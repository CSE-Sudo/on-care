// 식단 조언·추천 경로(/diet/advice, /diet/recommendations)와 하루 코치 한마디.

part of '../local_api_interceptor.dart';

extension _LocalApiDietAdvice on LocalApiInterceptor {
  /// GET /diet/advice — 기간에 맞는 식단 조언. (#1574)
  ///
  /// 실 서버(`/diet/advice`)와 **같은 규칙, 같은 문장**이다. 데모에 이 경로가
  /// 없던 동안에는 요청이 그대로 네트워크로 흘러 실패했고, 화면은 어쩔 수 없이
  /// 오늘 조언을 대신 그렸다 — `이번 주` 를 보면서 오늘 이야기를 읽게 되는
  /// 원인이 여기였다.
  ///
  /// 규칙 한 줄 + 다음 할 일(#2251·#2253·#2254)을 서버와 같은 규칙으로 만든다
  /// (`core/demo/diet_advice.dart`). 데모에는 AI 가 없어 이번 주·전체의 다음 할
  /// 일은 AI 가 실패했을 때의 규칙 문장이다.
  Future<Response<Object?>> _dietAdvice(RequestOptions options) async {
    final String? period = _advicePeriod(options);
    if (period == null) {
      return _unprocessable(options, 'period must be today, week or all');
    }
    final Object? rawLang = options.queryParameters['lang'];
    final String lang = rawLang is String && rawLang.isNotEmpty
        ? rawLang
        : 'ko';
    if (lang != 'ko' && lang != 'en') {
      return _unprocessable(options, 'lang must be ko or en');
    }
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    // 전체가 읽는 4주가 가장 길다 — 이번 주의 지난주 회고(최대 13일 전)도 그 안이다.
    final String start = wireDate(
      DateTime(today.year, today.month, today.day - 27),
    );
    final rows =
        await (_db.select(_db.dietEntries)
              ..where(
                (t) =>
                    t.date.isBiggerOrEqualValue(start) &
                    t.date.isSmallerOrEqualValue(wireDate(today)),
              )
              ..orderBy(<OrderClauseGenerator<$DietEntriesTable>>[
                (t) => OrderingTerm(expression: t.date),
                (t) => OrderingTerm(expression: t.createdAt),
              ]))
            .get();
    final List<DemoDietEntry> entries = <DemoDietEntry>[
      for (final DietEntryRow r in rows) _demoDietEntry(r),
    ];
    return _ok(
      options,
      demoDietAdvice(
        period: period,
        lang: lang,
        now: now,
        entries: entries,
        targets: demoDietTargets(await _mergedProfile()),
      ),
    );
  }

  /// 끼니 한 행 → 조언이 읽는 값. 탄단지는 행에 칼럼이 없어 음식에서 되짚는다.
  DemoDietEntry _demoDietEntry(DietEntryRow row) {
    final List<Object?> foods = jsonDecode(row.foodsJson) as List<Object?>;
    final _MacroTotals macros = _foodMacroTotals(foods);
    return (
      date: row.date,
      mealType: row.mealType,
      foods: <String>[
        for (final Object? food in foods)
          if (food is Map)
            if ((food['name'] as String?)?.trim() case final String n
                when n.isNotEmpty)
              n,
      ],
      kcal: row.totalCalories,
      proteinG: macros.proteinG,
      sodiumMg: row.sodiumMg,
      sugarG: row.sugarG,
      carbsG: macros.carbsG,
      fatG: macros.fatG,
    );
  }

  /// 조언 요청의 `period`. 기간 이름이 아니면 null 이다 — 서버가 422 로
  /// 답하므로 목업이 조용히 오늘로 흘려보내면 두 구현이 갈린다.
  String? _advicePeriod(RequestOptions options) {
    final Object? raw = options.queryParameters['period'];
    final String period = raw is String && raw.isNotEmpty ? raw : kPeriodToday;
    const Set<String> known = <String>{kPeriodToday, kPeriodWeek, kPeriodAll};
    return known.contains(period) ? period : null;
  }

  /// 기간 이름 → [시작, 끝] (양끝 포함). 서버 `period_window.period_bounds` 와
  /// 같은 규칙이다 — `이번 주` 는 월요일부터 오늘까지, `전체` 는 12주다.
  (String, String) _periodBounds(String period) {
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (period == kPeriodToday) {
      return (wireDate(today), wireDate(today));
    }
    if (period == kPeriodWeek) {
      return (wireDate(mondayOf(today)), wireDate(today));
    }
    final DateTime from = DateTime(
      today.year,
      today.month,
      today.day - (kAllPeriodWeeks * 7 - 1),
    );
    return (wireDate(from), wireDate(today));
  }

  /// GET /diet/recommendations — 홈 "AI 추천 식단".
  ///
  /// 서버(`diet_recommendation_service`)의 규칙 경로와 같다(#2661). 최근 3일 식단
  /// 기록의 하루 평균에서 신호(나트륨·당류 과다, 열량 과다·부족, 단백질 부족)를
  /// 뽑고, 신호와 맞는 메뉴를 앞으로 올린다. 데모에는 AI 가 없어 서버가 AI 에
  /// 실패했을 때의 규칙 순서다. `reason_text` 는 비워 두어 카드 문구는 앱의 l10n
  /// 기본값이 로케일을 따라간다.
  ///
  /// 기록이 없거나 신호가 없으면 서버처럼 `personalized: false` 다 — 화면이 그
  /// 값으로 근거 줄을 감추므로, 근거가 없는데 있는 척하지 않는다.
  Future<Response<Object?>> _dietRecommendations(RequestOptions options) async {
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final String start = wireDate(
      DateTime(today.year, today.month, today.day - (_recLookbackDays - 1)),
    );
    final rows =
        await (_db.select(_db.dietEntries)..where(
              (t) =>
                  t.date.isBiggerOrEqualValue(start) &
                  t.date.isSmallerOrEqualValue(wireDate(today)),
            ))
            .get();

    // 평균은 '기록이 있는 날' 기준이다 — 서버 `build_context` 와 같다.
    final Map<String, List<double>> perDay = <String, List<double>>{};
    for (final DietEntryRow r in rows) {
      final List<double> day = perDay.putIfAbsent(
        r.date,
        () => <double>[0, 0, 0, 0],
      );
      day[0] += r.sodiumMg;
      day[1] += r.sugarG;
      day[2] += r.totalCalories;
      day[3] += _foodMacroTotals(
        jsonDecode(r.foodsJson) as List<Object?>,
      ).proteinG;
    }
    final int n = perDay.length;
    double avg(int i) => n == 0
        ? 0
        : perDay.values.fold<double>(
                0,
                (double a, List<double> d) => a + d[i],
              ) /
              n;
    final int avgSodium = avg(0).truncate();
    final double avgSugar = avg(1);
    final int avgCalories = avg(2).truncate();
    final double avgProtein = avg(3);

    final Map<String, Object?> profile = await _mergedProfile();
    int? positive(Object? v) => v is num && v > 0 ? v.toInt() : null;
    final int sodiumLimit =
        positive(profile['daily_sodium_mg']) ?? kGoalDefaultDailySodiumMg;
    final int sugarLimit =
        positive(profile['daily_sugar_g']) ?? kGoalDefaultDailySugarG;
    final int calorieLimit =
        positive(profile['daily_calories']) ?? kGoalDefaultDailyCalories;
    final int proteinGoal = positive(profile['daily_protein_g']) ?? 0;

    final Set<String> signals = <String>{
      if (n > 0) ...<String>{
        if (avgSodium >= sodiumLimit * _recHighRatio) 'sodium_high',
        if (avgSugar >= sugarLimit * _recHighRatio) 'sugar_high',
        if (avgCalories >= calorieLimit * _recHighRatio)
          'calorie_high'
        else if (avgCalories > 0 && avgCalories <= calorieLimit * _recLowRatio)
          'calorie_low',
        if (proteinGoal > 0 && avgProtein <= proteinGoal * _recLowRatio)
          'protein_low',
      },
    };

    // 신호와 `good_for` 가 겹치는 만큼 점수를 준다. 동점은 기본 순서를 지킨다
    // (서버 `_rule_rank`). 신호가 없으면 정확히 기본 순서다.
    final List<MealRecommendation> base = MealRecommendations.fallback.items;
    int score(MealRecommendation m) =>
        (_recGoodFor[m.key] ?? const <String>{}).intersection(signals).length;
    final List<MealRecommendation> ranked = <MealRecommendation>[...base]
      ..sort((MealRecommendation a, MealRecommendation b) {
        final int byScore = score(b).compareTo(score(a));
        return byScore != 0 ? byScore : base.indexOf(a) - base.indexOf(b);
      });

    return _ok(options, <String, Object?>{
      'items': <Map<String, Object?>>[
        for (final MealRecommendation item in ranked)
          <String, Object?>{'key': item.key, 'reason_key': item.reasonKey},
      ],
      'personalized': n > 0 && signals.isNotEmpty,
      'days_with_data': n,
      'avg_sodium_mg': avgSodium,
      'sodium_limit_mg': sodiumLimit,
      'trainer_pick': _demoTrainerPick(options),
    });
  }

  /// 데모 담당 트레이너가 확정해 둔 식단 추천(#2380). 서버 `trainer_pick` 과 같은
  /// 모양이다. 4주 추천 메뉴 리스트(`kDemoMenuPlan`)의 저녁 고단백 메뉴를 쓴다 —
  /// 트레이너 웹 데모가 같은 리스트에서 후보를 낸다. 담당이 없는 데모 회원이면
  /// 홈이 담당을 확인해 그리지 않는다.
  Map<String, Object?> _demoTrainerPick(RequestOptions options) {
    final String lang = _requestLang(options);
    final DemoPlanMenu menu = (kDemoMenuPlan[lang] ?? kDemoMenuPlan['ko']!)
        .firstWhere(
          (DemoPlanMenu m) => m.slot == 'dinner' && m.tag == 'protein_high',
        );
    return <String, Object?>{
      'slot': menu.slot,
      'name': menu.name,
      'tag': menu.tag,
      'keyword': menu.keyword,
      'trainer_name': kDemoTrainerName,
    };
  }

  /// 하루 식단 코치 문장(`ai_coach_message`). 실 서버 `diet_service.build_day`
  /// 와 같은 규칙이다(#2644).
  ///
  /// - 한국어 화면이면 시드가 정해 둔 그날의 큐레이션 문장을 먼저 쓴다. 픽스처
  ///   문장이 한국어뿐이라, 영어 화면에서는 건너뛰고 수치 기반 문장을 쓴다.
  /// - 수치 기반 문장은 지난 날짜면 그날을 되짚고, 나트륨 기준은 회원 목표다.
  Future<String> _dietDayCoachMessage(
    RequestOptions options, {
    required String date,
    required int totalSodium,
    required bool empty,
  }) async {
    final String lang = _requestLang(options);
    if (lang == 'ko') {
      final String? curated = await _dietDayMessage(date);
      if (curated != null) return curated;
    }
    final Map<String, Object?> profile = await _mergedProfile();
    return LocalApiInterceptor.derivedDietDayMessage(
      lang: lang,
      totalSodium: totalSodium,
      empty: empty,
      isPast: date.compareTo(_todayDateString()) < 0,
      sodiumLimit: (profile['daily_sodium_mg'] as num?)?.toInt(),
    );
  }

  /// 회원이 식단·운동 기록을 바꿨다 — 시드가 큐레이션해 둔 문장을 거둔다(#2645).
  ///
  /// 홈 '오늘의 AI 통합 조언'(`dashboard_ai_advice`)과 식단 탭의 하루 코치
  /// 문장([kDietDayMessagesKey])은 시드의 기록에 맞춰 쓴 글이다. 기록을 지우거나
  /// 고친 뒤에도 남아 있으면, 끼니를 다 지운 홈이 여전히 "짬뽕 …" 을 말한다. 기록이
  /// 바뀐 뒤로는 실 서버처럼 지금 기록으로 만든 조언을 낸다.
  ///
  /// 통합 조언은 식단·운동 어느 쪽이 바뀌어도 거두고, 하루 코치 문장은
  /// [dietDates] 의 날짜만 거둔다. 다음 날 시드가 새로 깔리면 다시 채워진다.
  Future<void> _retireCuratedAdvice({
    List<String> dietDates = const <String>[],
  }) async {
    await _db.deleteValue('dashboard_ai_advice');
    if (dietDates.isEmpty) return;
    final String? raw = await _db.readValue(kDietDayMessagesKey);
    if (raw == null || raw.isEmpty) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    final Map<String, Object?> messages = Map<String, Object?>.of(decoded);
    final int before = messages.length;
    for (final String date in dietDates) {
      messages.remove(date);
    }
    if (messages.length == before) return;
    await _db.putValue(kDietDayMessagesKey, jsonEncode(messages));
  }

  /// 시드가 정해 둔 그 날짜의 코치 문구. 없으면 null.
  ///
  /// 시연에 쓰는 사흘은 문장이 정해져 있다(`kDietDayMessagesKey`). 그 날짜에
  /// 수치 기반 문구를 대신 쓰면 데모 화면의 문장이 바뀌므로 저장된 것을 먼저 본다.
  Future<String?> _dietDayMessage(String date) async {
    final String? raw = await _db.readValue(kDietDayMessagesKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final Object? message = decoded[date];
      return message is String && message.isNotEmpty ? message : null;
    } on FormatException {
      return null;
    }
  }
}

/// 추천 신호를 뽑는 기간(일). 서버 `LOOKBACK_DAYS` 와 같다.
const int _recLookbackDays = 3;

/// 한도의 몇 % 이상이면 과다, 미만이면 부족인지. 서버 `_HIGH_RATIO`·`_LOW_RATIO`.
const double _recHighRatio = 0.9;

const double _recLowRatio = 0.6;

/// 메뉴 → 도움이 되는 신호. 서버 `meal_catalog.CATALOG` 의 `good_for` 와 같다.
const Map<String, Set<String>> _recGoodFor = <String, Set<String>>{
  'chicken_salad': <String>{'sodium_high', 'protein_low'},
  'brown_rice_box': <String>{'sugar_high', 'calorie_low'},
  'salmon': <String>{'protein_low', 'sodium_high'},
  'tofu': <String>{'calorie_high'},
  'namul_bibimbap': <String>{'sugar_high'},
};

/// 회원 나트륨 목표가 없을 때의 하루 상한. 서버 `SODIUM_LIMIT_MG` 와 같다.
const int _kDefaultSodiumLimitMg = kGoalDefaultDailySodiumMg;

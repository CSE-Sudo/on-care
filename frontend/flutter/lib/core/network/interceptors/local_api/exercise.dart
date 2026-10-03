// 운동 경로(/exercise/weeks, /exercise/sessions, /exercise/advice, /exercise/calories).

part of '../local_api_interceptor.dart';

extension _LocalApiExercise on LocalApiInterceptor {
  Future<Response<Object?>> _exerciseDelete(RequestOptions options) async {
    final id = options.path.split('/').last;
    final existing = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return _notFound(options, '운동 기록을 찾을 수 없습니다.');
    if (existing.source != 'member') return _derivedExercise(options);
    await (_db.delete(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).go();
    _points.revoke(PointsRule.exerciseManual.sourceType, id);
    await _retireCuratedAdvice();
    return _ok(options, <String, Object?>{'status': 'deleted'});
  }

  /// PT·배정 루틴에서 파생된 기록은 회원이 고치거나 지울 수 없다 — 서버
  /// (`exercise.py` 의 `_reject_if_derived`)와 같은 409 다. 기록은 분명히 있으므로
  /// 404 로 없는 척하지 않는다. (#499, #638, #2662)
  Response<Object?> _derivedExercise(RequestOptions options) =>
      Response<Object?>(
        requestOptions: options,
        statusCode: 409,
        data: <String, Object?>{'detail': '코칭에서 생성된 운동 기록은 수정하거나 삭제할 수 없습니다.'},
      );

  Future<Response<Object?>> _exerciseUpdate(RequestOptions options) async {
    final id = options.path.split('/').last;
    final existing = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return _notFound(options, '운동 기록을 찾을 수 없습니다.');
    if (existing.source != 'member') return _derivedExercise(options);
    final body = _jsonBody(options);
    final type = (body['type'] as String? ?? existing.type).trim();
    final durationSeconds = body.containsKey('duration_seconds')
        ? (body['duration_seconds'] as num?)?.toInt()
        : existing.durationSeconds;
    final minutes = durationSeconds != null
        ? minutesFromSeconds(durationSeconds)
        : ((body['minutes'] as num?)?.toInt() ?? existing.minutes);
    final intensity = (body['intensity'] as String? ?? existing.intensity)
        .trim();
    final name = ((body['name'] as String?) ?? existing.name).trim();
    // 앱이 보낸 `calories` 는 쓰지 않는다 — 실 서버와 같은 규약이다(#1312).
    // 계산이 한 곳이라야 미리보기와 저장된 기록의 숫자가 갈리지 않는다.
    final estimated = await _demoEstimate(
      name: name,
      type: type,
      minutes: minutes,
      intensity: intensity,
    );
    // 유형을 근력에서 바꾼 수정이면 세트·횟수·중량이 지워진다 — 남겨 두면
    // 유산소 기록이 세트를 들고 있게 된다.
    final sets = _strengthOnly(
      type,
      body.containsKey('sets')
          ? (body['sets'] as num?)?.toInt()
          : existing.sets,
    );
    // 회↔초를 되돌린 수정도 같은 규칙이다 — 초가 실려 오면 횟수를 비운다.
    // (#1969)
    final holdSeconds = _strengthOnly(
      type,
      body.containsKey('hold_seconds')
          ? (body['hold_seconds'] as num?)?.toInt()
          : existing.holdSeconds,
    );
    final reps = holdSeconds != null
        ? null
        : _strengthOnly(
            type,
            body.containsKey('reps')
                ? (body['reps'] as num?)?.toInt()
                : existing.reps,
          );
    final weight = _strengthOnly(
      type,
      body.containsKey('weight')
          ? (body['weight'] as num?)?.toDouble()
          : existing.weight,
    );
    // 날짜를 주지 않은 수정은 원래 자리를 그대로 둔다 — 오늘로 끌어오면 지난
    // 기록을 고치기만 해도 이번 주로 옮겨 간다.
    final (String weekStart, String dayLabel) = body['date'] is String
        ? _placement(body['date'])
        : (existing.weekStart, existing.dayLabel);
    await (_db.update(
      _db.exerciseSessions,
    )..where((t) => t.id.equals(id))).write(
      ExerciseSessionsCompanion(
        type: Value(type),
        name: Value(name),
        minutes: Value(minutes),
        calories: Value(estimated.calories),
        intensity: Value(intensity),
        weekStart: Value(weekStart),
        dayLabel: Value(dayLabel),
        sets: Value(sets),
        reps: Value(reps),
        holdSeconds: Value(holdSeconds),
        durationSeconds: Value(durationSeconds),
        weight: Value(weight),
      ),
    );
    // 기록을 보호권으로 이어 붙인 날로 옮겼으면 그 보호권을 되돌린다(#1788).
    _refundShieldOn(weekStart, dayLabel);
    await _retireCuratedAdvice();
    return _ok(
      options,
      _sessionJson(
        id: id,
        weekStart: weekStart,
        dayLabel: dayLabel,
        type: type,
        name: name,
        minutes: minutes,
        sets: sets,
        reps: reps,
        holdSeconds: holdSeconds,
        durationSeconds: durationSeconds,
        weight: weight,
        calories: estimated.calories,
        intensity: intensity,
        calorieSource: estimated.source,
      ),
    );
  }

  /// GET /exercise/weeks/current[?week_start=YYYY-MM-DD]
  ///
  /// `week_start` 없이 부르면 이번 주다(예전 동작 그대로). 운동 탭이 주를 뒤로
  /// 넘길 때 그 주의 월요일을 실어 보낸다(#671) — 그 전에는 조회 경로가 이번
  /// 주 하나뿐이라 지난주를 받아올 방법이 없었다.
  /// GET /exercise/advice — 기간에 맞는 운동 조언. (#1574)
  ///
  /// 식단 조언과 같은 규칙이다. 운동 기록은 날짜가 아니라 (그 주 월요일, 요일)
  /// 로 저장돼 있어, 구간이 걸치는 주를 모두 읽어 실제 날짜로 되돌린 뒤 거른다
  /// — 서버(`exercise_service.period_days`)가 하는 일과 같다.
  Future<Response<Object?>> _exerciseAdvice(RequestOptions options) async {
    final String? period = _advicePeriod(options);
    if (period == null) {
      return _unprocessable(options, 'period must be today, week or all');
    }
    final (String start, String end) = _periodBounds(period);
    final List<String> weeks = _weekStartsCovering(start, end);
    final rows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.isIn(weeks))).get();

    final Map<String, ({int minutes, int calories, Map<String, int> byType})>
    perDate =
        <String, ({int minutes, int calories, Map<String, int> byType})>{};
    for (final r in rows) {
      final int index = _weekdayLabels.indexOf(r.dayLabel);
      if (index < 0) continue;
      final DateTime monday = DateTime.parse(r.weekStart);
      final String date = wireDate(
        DateTime(monday.year, monday.month, monday.day + index),
      );
      if (date.compareTo(start) < 0 || date.compareTo(end) > 0) continue;
      final ({int minutes, int calories, Map<String, int> byType}) day =
          perDate[date] ?? (minutes: 0, calories: 0, byType: <String, int>{});
      // 서버 `exercise_types.normalize` 와 같은 공용 표 — 한글 라벨·옛 값도
      // 제 유형 칸에 들어간다(#2861).
      final String kind = normalizeExerciseType(r.type);
      day.byType[kind] = (day.byType[kind] ?? 0) + r.minutes;
      perDate[date] = (
        minutes: day.minutes + r.minutes,
        calories: day.calories + r.calories,
        byType: day.byType,
      );
    }

    final List<String> dates = perDate.keys.toList()..sort();
    final List<ExerciseDayTotals> days = <ExerciseDayTotals>[
      for (final String date in dates)
        (
          date: DateTime.parse(date),
          minutes: perDate[date]!.minutes,
          calories: perDate[date]!.calories,
          byType: perDate[date]!.byType,
        ),
    ];

    // 추천 개인운동도 서버와 같은 구간을 읽는다(#2162, #2662).
    final DateTime today = _dateOnly(nowKst());
    final ExerciseAdvice advice = exercisePeriodAdviceOf(
      days,
      period,
      routineDays:
          routineDays?.call(routineAdviceFetchStart(period, today), today) ??
          const <RoutineAdviceDay>[],
    );
    return _ok(options, <String, Object?>{
      'period': period,
      'from_date': start,
      'to_date': end,
      'days_logged': days.length,
      'message': advice.message,
      // 서버처럼 문장 키·값도 준다(#2210).
      'advice_key': advice.key,
      'advice_params': advice.params,
    });
  }

  /// [start, end] 를 덮는 모든 주의 월요일. 구간의 첫날이 주 가운데면 그 주
  /// 월요일부터 담는다 — 월요일이 구간 밖이어도 그 주의 기록은 구간 안에 있을
  /// 수 있다.
  List<String> _weekStartsCovering(String start, String end) {
    final DateTime from = mondayOf(DateTime.parse(start));
    final DateTime to = DateTime.parse(end);
    final List<String> weeks = <String>[];
    for (
      DateTime week = from;
      !week.isAfter(to);
      week = DateTime(week.year, week.month, week.day + 7)
    ) {
      weeks.add(wireDate(week));
    }
    return weeks;
  }

  /// `GET /exercise/weeks?from=&to=` — 구간이 걸친 주들. (#2247)
  ///
  /// 주마다의 집계는 [_exerciseCurrentWeek] 을 그대로 부른다 — 데모에서도 한 주
  /// 조회와 기간 조회의 숫자가 갈리면 안 된다. 서버도 같은 함수를 기간만큼
  /// 부른다(`exercise_service.build_period`). 그 응답에서 그래프가 쓰지 않는
  /// `sessions`·`ai_coach_message` 는 덜어 낸다.
  Future<Response<Object?>> _exercisePeriod(RequestOptions options) async {
    for (final String key in const <String>['from', 'to']) {
      final Object? raw = options.queryParameters[key];
      if (raw != null && (raw is! String || !_isDateString(raw))) {
        return _unprocessable(options, '\$key must be YYYY-MM-DD');
      }
    }
    final DateTime thisMonday = mondayOf(nowKst());
    DateTime lastMonday = _queryDate(options, 'to') == null
        ? thisMonday
        : mondayOf(_queryDate(options, 'to')!);
    if (lastMonday.isAfter(thisMonday)) lastMonday = thisMonday;
    final DateTime? fromQuery = _queryDate(options, 'from');
    DateTime firstMonday;
    if (fromQuery != null) {
      firstMonday = mondayOf(fromQuery);
    } else {
      final Set<String> days = await _exerciseDates();
      firstMonday = days.isEmpty
          ? lastMonday
          : mondayOf(DateTime.parse((days.toList()..sort()).first));
    }
    if (firstMonday.isAfter(lastMonday)) firstMonday = lastMonday;
    // 서버와 같은 구간 상한(`exercise_service.MAX_PERIOD_WEEKS`, #2833).
    final DateTime floorMonday = DateTime(
      lastMonday.year,
      lastMonday.month,
      lastMonday.day - (kExerciseMaxPeriodWeeks - 1) * 7,
    );
    if (firstMonday.isBefore(floorMonday)) firstMonday = floorMonday;

    const List<String> carried = <String>[
      'day_labels',
      'daily_minutes',
      'daily_calories',
      'cardio_minutes',
      'strength_minutes',
      'strength_sets',
      'stretching_minutes',
      'other_minutes',
      'total_minutes',
      'total_calories',
      'streak_days',
    ];
    final List<Map<String, Object?>> weeks = <Map<String, Object?>>[];
    DateTime cursor = firstMonday;
    while (!cursor.isAfter(lastMonday)) {
      final String monday = wireDate(cursor);
      final Response<Object?> week = await _exerciseCurrentWeek(
        options.copyWith(
          queryParameters: <String, Object?>{'week_start': monday},
        ),
      );
      final Map<String, Object?> body =
          (week.data as Map<String, Object?>?) ?? const <String, Object?>{};
      weeks.add(<String, Object?>{
        'week_start': monday,
        for (final String key in carried) key: body[key],
      });
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 7);
    }
    return _ok(options, <String, Object?>{
      'from_week': wireDate(firstMonday),
      'to_week': wireDate(lastMonday),
      'weeks': weeks,
    });
  }

  Future<Response<Object?>> _exerciseCurrentWeek(RequestOptions options) async {
    // 저장된 기록의 칼로리 근거를 되짚을 때 쓴다 — 이름이 종목표에 붙어도
    // 체중을 모르면 어림값으로 계산된 기록이다(`_demoEstimate` 와 같은 판단).
    final double? weightKg = ((await _mergedProfile())['weight_kg'] as num?)
        ?.toDouble();
    // 파라미터가 **있으면** 그 값을 그대로 검사한다. 빈 문자열도 "잘못된 값"이다
    // — 서버(FastAPI)가 그렇게 답하므로 여기서 조용히 이번 주로 흘려보내면 두
    //   구현이 갈린다.
    final bool hasWeekStart = options.queryParameters.containsKey('week_start');
    final String weekStart;
    if (hasWeekStart) {
      final Object? requested = options.queryParameters['week_start'];
      final String raw = requested is String ? requested : '';
      if (!_isDateString(raw)) {
        return _unprocessable(options, 'week_start must be YYYY-MM-DD');
      }
      // 월요일이 아닌 날짜를 줘도 그 날이 속한 주로 맞춘다 — 서버의
      // `monday_of_str` 과 같은 규칙(backend/API_CONTRACT.md).
      weekStart = _mondayOfString(raw);
    } else {
      weekStart = _mondayOfThisWeekString();
    }
    final rows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.equals(weekStart))).get();

    // Aggregate minutes per day-label so the bar chart can render even
    // when a day is missing (React mock left Tue=0).
    final perDay = <String, int>{for (final l in _weekdayLabels) l: 0};
    // 일별 소모 칼로리 — 홈 '주간 추이' 차트가 읽는 시리즈. 없으면 클라이언트가
    // 데모 상수로 폴백하므로 분(minutes) 시리즈와 같이 내려준다.
    final perDayCalories = <String, int>{for (final l in _weekdayLabels) l: 0};
    final perDayCardio = <String, int>{for (final l in _weekdayLabels) l: 0};
    final perDayStrength = <String, int>{for (final l in _weekdayLabels) l: 0};
    // 근력은 세트로 읽는다 — 기록에 세트가 있으면 그 값을, 없으면 분에서
    // 환산한 값을 센다(서버 `sets_of` 와 같은 규칙). (#1262)
    final perDayStrengthSets = <String, int>{
      for (final l in _weekdayLabels) l: 0,
    };
    final perDayStretching = <String, int>{
      for (final l in _weekdayLabels) l: 0,
    };
    // 기타는 유산소에 얹지 않는다 — 서버가 그렇게 세지 않는다 (#996). 목업이
    // 서버와 다르게 세면 데모(목업)와 실 API 화면의 그래프가 갈라진다. (#997)
    final perDayOther = <String, int>{for (final l in _weekdayLabels) l: 0};
    int totalMinutes = 0;
    int totalCalories = 0;
    final sessionsJson = <Map<String, Object?>>[];

    for (final r in rows) {
      totalMinutes += r.minutes;
      totalCalories += r.calories;
      perDay.update(
        r.dayLabel,
        (m) => m + r.minutes,
        ifAbsent: () => r.minutes,
      );
      perDayCalories.update(
        r.dayLabel,
        (c) => c + r.calories,
        ifAbsent: () => r.calories,
      );
      // 서버 `exercise_types.normalize` 와 같은 공용 표로 칸을 고른다(#2861).
      final bucket = switch (normalizeExerciseType(r.type)) {
        kExerciseTypeCardio => perDayCardio,
        kExerciseTypeStrength => perDayStrength,
        kExerciseTypeStretching => perDayStretching,
        _ => perDayOther,
      };
      bucket.update(
        r.dayLabel,
        (m) => m + r.minutes,
        ifAbsent: () => r.minutes,
      );
      if (identical(bucket, perDayStrength)) {
        final int sets =
            r.sets ?? setsFromStrengthMinutes(r.minutes.toDouble());
        perDayStrengthSets.update(
          r.dayLabel,
          (n) => n + sets,
          ifAbsent: () => sets,
        );
      }
      // Date/time labels are synthesized in `_sessionJson` so the
      // React-style session list ("오늘", "어제", "MM월 DD일") works
      // without a schema migration on the drift `exerciseSessions` table.
      sessionsJson.add(
        _sessionJson(
          id: r.id,
          weekStart: weekStart,
          dayLabel: r.dayLabel,
          type: r.type,
          name: r.name,
          minutes: r.minutes,
          sets: r.sets,
          reps: r.reps,
          holdSeconds: r.holdSeconds,
          durationSeconds: r.durationSeconds,
          weight: r.weight,
          calories: r.calories,
          intensity: r.intensity,
          // 저장된 기록의 근거는 이름을 다시 붙여 되짚는다. 데모는 이름 해석
          // AI 를 타지 않으므로 쓰기 때와 같은 답이 나온다 — drift 스키마에
          // 컬럼을 더하지 않으려고 이 자리에서 되살린다.
          calorieSource:
              matchDemoExercise(r.name) != null &&
                  weightKg != null &&
                  weightKg > 0
              ? 'db'
              : 'estimate',
          source: r.source,
          assignedRoutineId: r.assignedRoutineId,
        ),
      );
    }
    // Most recent first so the prototype's grouping (today / yesterday
    // / older) reads top-down.
    sessionsJson.sort((a, b) {
      final ai = _weekdayLabels.indexOf(a['day_label']! as String);
      final bi = _weekdayLabels.indexOf(b['day_label']! as String);
      return bi - ai;
    });

    final dailyMinutes = <num>[for (final l in _weekdayLabels) perDay[l] ?? 0];
    final dailyCalories = <num>[
      for (final l in _weekdayLabels) perDayCalories[l] ?? 0,
    ];
    final cardioSeries = <num>[
      for (final l in _weekdayLabels) perDayCardio[l] ?? 0,
    ];
    final strengthSeries = <num>[
      for (final l in _weekdayLabels) perDayStrength[l] ?? 0,
    ];
    final stretchingSeries = <num>[
      for (final l in _weekdayLabels) perDayStretching[l] ?? 0,
    ];
    final otherSeries = <num>[
      for (final l in _weekdayLabels) perDayOther[l] ?? 0,
    ];

    // 운동 탭의 연속은 운동만 센다 — 보호권은 기록 연속(식단·운동)을 지키고
    // 포인트 화면에서 쓴다(#1788, #2075).
    final streak = _longestActiveStreak(dailyMinutes);

    return _ok(options, <String, Object?>{
      'sessions': sessionsJson,
      'daily_minutes': dailyMinutes,
      'daily_calories': dailyCalories,
      'cardio_minutes': cardioSeries,
      'strength_minutes': strengthSeries,
      'strength_sets': <num>[
        for (final l in _weekdayLabels) perDayStrengthSets[l] ?? 0,
      ],
      // 서버와 같은 이름으로 함께 내려준다 — stretching 이 표준이고
      // flexibility 는 옮겨 가는 동안의 옛 이름이다. (#996, #1276)
      'stretching_minutes': stretchingSeries,
      'flexibility_minutes': stretchingSeries,
      'other_minutes': otherSeries,
      'day_labels': _weekdayLabels,
      'total_minutes': totalMinutes,
      'total_calories': totalCalories,
      'streak_days': streak,
      'ai_coach_message': totalMinutes >= 240
          ? '주간 운동 목표 80%를 달성했어요! 오늘 가볍게 걷기를 더해 100%를 채워봐요.'
          : '이번 주는 운동량이 조금 부족해요. 가벼운 산책부터 다시 시작해 봐요.',
    });
  }

  /// "N일 연속" — 운동한 요일 중 가장 긴 연속 구간의 길이. 활성 일수의 단순
  /// 합계가 아니다(월·수·금 운동은 3일이 아니라 1일 연속). FastAPI
  /// `exercise_service._longest_streak`, 그리고 클라이언트의
  /// `longestActiveStreak` 와 같은 정의라야 '연속' 카드가 어느 경로에서든
  /// 같은 값을 보인다. 보호권으로 이어 붙인 날([protectedDays])도 운동한 날로
  /// 센다(#1788).
  int _longestActiveStreak(List<num> dailyMinutes) {
    int best = 0;
    int run = 0;
    for (int i = 0; i < dailyMinutes.length; i++) {
      if (dailyMinutes[i] > 0) {
        run += 1;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }

  /// "오늘 / 어제 / MM월 DD일" for a weekday label inside [weekStart]'s week.
  ///
  /// 요일만으로는 어느 주인지 알 수 없어 지난주 기록에도 '오늘'이 붙던 문제가
  /// 있었다. 주의 월요일에서 실제 날짜를 되짚어 오늘과 견준다.
  String _dateLabelForDayLabel(String dayLabel, String weekStart) {
    final dayIdx = _weekdayLabels.indexOf(dayLabel);
    final monday = DateTime.tryParse(weekStart);
    if (dayIdx < 0 || monday == null) return dayLabel;
    // Duration 이 아니라 날짜 성분으로 더한다(서머타임 안전).
    final date = DateTime(monday.year, monday.month, monday.day + dayIdx);
    final now = nowKst();
    final today = DateTime(now.year, now.month, now.day);
    final delta = today
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (delta == 0) return '오늘';
    if (delta == 1) return '어제';
    return '${date.month}월 ${date.day}일';
  }

  List<String> _defaultItems(String type) => switch (type) {
    'cardio' => const <String>['러닝머신 30분'],
    'strength' => const <String>['스쿼트 3세트', '데드리프트 3세트'],
    'yoga' || 'stretching' || 'flexibility' => const <String>['전신 스트레칭 20분'],
    'walking' => const <String>['공원 산책'],
    _ => const <String>[],
  };

  /// 근력에서만 의미 있는 값(세트·중량). 다른 유형에서 온 값은 버린다 — 서버
  /// (`_strength_only`)와 같은 규칙이라야 데모와 실 API 가 같은 기록을 남긴다.
  /// (#1262, #1276)
  T? _strengthOnly<T>(String type, T? value) =>
      type.trim() == 'strength' ? value : null;

  /// 요청이 고른 날의 (주 시작 월요일, 요일 라벨). 날짜가 없으면 오늘이다.
  ///
  /// 예전에는 요일 라벨만 받고 주차는 늘 이번 주로 박았다 — 지난 날짜를 골라도
  /// 기록이 이번 주로 들어왔다. (#1276)
  (String, String) _placement(Object? raw) {
    final DateTime day = raw is String
        ? (DateTime.tryParse(raw) ?? nowKst())
        : nowKst();
    return (_mondayOf(day), _weekdayLabels[day.weekday - 1]);
  }

  /// POST /exercise/calories — 운동 이름·시간·강도로 예상 소모 칼로리. (#1312)
  ///
  /// 서버와 같은 순서다: 이름을 종목표에 붙이고, 붙었으면 계수 × 데모 회원 체중
  /// 으로, 안 붙었으면 유형 평균으로 계산한다. 이름 해석 AI 는 데모에 없으므로
  /// `mixed` 는 여기서 나오지 않는다 — 없는 근거를 있는 척하지 않는다.
  Future<Response<Object?>> _exerciseCalories(RequestOptions options) async {
    final Map<String, Object?> payload = _payloadOf(options.data);
    final String name = ((payload['name'] as String?) ?? '').trim();
    if (name.isEmpty) {
      return _badRequest(options, '운동 이름을 입력해 주세요.');
    }
    final int minutes = (payload['minutes'] as num?)?.toInt() ?? 0;
    if (minutes <= 0) {
      return _badRequest(options, 'minutes must be > 0');
    }
    final ({int calories, String source, String matchedName}) result =
        await _demoEstimate(
          name: name,
          type: payload['type'] as String?,
          minutes: minutes,
          intensity: payload['intensity'] as String?,
        );
    return _ok(options, <String, Object?>{
      'calories': result.calories,
      'source': result.source,
      'matched_name': result.matchedName,
      // 데모에는 종목 참조표의 `isometric` 표시가 없다 — 이름 조각으로 본다.
      // 폼이 `횟수` 대신 `초` 를 물을지의 기본값이다(#1969).
      'isometric': isIsometricExerciseName(name),
    });
  }

  /// 데모의 소모 칼로리 계산 — 미리보기와 저장이 **같은 자리**를 쓴다. 서버가
  /// 저장할 때 다시 계산하는 것과 같은 규약이라, 데모에서도 화면의 숫자와
  /// 기록의 숫자가 갈리지 않는다.
  Future<({int calories, String source, String matchedName})> _demoEstimate({
    required String name,
    required String? type,
    required int minutes,
    required String? intensity,
  }) async {
    // 유형 표기는 서버 `exercise_types.normalize` 와 같은 공용 표로 접는다 —
    // 한글 라벨(`유산소`)도 기타로 떨어지지 않는다(#2861).
    // 강도 배수·유형별 분당 kcal 폴백은 서버 `exercise_catalog.energy` 와 같은
    // 공용 표(`oncare_rules`)다(#2906).
    final double factor = exerciseIntensityFactor(intensity);
    final DemoExerciseActivity? matched = matchDemoExercise(name);
    final double? weightKg = ((await _mergedProfile())['weight_kg'] as num?)
        ?.toDouble();
    // 체중을 모르면 참조표로 계산하지 않는다 — 기준 체중으로 낸 값은 이 회원의
    // 값이 아닌데 `db` 로 표시되면 실제보다 높은 신뢰 신호를 준다.
    if (matched == null || weightKg == null || weightKg <= 0) {
      return (
        calories: fallbackExerciseCalories(type, minutes, intensity),
        source: 'estimate',
        matchedName: '',
      );
    }
    return (
      calories: demoCatalogCalories(matched, minutes, factor, weightKg),
      source: 'db',
      matchedName: matched.name,
    );
  }

  /// POST /exercise/sessions — 운동 기록 1~N개를 한 번에 저장한다. (#2544)
  ///
  /// 실 서버처럼 **전부 되거나 전부 안 된다** — 항목을 모두 먼저 검사하고,
  /// 하나라도 잘못되면 아무것도 넣지 않는다. 적립은 기록마다 하고(하루 한도도
  /// 기록마다 센다) 응답에는 합계 한 벌을 싣는다.
  Future<Response<Object?>> _exerciseAddSession(RequestOptions options) async {
    final Object? raw = _payloadOf(options.data)['sessions'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > kMaxExerciseSessionsPerSave) {
      return _unprocessable(
        options,
        'sessions must hold 1..$kMaxExerciseSessionsPerSave items',
      );
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (final Object? item in raw)
        if (item is Map) item.cast<String, Object?>(),
    ];
    if (items.length != raw.length || items.any((i) => _minutesOf(i) <= 0)) {
      return _unprocessable(options, 'minutes must be > 0');
    }
    final String batch = '${DateTime.now().microsecondsSinceEpoch}';
    final List<Map<String, Object?>> sessions = <Map<String, Object?>>[];
    int awarded = 0;
    int balance = 0;
    for (int i = 0; i < items.length; i++) {
      final ({Map<String, Object?> session, PointsAward points}) saved =
          await _insertExerciseSession(items[i], id: 'ex-$batch-$i');
      sessions.add(saved.session);
      awarded += saved.points.awarded;
      balance = saved.points.balance;
    }
    return _ok(options, <String, Object?>{
      'sessions': sessions,
      'points': PointsAward(awarded: awarded, balance: balance).toJson(),
    });
  }

  /// 기록 한 건의 분. 초가 오면 그쪽이 맞고 분은 여기서 파생된다 — 실 서버
  /// (`ExerciseSessionCreate._minutes_from_seconds`)와 같은 규칙이라야, 같은
  /// 기록이 데모와 실서버에서 다른 길이로 읽히지 않는다. (#2071)
  int _minutesOf(Map<String, Object?> payload) {
    final int? durationSeconds = (payload['duration_seconds'] as num?)?.toInt();
    return durationSeconds != null
        ? minutesFromSeconds(durationSeconds)
        : ((payload['minutes'] as num?)?.toInt() ?? 0);
  }

  /// 검사를 마친 기록 한 건을 drift 에 넣고 응답 한 칸과 적립을 돌려준다.
  /// `ex-` 접두(`seed-` 가 아닌)라 seedIfEmpty 가 지우지 않는다.
  Future<({Map<String, Object?> session, PointsAward points})>
  _insertExerciseSession(
    Map<String, Object?> payload, {
    required String id,
  }) async {
    final type = (payload['type'] as String?) ?? 'cardio';
    final durationSeconds = (payload['duration_seconds'] as num?)?.toInt();
    final minutes = _minutesOf(payload);
    final intensity = (payload['intensity'] as String?) ?? 'moderate';
    final name = ((payload['name'] as String?) ?? '').trim();
    // 실 서버와 같이 여기서 다시 계산한다 — 앱이 보낸 값은 쓰지 않는다(#1312).
    final estimated = await _demoEstimate(
      name: name,
      type: type,
      minutes: minutes,
      intensity: intensity,
    );
    final sets = _strengthOnly(type, (payload['sets'] as num?)?.toInt());
    // 한 세트는 회로든 초로든 한 번만 잰다 — 초가 오면 횟수를 비운다(#1969).
    final holdSeconds = _strengthOnly(
      type,
      (payload['hold_seconds'] as num?)?.toInt(),
    );
    final reps = holdSeconds != null
        ? null
        : _strengthOnly(type, (payload['reps'] as num?)?.toInt());
    final weight = _strengthOnly(type, (payload['weight'] as num?)?.toDouble());
    final (String weekStart, String dayLabel) = _placement(payload['date']);

    await _db
        .into(_db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: id,
            weekStart: weekStart,
            dayLabel: dayLabel,
            type: type,
            name: Value(name),
            minutes: minutes,
            calories: estimated.calories,
            intensity: Value(intensity),
            sets: Value(sets),
            reps: Value(reps),
            holdSeconds: Value(holdSeconds),
            durationSeconds: Value(durationSeconds),
            weight: Value(weight),
          ),
        );
    // 보호권으로 이어 붙인 날에 기록이 생기면 그 보호권을 되돌린다(#1788).
    _refundShieldOn(weekStart, dayLabel);
    await _retireCuratedAdvice();

    return (
      session: _sessionJson(
        id: id,
        weekStart: weekStart,
        dayLabel: dayLabel,
        type: type,
        name: name,
        minutes: minutes,
        sets: sets,
        reps: reps,
        holdSeconds: holdSeconds,
        durationSeconds: durationSeconds,
        weight: weight,
        calories: estimated.calories,
        intensity: intensity,
        calorieSource: estimated.source,
      ),
      // 운동 직접 추가 +20P, 하루 3회(#1786). 생성 응답에만 싣는다 — 수정 응답은
      // 같은 모양을 쓰지만 적립이 없다.
      points: _points.award(PointsRule.exerciseManual, id),
    );
  }

  /// 단건 응답 한 벌. 생성과 수정이 같은 모양을 내야 앱이 두 경로에서 같은
  /// 기록을 읽는다.
  Map<String, Object?> _sessionJson({
    required String id,
    required String weekStart,
    required String dayLabel,
    required String type,
    required String name,
    required int minutes,
    required int? sets,
    required int? reps,
    required int? holdSeconds,
    required int? durationSeconds,
    required double? weight,
    required int calories,
    required String intensity,
    required String calorieSource,
    String source = 'member',
    String? assignedRoutineId,
  }) => <String, Object?>{
    'id': id,
    'day_label': dayLabel,
    'date': _dateOfWeekday(weekStart, dayLabel),
    'type': type,
    'name': name,
    'minutes': minutes,
    'sets': sets,
    'reps': reps,
    'hold_seconds': holdSeconds,
    'duration_seconds': durationSeconds,
    'weight': weight,
    'calories': calories,
    'calorie_source': calorieSource,
    'intensity': intensity,
    'date_label': _dateLabelForDayLabel(dayLabel, weekStart),
    // 시각은 PT 를 받은 날에만 있다 — 데모 픽스처는 PT 를 18:00 수업으로 둔다.
    // 개인운동·회원 기록은 언제 했는지를 남기지 않으므로 지어내지 않는다.
    // 유형별 기본 시각을 붙이면 개인운동 카드에 `07:30 수업 완료` 가 선다.
    // (#1884, #2662)
    'time_label': source == 'trainer_pt' ? '18:00' : null,
    'items': name.isEmpty ? _defaultItems(type) : <String>[name],
    // 누가 만든 기록인가 — 앱은 이 값으로 `직접 추가한 운동` 과 PT·배정 루틴
    // 기록을 가르고 연필을 붙인다(#499, #638). 배정 이름은 서버처럼 그 운동의
    // 이름이다. (#2662)
    'source': source,
    'assigned_routine_id': assignedRoutineId,
    'assigned_routine_name': assignedRoutineId == null ? '' : name,
  };

  /// (주 시작, 요일 라벨) → `YYYY-MM-DD`. FastAPI `session_date_of` 와 같다.
  String _dateOfWeekday(String weekStart, String dayLabel) {
    final DateTime? monday = DateTime.tryParse(weekStart);
    final int index = _weekdayLabels.indexOf(dayLabel);
    if (monday == null || index < 0) return weekStart;
    return wireDate(DateTime(monday.year, monday.month, monday.day + index));
  }
}

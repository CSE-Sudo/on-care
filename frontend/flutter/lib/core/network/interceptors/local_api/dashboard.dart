// 홈 요약과 기록 기간 경로(/dashboard/summary, /me/records/span).

part of '../local_api_interceptor.dart';

extension _LocalApiDashboard on LocalApiInterceptor {
  Future<Response<Object?>> _dashboardSummary(RequestOptions options) async {
    final today = _todayDateString();
    final profile = await _mergedProfile();
    final int calorieGoal =
        (profile['daily_calories'] as num?)?.toInt() ??
        kGoalDefaultDailyCalories;
    final int sodiumGoal =
        (profile['daily_sodium_mg'] as num?)?.toInt() ??
        kGoalDefaultDailySodiumMg;
    final int sugarGoal =
        (profile['daily_sugar_g'] as num?)?.toInt() ?? kGoalDefaultDailySugarG;

    // Diet aggregates.
    final dietRows = await (_db.select(
      _db.dietEntries,
    )..where((t) => t.date.equals(today))).get();
    int totalCalories = 0;
    int totalSodium = 0;
    double totalSugar = 0;
    var totalCarbs = 0.0;
    var totalProtein = 0.0;
    var totalFat = 0.0;
    final sodiumByFoodName = <String, int>{};
    for (final r in dietRows) {
      totalCalories += r.totalCalories;
      totalSodium += r.sodiumMg;
      totalSugar += r.sugarG;
      final foods = (jsonDecode(r.foodsJson) as List<Object?>).cast<Object?>();
      final macros = _foodMacroTotals(foods);
      totalCarbs += macros.carbsG;
      totalProtein += macros.proteinG;
      totalFat += macros.fatG;
      for (final food in foods) {
        if (food is! Map) continue;
        final name = (food['name'] as String? ?? '').trim();
        final sodium = (food['sodium_mg'] as num?)?.toInt() ?? 0;
        if (name.isNotEmpty && sodium > 0) {
          sodiumByFoodName.update(
            name,
            (total) => total + sodium,
            ifAbsent: () => sodium,
          );
        }
      }
    }
    final sodiumSources = sodiumByFoodName.entries.toList()
      ..sort((a, b) {
        final sodiumOrder = b.value.compareTo(a.value);
        return sodiumOrder != 0 ? sodiumOrder : a.key.compareTo(b.key);
      });
    // 경고가 짚는 상위 급원 두 개. 서버(`dashboard._SODIUM_SOURCE_COUNT`)와 같다.
    final List<String> sodiumSourceNames = <String>[
      for (final MapEntry<String, int> source in sodiumSources.take(2))
        source.key,
    ];
    final String lang = _requestLang(options);

    // 데모 시드가 큐레이션 '통합 조언'을 준비해 뒀는지. 있으면 그것을 우선
    // 노출하고, 없으면(시드 없는 테스트 DB, 회원이 기록을 바꿔 거둔 뒤 —
    // [_retireCuratedAdvice]) 나트륨 상위 급원 기반 경고를 동적으로 생성한다.
    final seededAdvice = await _db.readValue('dashboard_ai_advice');
    final bool hasSeededAdvice =
        seededAdvice != null && seededAdvice.isNotEmpty;

    // Exercise aggregates for the current week.
    final weekStart = _mondayOfThisWeekString();
    final exerciseRows = await (_db.select(
      _db.exerciseSessions,
    )..where((t) => t.weekStart.equals(weekStart))).get();
    int exerciseMinutes = 0;
    for (final r in exerciseRows) {
      exerciseMinutes += r.minutes;
    }

    // (혈당 row removed from the home summary per the latest design ref —
    // the indicator list now ends at 당류.)

    final now = nowKst();
    final monday = mondayOf(now);
    final nutritionByDate = <String, Map<String, num>>{
      for (var index = 0; index < 7; index++)
        wireDate(monday.add(Duration(days: index))): <String, num>{
          'calories': 0,
          'sodium_mg': 0,
          'sugar_g': 0.0,
        },
    };
    final allDietRows = await _db.select(_db.dietEntries).get();
    for (final row in allDietRows) {
      final totals = nutritionByDate[row.date];
      if (totals == null) continue;
      totals['calories'] = totals['calories']! + row.totalCalories;
      totals['sodium_mg'] = totals['sodium_mg']! + row.sodiumMg;
      totals['sugar_g'] = totals['sugar_g']! + row.sugarG;
    }
    final nutritionWeek = <Map<String, Object?>>[
      for (var index = 0; index < 7; index++)
        <String, Object?>{
          'label': _weekdayLabels[index],
          ...nutritionByDate[wireDate(monday.add(Duration(days: index)))]!,
        },
    ];
    final String? sodiumWarning = _homeSodiumWarning(
      lang: lang,
      totalSodium: totalSodium,
      sodiumGoal: sodiumGoal,
      sourceNames: sodiumSourceNames,
    );
    final ({String key, String text}) exerciseFeedback = _homeExerciseFeedback(
      lang: lang,
      minutes: exerciseMinutes,
    );
    final String adviceKey = hasSeededAdvice
        ? kDailyCombinedAdviceKey
        : sodiumWarning != null
        ? (sodiumSourceNames.isEmpty ? 'sodium_over' : 'sodium_over_sources')
        : exerciseFeedback.key;

    return _ok(options, <String, Object?>{
      'indicators': <Map<String, Object?>>[
        <String, Object?>{
          'label': '칼로리',
          'current': totalCalories,
          'max': calorieGoal,
          'unit': 'kcal',
          'over_budget': totalCalories > calorieGoal,
        },
        <String, Object?>{
          'label': '나트륨',
          'current': totalSodium,
          'max': sodiumGoal,
          'unit': 'mg',
          'over_budget': totalSodium > sodiumGoal,
        },
        <String, Object?>{
          'label': '당류',
          'current': totalSugar,
          'max': sugarGoal,
          'unit': 'g',
          'over_budget': totalSugar > sugarGoal,
        },
      ],
      'macros': _macroPayload(totalCarbs, totalProtein, totalFat),
      'diet_entries': dietRows.length,
      'exercise_minutes': exerciseMinutes,
      // 주간 점수·지난 주 비교선·운동 칼로리·횟수는 서버처럼 싣지 않는다 — 홈이
      // 읽지 않는다(#2646).
      'nutrition_week': nutritionWeek,
      // 시드가 큐레이션한 통합 조언은 **키로** 내려보낸다 — 문장은 ARB 가
      // ko·en 양쪽으로 갖고 있고 화면이 로케일에 맞게 고른다(#435).
      //
      // 시드 조언이 없으면 서버와 같은 순서로 고른다 — 나트륨 경고가 있으면
      // 그것, 없으면 이번 주 운동 되먹임이다. 음식 이름이 든 경고도 키와 음식
      // 이름 인자로 싣는다(#2644).
      'ai_advice_key': adviceKey,
      'ai_advice_params': <String, Object?>{
        if (adviceKey == 'sodium_over_sources') 'foods': sodiumSourceNames,
      },
      // 키를 모르는 화면이 읽는 문장. 서버처럼 요청 언어를 따른다.
      'sodium_warning': hasSeededAdvice ? null : sodiumWarning,
      'exercise_feedback': exerciseFeedback.text,
    });
  }

  /// `GET /me/records/span` — 식단·운동을 처음 남긴 날. 없으면 null. (#2236)
  Future<Response<Object?>> _recordSpan(RequestOptions options) async {
    final DateTime? diet = await _firstDietDate();
    final Set<String> exerciseDays = await _exerciseDates();
    final String? exercise = exerciseDays.isEmpty
        ? null
        : (exerciseDays.toList()..sort()).first;
    return _ok(options, <String, Object?>{
      'diet_first_date': diet == null ? null : wireDate(diet),
      'exercise_first_date': exercise,
    });
  }
}

/// 홈 나트륨 경고 — 서버 `dashboard._build_sodium_warning` 과 같은 문장.
/// 목표 안이면 null. 음식 이름은 회원이 적은 데이터라 번역하지 않는다.
String? _homeSodiumWarning({
  required String lang,
  required int totalSodium,
  required int sodiumGoal,
  required List<String> sourceNames,
}) {
  if (totalSodium <= sodiumGoal) return null;
  final bool en = lang == 'en';
  if (sourceNames.isEmpty) {
    return en
        ? 'Sodium is at ${totalSodium}mg today, over your goal (${sodiumGoal}mg).'
        : '오늘 나트륨이 ${totalSodium}mg 으로 목표(${sodiumGoal}mg)를 넘었어요.';
  }
  return en
      ? 'Sodium is high from ${sourceNames.join(' and ')}.'
      : '${sourceNames.join('·')} 섭취로 나트륨이 높아요.';
}

/// 이번 주 운동 되먹임 — 서버 `dashboard._exercise_feedback` 과 같은 기준
/// (주 150분)·같은 문장·같은 키.
({String key, String text}) _homeExerciseFeedback({
  required String lang,
  required int minutes,
}) {
  final bool en = lang == 'en';
  if (minutes >= 150) {
    return (
      key: 'exercise_on_track',
      text: en
          ? 'You worked out $minutes minutes this week. You are on track!'
          : '이번 주 $minutes분 운동했어요. 목표 달성 중이에요!',
    );
  }
  if (minutes > 0) {
    return (
      key: 'exercise_more',
      text: en
          ? 'You worked out $minutes minutes this week. A little more to go!'
          : '이번 주 $minutes분 운동했어요. 조금만 더 힘내요!',
    );
  }
  return (
    key: 'exercise_start',
    text: en
        ? 'Start moving this week — an easy walk is a good beginning.'
        : '이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요.',
  );
}

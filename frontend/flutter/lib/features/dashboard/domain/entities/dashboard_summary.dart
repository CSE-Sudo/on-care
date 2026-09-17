import 'package:oncare/features/diet/domain/entities/diet_day.dart';

/// One row of the "오늘의 건강 요약" progress list.
class HealthIndicator {
  const HealthIndicator({
    required this.label,
    required this.current,
    required this.max,
    required this.unit,
    this.overBudget = false,
  });

  final String label;
  final num current;
  final num max;
  final String unit;

  /// True when [current] should be treated as exceeding the target,
  /// even if the number is below `max` for a different reason. The
  /// React mock marks 나트륨 2100/2000 as `warning: true`.
  final bool overBudget;

  double get progress =>
      max == 0 ? 0 : (current / max).clamp(0.0, 1.0).toDouble();

  factory HealthIndicator.fromJson(Map<String, Object?> json) =>
      HealthIndicator(
        label: json['label']! as String,
        current: json['current']! as num,
        max: json['max']! as num,
        unit: json['unit']! as String,
        overBudget: (json['over_budget'] as bool?) ?? false,
      );
}

/// One day of the 식단 카드 weekly-trend chart.
///
/// 홈 카드가 그리는 것은 [calories] 하나다(#1879). [sodiumMg] 는 주간 건강
/// 점수와 코칭 문구가 읽고, [sugarG] 는 응답 계약을 지키느라 남는다.
///
/// [carbsG]·[proteinG]·[fatG] 는 서버가 실어 보내지만 **아직 그리는 화면이
/// 없다** — 홈 지표 3칸은 오늘 합계(`DashboardSummary.macros`)를 쓰고, 주간
/// 추이는 칼로리로 고정이다. 주간 탄단지 추이를 되살릴 때 바로 쓸 자리다.
class NutritionDay {
  const NutritionDay({
    required this.label,
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
  });

  final String label; // 요일(월/화/…)
  final int calories;
  final int sodiumMg;
  final double sugarG;

  /// 그날의 탄단지(g). 서버가 주지 않던 시절의 응답은 0 으로 떨어진다.
  final double carbsG;
  final double proteinG;
  final double fatG;

  factory NutritionDay.fromJson(Map<String, Object?> json) => NutritionDay(
    label: (json['label'] as String?) ?? '',
    calories: (json['calories'] as num?)?.toInt() ?? 0,
    sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
    sugarG: (json['sugar_g'] as num?)?.toDouble() ?? 0,
    carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
    proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
    fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
  );
}

/// Snapshot displayed on the home dashboard. Mirrors the data the
/// React `Dashboard.tsx` mounts in `healthData` /
/// `quickStats` / weekly score.
class DashboardSummary {
  const DashboardSummary({
    required this.indicators,
    required this.macros,
    required this.dietEntries,
    required this.exerciseMinutes,
    this.exerciseCalories = 0,
    this.exerciseCount = 0,
    this.exerciseBurnGoal = defaultExerciseBurnGoal,
    this.nutritionWeek = const <NutritionDay>[],
    this.nutritionWeekPrev = const <NutritionDay>[],
      required this.weekScore,
    required this.weekScoreDelta,
    required this.sodiumWarning,
    this.exerciseFeedback,
    this.aiAdviceKey,
  });

  /// 3-row health summary (칼로리 / 나트륨 / 당류).
  final List<HealthIndicator> indicators;

  /// Today's carbohydrate, protein, and fat totals and calorie ratios.
  final DietMacros macros;

  /// `quickStats` left tile — number of diet records logged today.
  final int dietEntries;

  /// `quickStats` right tile — total exercise minutes for the current week.
  final int exerciseMinutes;

  /// Total calories burned by the exercise sessions included in this summary.
  final int exerciseCalories;

  /// Number of exercise sessions included in this summary.
  final int exerciseCount;

  /// 운동 카드 소모 목표(kcal). 개인화 전까지 서버 기본값(500).
  /// 홈 운동 카드와 운동 탭 '이번 주 운동 요약'이 모두 이 값을 읽는다.
  final int exerciseBurnGoal;

  /// 서버가 `exercise_burn_goal` 을 내려주지 않을 때 쓰는 기본값(kcal).
  static const int defaultExerciseBurnGoal = 500;

  /// 식단 카드 주간 추이(최근 7일 일별 영양) + 지난 주 같은 요일(비교선).
  /// 비어 있으면(데모/목·데이터 없음) 화면은 기존 데모 상수로 폴백한다.
  final List<NutritionDay> nutritionWeek;
  final List<NutritionDay> nutritionWeekPrev;


  /// "이번 주 건강 점수" card.
  final int weekScore;
  final int weekScoreDelta;

  /// Diet-side daily feedback line — currently driven by the sodium
  /// budget, but treated generically as "the diet feedback the AI
  /// coach wants surfaced today". Null = nothing to say.
  final String? sodiumWarning;

  /// Exercise-side weekly feedback line. Optional for back-compat.
  final String? exerciseFeedback;

  /// 표시 문자열 대신 **로케일 독립 식별자**로 내려오는 AI 조언. 값이 있으면
  /// 화면이 [AppLocalizations] 로 풀어 쓰고, [sodiumWarning]·[exerciseFeedback]
  /// 보다 우선한다.
  ///
  /// 데모(목·시드)가 쓰는 통로다. 서버가 만든 문장은 번역본이 없으므로 그대로
  /// 문자열 필드로 오지만, 데모 문구는 앱이 ARB 에 이미 양쪽 로케일로 갖고
  /// 있는데도 한국어 문자열을 실어 보내 영어 데모에서 한국어가 나왔다(#435).
  final String? aiAdviceKey;

  HealthIndicator get calorieIndicator => indicators.firstWhere(
    (HealthIndicator indicator) => indicator.unit == 'kcal',
    orElse: () => const HealthIndicator(
      label: '칼로리',
      current: 0,
      max: 2000,
      unit: 'kcal',
    ),
  );

  HealthIndicator get sodiumIndicator => indicators.firstWhere(
    (HealthIndicator indicator) => indicator.unit == 'mg',
    orElse: () =>
        const HealthIndicator(label: '나트륨', current: 0, max: 2000, unit: 'mg'),
  );

  HealthIndicator get sugarIndicator => indicators.firstWhere(
    (HealthIndicator indicator) => indicator.unit == 'g',
    orElse: () =>
        const HealthIndicator(label: '당류', current: 0, max: 50, unit: 'g'),
  );

  bool get isEmpty =>
      dietEntries == 0 &&
      exerciseMinutes == 0 &&
      calorieIndicator.current == 0 &&
      // 오늘 기록이 없어도 이번 주(과거 요일)에 실제 식단 기록이 있으면 홈은
      // 비어 있지 않다 — 주간 추이 차트가 표시돼야 한다.
      !nutritionWeek.any((NutritionDay day) => day.calories > 0);

  factory DashboardSummary.fromJson(
    Map<String, Object?> json,
  ) => DashboardSummary(
    indicators: (json['indicators']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(HealthIndicator.fromJson)
        .toList(),
    macros: json['macros'] is Map<Object?, Object?>
        ? DietMacros.fromJson(
            (json['macros']! as Map<Object?, Object?>).cast<String, Object?>(),
          )
        : const DietMacros.zero(),
    dietEntries: (json['diet_entries']! as num).toInt(),
    exerciseMinutes: (json['exercise_minutes']! as num).toInt(),
    exerciseCalories: (json['exercise_calories'] as num?)?.toInt() ?? 0,
    exerciseCount: (json['exercise_count'] as num?)?.toInt() ?? 0,
    exerciseBurnGoal:
        (json['exercise_burn_goal'] as num?)?.toInt() ??
        defaultExerciseBurnGoal,
    nutritionWeek:
        ((json['nutrition_week'] as List<Object?>?) ?? const <Object?>[])
            .cast<Map<String, Object?>>()
            .map(NutritionDay.fromJson)
            .toList(),
    nutritionWeekPrev:
        ((json['nutrition_week_prev'] as List<Object?>?) ?? const <Object?>[])
            .cast<Map<String, Object?>>()
            .map(NutritionDay.fromJson)
            .toList(),
    weekScore: (json['week_score']! as num).toInt(),
    weekScoreDelta: (json['week_score_delta']! as num).toInt(),
    sodiumWarning: json['sodium_warning'] as String?,
    exerciseFeedback: json['exercise_feedback'] as String?,
    aiAdviceKey: json['ai_advice_key'] as String?,
  );
}

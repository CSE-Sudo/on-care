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
/// 홈 카드가 그리는 것은 [calories] 하나다(#1879). 서버 응답에는 그날의
/// 나트륨·당류도 실려 오지만 앱은 읽지 않는다(#2646).
///
/// 날짜별 탄단지는 싣지 않는다 — 홈 지표 3칸은 오늘 합계
/// (`DashboardSummary.macros`)를 쓰고 주간 추이는 칼로리로 고정이다(#1889).
/// 식단 탭 `전체` 그래프가 쌓는 탄단지는 다른 경로(`/diet/days/{date}`)로 온다.
class NutritionDay {
  const NutritionDay({required this.label, required this.calories});

  final String label; // 요일(월/화/…)
  final int calories;

  factory NutritionDay.fromJson(Map<String, Object?> json) => NutritionDay(
    label: (json['label'] as String?) ?? '',
    calories: (json['calories'] as num?)?.toInt() ?? 0,
  );
}

/// Snapshot displayed on the home dashboard — `GET /dashboard/summary`.
///
/// 홈이 그리는 값만 든다. 주간 점수·지난 주 비교선·운동 칼로리·횟수·소모 목표는
/// 화면 어디에서도 읽지 않아 뺐다(#2646).
class DashboardSummary {
  const DashboardSummary({
    required this.indicators,
    required this.macros,
    required this.dietEntries,
    required this.exerciseMinutes,
    this.nutritionWeek = const <NutritionDay>[],
    required this.sodiumWarning,
    this.exerciseFeedback,
    this.aiAdviceKey,
    this.aiAdviceParams = const <String, Object>{},
  });

  /// 3-row health summary (칼로리 / 나트륨 / 당류).
  final List<HealthIndicator> indicators;

  /// Today's carbohydrate, protein, and fat totals and calorie ratios.
  final DietMacros macros;

  /// `quickStats` left tile — number of diet records logged today.
  final int dietEntries;

  /// `quickStats` right tile — total exercise minutes for the current week.
  final int exerciseMinutes;

  /// 식단 카드 주간 추이(이번 주 월~일 일별 칼로리).
  /// 비어 있으면(데이터 없음) 화면은 기존 데모 상수로 폴백한다.
  final List<NutritionDay> nutritionWeek;

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

  /// [aiAdviceKey] 문장에 끼울 값. `sodium_over_sources` 면 `foods`(나트륨 상위
  /// 급원 음식 이름 목록, 최대 두 개)가 들어온다(#2644). 음식 이름은 회원이
  /// 적은 데이터라 번역하지 않고 ARB 문장 틀에 그대로 끼운다.
  final Map<String, Object> aiAdviceParams;

  HealthIndicator get calorieIndicator => indicators.firstWhere(
    (HealthIndicator indicator) => indicator.unit == 'kcal',
    orElse: () => const HealthIndicator(
      label: '칼로리',
      current: 0,
      max: 2000,
      unit: 'kcal',
    ),
  );

  bool get isEmpty =>
      dietEntries == 0 &&
      exerciseMinutes == 0 &&
      calorieIndicator.current == 0 &&
      // 오늘 기록이 없어도 이번 주(과거 요일)에 실제 식단 기록이 있으면 홈은
      // 비어 있지 않다 — 주간 추이 차트가 표시돼야 한다.
      !nutritionWeek.any((NutritionDay day) => day.calories > 0);

  factory DashboardSummary.fromJson(Map<String, Object?> json) =>
      DashboardSummary(
        indicators: (json['indicators']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(HealthIndicator.fromJson)
            .toList(),
        macros: json['macros'] is Map<Object?, Object?>
            ? DietMacros.fromJson(
                (json['macros']! as Map<Object?, Object?>)
                    .cast<String, Object?>(),
              )
            : const DietMacros.zero(),
        dietEntries: (json['diet_entries']! as num).toInt(),
        exerciseMinutes: (json['exercise_minutes']! as num).toInt(),
        nutritionWeek:
            ((json['nutrition_week'] as List<Object?>?) ?? const <Object?>[])
                .cast<Map<String, Object?>>()
                .map(NutritionDay.fromJson)
                .toList(),
        sodiumWarning: json['sodium_warning'] as String?,
        exerciseFeedback: json['exercise_feedback'] as String?,
        aiAdviceKey: json['ai_advice_key'] as String?,
        aiAdviceParams: <String, Object>{
          for (final MapEntry<Object?, Object?> e
              in ((json['ai_advice_params'] as Map<Object?, Object?>?) ??
                      const <Object?, Object?>{})
                  .entries)
            if (e.key is String && e.value != null) e.key! as String: e.value!,
        },
      );
}

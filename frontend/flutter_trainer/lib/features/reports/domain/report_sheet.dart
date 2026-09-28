/// 리포트 PDF 한 장 결과지에 싣는 수치. (#2485)
///
/// 결과지는 체성분 결과지의 문법을 빌린다 — 항목마다 **표준 범위 대비 막대**를
/// 긋고, 오른쪽에 점수와 평가를 모은다. 여기서는 그 막대가 어디까지 가는지,
/// 어느 칸(부족·적정·초과)에 서는지, 점수가 몇 점인지를 화면과 떼어 계산한다.
/// 화면(`ReportResultSheet`)은 이 값을 그리기만 한다.
library;

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart'
    show carbsTargetG, fatTargetG, proteinTargetG;
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays, weekdayCount;
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart'
    show goodCompletionThreshold;
import 'package:oncare_trainer/shared/models/trainer_client.dart'
    show sodiumTargetMg;

/// 막대가 선 칸.
enum SheetBand { under, normal, over }

/// 막대 한 줄 — 값과 목표, 그리고 적정 범위(목표 대비 비율).
///
/// 막대의 세 칸은 폭이 고정이다(체성분 결과지와 같다). 항목마다 적정 범위가
/// 달라도 `적정` 칸은 언제나 같은 자리에 서서, 줄을 훑어 내리면 어느 항목이
/// 칸을 벗어났는지가 한눈에 보인다. 칸 안에서는 비율에 따라 곧게 늘어난다.
class SheetMeasure {
  /// Creates a measure.
  const SheetMeasure({
    required this.value,
    required this.target,
    required this.low,
    required this.high,
    this.axisMax = 2,
    this.overIsFine = false,
  });

  /// 이번 주 값. 기록이 없으면 null.
  final double? value;

  /// 견줄 목표. 0 이하이면 견줄 수 없다.
  final double target;

  /// 적정 범위의 아래·위 끝(목표 대비 비율).
  final double low;
  final double high;

  /// 막대 오른쪽 끝의 비율. 이보다 크면 끝에 붙는다.
  final double axisMax;

  /// 목표를 넘겨도 걱정할 일이 아닌 항목인가(운동량).
  final bool overIsFine;

  /// 목표 대비 비율. 값이 없거나 목표가 없으면 null.
  double? get ratio {
    final double? v = value;
    if (v == null || target <= 0) return null;
    return v / target;
  }

  /// `부족` 칸이 있는가. 상한만 있는 항목(나트륨·당류)에는 없다.
  bool get hasUnder => low > 0;

  /// `초과` 칸이 있는가. 100% 가 끝인 항목(수행률·출석)에는 없다.
  bool get hasOver => high < axisMax;

  /// 막대가 선 칸. 값이 없으면 null.
  SheetBand? get band {
    final double? r = ratio;
    if (r == null) return null;
    if (hasUnder && r < low) return SheetBand.under;
    if (hasOver && r > high) return SheetBand.over;
    return SheetBand.normal;
  }

  /// 짚어야 할 값인가. 값이 없으면 null — 모르는 것을 괜찮다고도, 나쁘다고도
  /// 하지 않는다.
  bool? get concerning => switch (band) {
    null => null,
    SheetBand.under => true,
    SheetBand.over => !overIsFine,
    SheetBand.normal => false,
  };

  /// 막대 끝의 자리(0~1). 값이 없으면 null.
  double? get position {
    final double? r = ratio;
    if (r == null) return null;
    return sheetBarPosition(r, low: low, high: high, axisMax: axisMax);
  }
}

/// `부족` 칸과 `적정` 칸의 폭(막대 전체 대비). 남는 폭이 `초과` 칸이다.
const double kSheetUnderSpan = 0.3;
const double kSheetNormalSpan = 0.3;

/// 목표 대비 비율 [ratio] 를 막대의 자리(0~1)로 바꾼다.
///
/// `0..low` 는 부족 칸, `low..high` 는 적정 칸, `high..axisMax` 는 초과 칸에
/// 각각 곧게 놓인다. 상한만 있는 항목(`low == 0`)은 0 부터 적정 칸에서 시작하고,
/// 초과 칸이 없는 항목(`high >= axisMax`)은 적정 칸 오른쪽 끝에서 멈춘다.
double sheetBarPosition(
  double ratio, {
  required double low,
  required double high,
  required double axisMax,
}) {
  const double normalStart = kSheetUnderSpan;
  const double overStart = kSheetUnderSpan + kSheetNormalSpan;
  final double r = ratio < 0 ? 0 : ratio;
  if (low > 0 && r < low) return r / low * kSheetUnderSpan;
  if (r <= high || high >= axisMax) {
    final double span = high - low;
    final double inside = span <= 0 ? 1 : ((r - low) / span).clamp(0.0, 1.0);
    // 상한만 있는 항목은 0 에서 부족 칸을 건너뛴 채 시작한다 — 그 칸은
    // 비어 있는 칸이다.
    return normalStart + inside * kSheetNormalSpan;
  }
  final double over = ((r - high) / (axisMax - high)).clamp(0.0, 1.0);
  return overStart + over * (1 - overStart);
}

/// 식단 분석 줄 — 결과지에 이 차례로 선다.
enum SheetDietItem { calories, carbs, protein, fat, sodium, sugar }

/// 운동 분석 줄.
enum SheetExerciseItem { completion, attendance, cardio, strength, stretching }

/// 점수를 이루는 항목.
enum SheetScorePart { completion, attendance, mealLogging, calorieDays }

/// 4주 평균과 견주는 항목.
enum SheetAverageItem { calories, completion, sodium, mealDays }

/// 이번 주 값과 직전 넉 주 평균.
class SheetAverage {
  /// Creates a comparison.
  const SheetAverage({required this.current, required this.average});

  final double? current;
  final double? average;

  /// 이번 주 − 평균. 둘 중 하나라도 없으면 null.
  double? get change {
    final double? c = current;
    final double? a = average;
    if (c == null || a == null) return null;
    return c - a;
  }
}

/// 주간 관리 점수 — 항목 점수(0~100)의 평균.
class SheetScore {
  /// Creates a score.
  const SheetScore(this.parts);

  /// 기록이 있어 점수에 들어간 항목만 담는다.
  final Map<SheetScorePart, double> parts;

  /// 0~100 점. 들어간 항목이 없으면 null.
  int? get value {
    if (parts.isEmpty) return null;
    final double sum = parts.values.fold<double>(
      0,
      (double a, double b) => a + b,
    );
    return (sum / parts.length).round();
  }
}

/// 결과지 한 장에 싣는 수치 전부.
class ReportSheet {
  const ReportSheet._({
    required this.diet,
    required this.exercise,
    required this.score,
    required this.averages,
    required this.mealDays,
    required this.mealDaysDue,
    required this.weeklyRates,
  });

  /// [report] 한 주의 결과지 수치.
  ///
  /// [trend] 는 여덟 주 운동 실적(없으면 유형별 줄과 추이가 `미집계`),
  /// [history] 는 직전 주들의 리포트(4주 평균 대비에 쓴다), [today] 는 이번 주
  /// 리포트에서 지난 날 수를 셀 때 쓴다.
  factory ReportSheet.of(
    WeeklyReport report, {
    ReportTrend? trend,
    List<WeeklyReport> history = const <WeeklyReport>[],
    DateTime? today,
  }) {
    final int? due = _mealDaysDue(report, today);
    return ReportSheet._(
      diet: _diet(report),
      exercise: _exercise(report, trend),
      score: _score(report, due),
      averages: _averages(report, history),
      mealDays: report.mealLoggedDays,
      mealDaysDue: due,
      weeklyRates: <double?>[
        for (final ReportTrendWeek week
            in trend?.weeks ?? const <ReportTrendWeek>[])
          week.isEmpty ? null : trend!.rateOf(week),
      ],
    );
  }

  final Map<SheetDietItem, SheetMeasure> diet;
  final Map<SheetExerciseItem, SheetMeasure> exercise;
  final SheetScore score;
  final Map<SheetAverageItem, SheetAverage> averages;

  /// 끼니를 하나라도 적은 날 수.
  final int mealDays;

  /// 끼니를 적었어야 하는 날 수. 요일별 끼니 자료가 없으면 null.
  final int? mealDaysDue;

  /// 주별 운동 달성률(0~1, 오래된 주 → 이번 주). 기록 없는 주는 null.
  final List<double?> weeklyRates;

  /// 적정 범위 — 칼로리는 판정 허용 폭과 같고, 탄단지는 ① 영양 막대가
  /// `모자람` 을 짚는 80% 를 아래 끝으로 쓴다.
  static const double _macroLow = 0.8;
  static const double _macroHigh = 1.2;
  static const double _exerciseLow = 0.8;
  static const double _exerciseHigh = 1.2;

  static Map<SheetDietItem, SheetMeasure> _diet(WeeklyReport r) =>
      <SheetDietItem, SheetMeasure>{
        SheetDietItem.calories: SheetMeasure(
          value: r.calorieMean,
          target: r.calorieGoal.toDouble(),
          low: 1 - calorieTolerance,
          high: 1 + calorieTolerance,
        ),
        SheetDietItem.carbs: SheetMeasure(
          value: recordedMean(r.carbsWeek),
          target: r.carbsTarget ?? carbsTargetG.toDouble(),
          low: _macroLow,
          high: _macroHigh,
        ),
        SheetDietItem.protein: SheetMeasure(
          value: recordedMean(r.proteinWeek),
          target: r.proteinTarget ?? proteinTargetG.toDouble(),
          low: _macroLow,
          high: _macroHigh,
        ),
        SheetDietItem.fat: SheetMeasure(
          value: recordedMean(r.fatWeek),
          target: r.fatTarget ?? fatTargetG.toDouble(),
          low: _macroLow,
          high: _macroHigh,
        ),
        // 나트륨·당류는 상한만 있다 — 적게 먹어서 걱정할 항목이 아니다.
        SheetDietItem.sodium: SheetMeasure(
          value: r.sodiumAvg?.toDouble() ?? recordedMean(r.sodiumWeek),
          target: (r.sodiumTarget ?? sodiumTargetMg).toDouble(),
          low: 0,
          high: 1,
        ),
        SheetDietItem.sugar: SheetMeasure(
          value: r.sugarMean,
          target: r.sugarLimit,
          low: 0,
          high: 1,
        ),
      };

  static Map<SheetExerciseItem, SheetMeasure> _exercise(
    WeeklyReport r,
    ReportTrend? trend,
  ) {
    SheetMeasure kind(ExerciseKind k) {
      final ReportTrendWeek? week = trend?.current;
      return SheetMeasure(
        value: week?.valueOf(k).toDouble(),
        target: trend?.goals.weeklyGoalOf(k) ?? 0,
        low: _exerciseLow,
        high: _exerciseHigh,
        // 주간 목표보다 더 한 것은 짚을 일이 아니다.
        overIsFine: true,
      );
    }

    // 수행률·출석은 100% 가 끝이다. 적정 칸의 아래 끝은 `잘한 주` 문턱이다.
    const double good = goodCompletionThreshold / 100;
    return <SheetExerciseItem, SheetMeasure>{
      SheetExerciseItem.completion: SheetMeasure(
        value: r.completionAvg?.toDouble(),
        target: 100,
        low: good,
        high: 1,
        axisMax: 1,
      ),
      SheetExerciseItem.attendance: SheetMeasure(
        value: r.attendanceRate?.toDouble(),
        target: 100,
        low: good,
        high: 1,
        axisMax: 1,
      ),
      SheetExerciseItem.cardio: kind(ExerciseKind.cardio),
      SheetExerciseItem.strength: kind(ExerciseKind.strength),
      SheetExerciseItem.stretching: kind(ExerciseKind.stretching),
    };
  }

  /// 끼니를 적었어야 하는 날 수 — 지난 주는 이레, 이번 주는 오늘까지.
  static int? _mealDaysDue(WeeklyReport r, DateTime? today) {
    if (r.mealCounts.length != weekdayCount) return null;
    final int due = r.isCurrentWeek
        ? elapsedWeekdays(today ?? nowKst())
        : weekdayCount;
    return due > 0 ? due : null;
  }

  static SheetScore _score(WeeklyReport r, int? due) {
    final Map<SheetScorePart, double> parts = <SheetScorePart, double>{};
    if (r.completionAvg case final int c) {
      parts[SheetScorePart.completion] = c.clamp(0, 100).toDouble();
    }
    if (r.attendanceRate case final int a) {
      parts[SheetScorePart.attendance] = a.clamp(0, 100).toDouble();
    }
    if (due != null) {
      parts[SheetScorePart.mealLogging] = (r.mealLoggedDays / due * 100)
          .clamp(0, 100)
          .toDouble();
    }
    final List<int> recorded = r.caloriesWeek
        .where((int k) => k > 0)
        .toList(growable: false);
    final int goal = r.calorieGoal;
    if (recorded.isNotEmpty && goal > 0) {
      final int within = recorded
          .where((int k) => ((k - goal) / goal).abs() <= calorieTolerance)
          .length;
      parts[SheetScorePart.calorieDays] = within / recorded.length * 100;
    }
    return SheetScore(parts);
  }

  static Map<SheetAverageItem, SheetAverage> _averages(
    WeeklyReport r,
    List<WeeklyReport> history,
  ) {
    double? meanOf(Iterable<num> xs) {
      final List<num> list = xs.toList(growable: false);
      if (list.isEmpty) return null;
      return list.fold<double>(0, (double a, num b) => a + b) / list.length;
    }

    // 칼로리 평균은 ① 의 `평소` 와 같은 규칙이다 — 넉 주에서 기록한 날만.
    final List<int> pastKcal = <int>[
      for (final WeeklyReport past in history)
        ...past.caloriesWeek.where((int k) => k > 0),
    ];
    return <SheetAverageItem, SheetAverage>{
      SheetAverageItem.calories: SheetAverage(
        current: r.calorieMean,
        average: meanOf(pastKcal),
      ),
      SheetAverageItem.completion: SheetAverage(
        current: r.completionAvg?.toDouble(),
        average: meanOf(<int>[
          for (final WeeklyReport past in history)
            if (past.completionAvg case final int c) c,
        ]),
      ),
      SheetAverageItem.sodium: SheetAverage(
        current: r.sodiumAvg?.toDouble(),
        average: meanOf(<int>[
          for (final WeeklyReport past in history)
            if (past.sodiumAvg case final int s) s,
        ]),
      ),
      SheetAverageItem.mealDays: SheetAverage(
        current: r.mealCounts.length == weekdayCount
            ? r.mealLoggedDays.toDouble()
            : null,
        average: meanOf(<int>[
          for (final WeeklyReport past in history)
            if (past.mealCounts.length == weekdayCount) past.mealLoggedDays,
        ]),
      ),
    };
  }
}

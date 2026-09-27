import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';

/// ③ 지난 주 목표 하나의 판정. (#2287)
enum GoalOutcome {
  /// 이번 주 수치가 목표에 닿았다.
  met,

  /// 절반쯤 — 방향은 맞았지만 모자랐다.
  partial,

  /// 못 지켰다.
  missed,

  /// 수치로 판정할 수 없는 목표이거나 판정할 기록이 없다. 트레이너가 직접
  /// 본다 — 지어낸 판정보다 `직접 확인` 이 정직하다.
  unknown,
}

/// 목표 한 줄과 그 판정·근거.
class GoalCheck {
  /// Creates a check.
  const GoalCheck({required this.goal, required this.outcome, this.evidence});

  /// 트레이너가 지난 주에 고른 목표 문장 그대로.
  final String goal;

  final GoalOutcome outcome;

  /// 판정의 근거가 된 이번 주 수치(`62 / 120g`, `5일 기록` 따위). 판정하지
  /// 못했으면 null.
  final String? evidence;
}

/// 목표가 무엇에 관한 것인가.
enum _GoalTopic {
  sodium,
  sugar,
  carbs,
  protein,
  fat,
  calories,
  logged,
  workout,
}

/// 채울수록 좋은 값은 목표의 이 비율 이상이면 달성으로 본다. 탄단지
/// 막대가 모자람을 짚는 경계(80%)와 같다: 막대가 빨갛게 짚지 않는 주를 ③ 이
/// 미달이라 부르면 두 칸이 서로 다른 말을 한다.
const double _metRatio = 0.8;

/// 이 비율 이상이면 절반으로 본다.
const double _partialRatio = 0.5;

/// 나트륨·당류는 적을수록 좋다. 목표를 이만큼까지 넘긴 주는 절반으로 본다.
const double _overPartial = 1.2;

/// 기록 목표 — 한 주 일곱 날 중 이만큼 적었으면 달성이다.
const int _loggedMetDays = 5;
const int _loggedPartialDays = 3;

/// [report] 주에 적용돼 있던 목표([WeeklyReport.weekGoals])를 그 주 수치로
/// 판정한다. 목표가 없으면 빈 목록.
///
/// 목표는 트레이너가 고르거나 직접 적은 **문장**이라, 무엇에 관한 목표인지를
/// 문장에 든 말로 가른다. 목표를 고른 언어와 지금 화면의 언어가 다를 수 있어
/// 한·영 두 언어의 말을 모두 본다 — 한국어로 고른 목표가 영어 화면에서
/// `직접 확인` 으로만 서면 판정이 언어를 따라 사라진다.
List<GoalCheck> checkWeekGoals(AppLocalizations l, WeeklyReport report) {
  return <GoalCheck>[
    for (final String goal in report.weekGoals) _check(l, report, goal),
  ];
}

/// 달성한 목표 수.
int metGoalCount(List<GoalCheck> checks) =>
    checks.where((GoalCheck c) => c.outcome == GoalOutcome.met).length;

GoalCheck _check(AppLocalizations l, WeeklyReport report, String goal) {
  final _GoalTopic? topic = _topicOf(goal);
  if (topic == null) {
    return GoalCheck(goal: goal, outcome: GoalOutcome.unknown);
  }
  return switch (topic) {
    _GoalTopic.sodium => _atMost(
      l,
      goal,
      value: report.sodiumAvg?.toDouble(),
      target: (report.sodiumTarget ?? summarySodiumTargetMg).toDouble(),
      unit: 'mg',
    ),
    _GoalTopic.sugar => _atMost(
      l,
      goal,
      value: recordedMean(report.sugarWeek),
      target: report.sugarTarget ?? summarySugarTargetG,
      unit: 'g',
    ),
    _GoalTopic.carbs => _atLeast(
      l,
      goal,
      value: recordedMean(report.carbsWeek),
      target: report.carbsTarget ?? carbsTargetG.toDouble(),
      unit: 'g',
    ),
    _GoalTopic.protein => _atLeast(
      l,
      goal,
      value: recordedMean(report.proteinWeek),
      target: report.proteinTarget ?? proteinTargetG.toDouble(),
      unit: 'g',
    ),
    _GoalTopic.fat => _atLeast(
      l,
      goal,
      value: recordedMean(report.fatWeek),
      target: report.fatTarget ?? fatTargetG.toDouble(),
      unit: 'g',
    ),
    _GoalTopic.calories => _near(l, report, goal),
    _GoalTopic.logged => _logged(l, report, goal),
    _GoalTopic.workout => _workout(l, report, goal),
  };
}

/// 한·영 두 언어의 말로 목표의 주제를 찾는다. 영양소를 먼저 본다 — `저녁
/// 단백질 기록하기` 는 기록이 아니라 단백질 목표다.
_GoalTopic? _topicOf(String goal) {
  final String text = goal.toLowerCase();
  final List<AppLocalizations> both = <AppLocalizations>[
    for (final locale in AppLocalizations.supportedLocales)
      lookupAppLocalizations(locale),
  ];
  bool mentions(Iterable<String> Function(AppLocalizations) words) => both.any(
    (AppLocalizations l) => words(
      l,
    ).any((String w) => w.isNotEmpty && text.contains(w.toLowerCase())),
  );
  List<String> split(String csv) => <String>[
    for (final String w in csv.split(',')) w.trim(),
  ];

  if (mentions((l) => <String>[l.metricSodium])) return _GoalTopic.sodium;
  if (mentions((l) => <String>[l.metricSugar])) return _GoalTopic.sugar;
  if (mentions((l) => <String>[l.metricCarbs])) return _GoalTopic.carbs;
  if (mentions((l) => <String>[l.metricProtein])) return _GoalTopic.protein;
  if (mentions((l) => <String>[l.metricFat])) return _GoalTopic.fat;
  if (mentions((l) => split(l.reportsLastGoalsKeywordsCalories))) {
    return _GoalTopic.calories;
  }
  // 운동을 기록보다 먼저 본다 — `운동 기록 3회` 는 식단 기록이 아니다.
  if (mentions((l) => split(l.reportsLastGoalsKeywordsWorkout))) {
    return _GoalTopic.workout;
  }
  if (mentions((l) => split(l.reportsLastGoalsKeywordsLogged))) {
    return _GoalTopic.logged;
  }
  return null;
}

/// 채울수록 좋은 값(탄단지).
GoalCheck _atLeast(
  AppLocalizations l,
  String goal, {
  required double? value,
  required double target,
  required String unit,
}) {
  if (value == null || target <= 0) {
    return GoalCheck(goal: goal, outcome: GoalOutcome.unknown);
  }
  final double ratio = value / target;
  return GoalCheck(
    goal: goal,
    outcome: ratio >= _metRatio
        ? GoalOutcome.met
        : ratio >= _partialRatio
        ? GoalOutcome.partial
        : GoalOutcome.missed,
    evidence: l.reportsLastGoalsEvidence(value.round(), target.round(), unit),
  );
}

/// 적을수록 좋은 값(나트륨·당류).
GoalCheck _atMost(
  AppLocalizations l,
  String goal, {
  required double? value,
  required double target,
  required String unit,
}) {
  if (value == null || target <= 0) {
    return GoalCheck(goal: goal, outcome: GoalOutcome.unknown);
  }
  final double ratio = value / target;
  return GoalCheck(
    goal: goal,
    outcome: ratio <= 1
        ? GoalOutcome.met
        : ratio <= _overPartial
        ? GoalOutcome.partial
        : GoalOutcome.missed,
    evidence: l.reportsLastGoalsEvidence(value.round(), target.round(), unit),
  );
}

/// 목표 근처에 머물수록 좋은 값(칼로리). 요약이 칼로리를 짚는 허용 폭과 같은
/// 폭 안이면 달성이다.
GoalCheck _near(AppLocalizations l, WeeklyReport report, String goal) {
  final double? mean = recordedMean(report.caloriesWeek);
  final double target = (report.calorieTarget ?? summaryCalorieTargetKcal)
      .toDouble();
  if (mean == null || target <= 0) {
    return GoalCheck(goal: goal, outcome: GoalOutcome.unknown);
  }
  final double gap = ((mean - target) / target).abs();
  return GoalCheck(
    goal: goal,
    outcome: gap <= summaryCalorieTolerance
        ? GoalOutcome.met
        : gap <= summaryCalorieTolerance * 2
        ? GoalOutcome.partial
        : GoalOutcome.missed,
    evidence: l.reportsLastGoalsEvidence(mean.round(), target.round(), 'kcal'),
  );
}

/// 기록 목표 — 식단을 적은 날 수. 끼니 수가 없으면(실서버 응답) 칼로리가 있는
/// 날로 센다.
GoalCheck _logged(AppLocalizations l, WeeklyReport report, String goal) {
  final List<num> series = report.mealCounts.isNotEmpty
      ? report.mealCounts
      : report.caloriesWeek;
  if (series.isEmpty) {
    return GoalCheck(goal: goal, outcome: GoalOutcome.unknown);
  }
  final int days = series.where((num v) => v > 0).length;
  // 진행 중인 주는 지난 날만큼만 요구한다 — 수요일에 `5일 중 3일` 을 미달로
  // 부르면, 아직 오지 않은 날을 못 지켰다고 적는 셈이다.
  final int elapsed = report.isCurrentWeek ? elapsedWeekdays(nowKst()) : 7;
  final double scale = elapsed / 7;
  return GoalCheck(
    goal: goal,
    outcome: days >= (_loggedMetDays * scale).ceil()
        ? GoalOutcome.met
        : days >= (_loggedPartialDays * scale).ceil()
        ? GoalOutcome.partial
        : GoalOutcome.missed,
    evidence: l.reportsLastGoalsEvidenceLogged(days),
  );
}

/// 운동 목표 — 그 주 개인 운동 이행률. 좋음(80) 이상이면 달성, 낮음(60)
/// 아래면 미달, 그 사이는 부분 달성 — 요약·작업대 배지와 같은 세 구간이다(#2345).
GoalCheck _workout(AppLocalizations l, WeeklyReport report, String goal) {
  final int? completion = report.completionAvg;
  if (completion == null) {
    return GoalCheck(goal: goal, outcome: GoalOutcome.unknown);
  }
  return GoalCheck(
    goal: goal,
    outcome: completion >= goodCompletionThreshold
        ? GoalOutcome.met
        : completion >= lowCompletionThreshold
        ? GoalOutcome.partial
        : GoalOutcome.missed,
    evidence: l.reportsLastGoalsEvidence(
      completion,
      goodCompletionThreshold,
      '%',
    ),
  );
}

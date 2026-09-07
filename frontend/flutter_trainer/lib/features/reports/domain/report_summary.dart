import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays;
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 한 주를 트레이너가 손볼 수 있는 문장으로 압축한 것.
///
/// 그대로 읽는 글이 아니라 **피드백 초안으로 가져다 고칠 재료**다(#755).
class ReportSummary {
  /// Creates a summary.
  const ReportSummary({
    required this.headline,
    required this.points,
    required this.generatedBy,
  });

  /// 이번 주를 한 문장으로. 잘한 점과 챙길 점이 함께 들어간다.
  final String headline;

  /// 근거가 된 수치 문장. 리포트 화면이 이미 보여 주는 값만 담는다 — 요약과
  /// 그래프가 다른 값을 말하면 트레이너가 어느 쪽을 믿어야 할지 모른다.
  final List<String> points;

  /// `llm` 이면 생성된 것, `rule` 이면 수치에서 조립한 것. 화면이 이 둘을
  /// 구분해 말해야 트레이너가 문장을 어디까지 믿을지 안다.
  final String generatedBy;

  /// 모델이 만든 문장인가.
  bool get isGenerated => generatedBy == 'llm';

  /// 피드백 입력창에 넣을 본문. 제목 줄과 근거를 그대로 잇는다.
  String get asDraft =>
      <String>[headline, ...points.map((p) => '· $p')].join('\n');
}

/// 하루 목표 — 백엔드 `trainer_report_summary_service` 와 같은 값이다.
const int summarySodiumTargetMg = 2000;

/// 이행률이 이 아래면 주의로 본다 — 주의 배지·리포트 막대와 같은 기준.
const int summaryLowCompletion = 70;

/// 목표를 이 날 수보다 많이 넘겼으면 주의로 본다 — [WeeklyReport.isGoodWeek]
/// 와 같은 기준이다.
const int summarySodiumOverDays = 2;

/// 근거 문장 수. 셋을 넘으면 카드가 리포트 본문만큼 길어져 요약이 아니게 된다.
const int summaryMaxPoints = 3;

/// 다음 주 제안 수. 근거 세 줄과 함께 놓이므로 둘이 상한이다.
const int summaryMaxActions = 2;

/// 하루 목표의 기본값 — 회원이 적어 둔 목표가 있으면 그쪽이 먼저다(#1430).
const int summaryCalorieTargetKcal = calorieTargetKcal;
const double summarySugarTargetG = 50;

/// 칼로리가 목표에서 이만큼 벗어나면 주의로 본다. 하루하루가 목표에 딱 맞는
/// 주는 없으므로 좁게 잡으면 매주 주의가 뜬다. 백엔드와 같은 값이다.
const double summaryCalorieTolerance = 0.15;

/// 당류를 이 날 수보다 많이 넘겼으면 주의로 본다 — 나트륨과 같은 규칙.
const int summarySugarOverDays = 2;

/// 탄·단·지가 개인 목표에서 이만큼 벗어나면 균형 이탈로 본다.
const double summaryMacroTolerance = 0.25;

/// 그 주에 챙겨야 할 일 하나. (#1430)
///
/// AI 근거, 규칙 기반 요약, `다음 주 할 일`, 피드백 초안이 **같은 목록**을
/// 본다. 예전에는 당류를 이 파일의 `summaryCoachingActions` 만 따로 계산해,
/// 카드의 AI 요약과 그 아래 제안이 서로 다른 고객 상태를 말할 수 있었다.
class SummaryWatchpoint {
  /// Creates a watchpoint.
  const SummaryWatchpoint({
    required this.kind,
    required this.text,
    required this.topic,
    required this.severity,
  });

  /// 무엇에 대한 주의인가(`sodium`·`sugar`·`calories`·`macro`·`completion`·
  /// `skipped`). 화면·테스트가 종류로 집을 수 있게 남긴다.
  final String kind;

  /// 근거로 그대로 인용되는 문장. 어느 기준으로 판정했는지까지 담는다.
  final String text;

  /// 머리 문장에 넣을 짧은 말.
  final String topic;

  /// 클수록 먼저 말한다. 근거를 잘라야 할 때 입력 순서가 아니라 이 값으로
  /// 고른다 — 순서대로 자르면 위험한 항목이 조용히 빠진다.
  final int severity;
}

/// 기록이 있는 날만. 0 은 `기록 없음` 이지 `아무것도 먹지 않은 날` 이 아니고,
/// 아직 오지 않은 요일도 같은 이유로 0 이다.
List<double> _recorded(Iterable<num> values) =>
    values.where((v) => v > 0).map((v) => v.toDouble()).toList(growable: false);

double? _mean(Iterable<num> values) {
  final recorded = _recorded(values);
  if (recorded.isEmpty) return null;
  return recorded.fold<double>(0, (a, b) => a + b) / recorded.length;
}

String _basis(Object? personal) => personal == null ? '기본 목표' : '개인 목표';

/// 그 주의 주의사항 전부. **판정은 여기 한 곳에서만 한다.**
///
/// 백엔드 `trainer_report_summary_service.watchpoints` 와 같은 기준이다 —
/// 데모에서 본 판정과 실서버에서 본 판정이 갈리지 않는다.
List<SummaryWatchpoint> summaryWatchpoints(WeeklyReport report) {
  final found = <SummaryWatchpoint>[];

  final completion = report.completionAvg;
  if (completion != null && completion < summaryLowCompletion) {
    found.add(
      SummaryWatchpoint(
        kind: 'completion',
        text: '운동 이행률 평균 $completion% · 기준 $summaryLowCompletion% 미만',
        topic: '운동 이행률 $completion%',
        severity: 90,
      ),
    );
  }

  final skipped = summarySkippedExercises(report);
  if (skipped.isNotEmpty) {
    found.add(
      SummaryWatchpoint(
        kind: 'skipped',
        text: '건너뛴 운동: ${skipped.join(', ')}',
        topic: '건너뛴 운동 ${skipped.length}가지',
        severity: 70,
      ),
    );
  }

  final sodiumTarget = report.sodiumTarget ?? summarySodiumTargetMg;
  final sodium = report.sodiumAvg;
  final sodiumOver = report.sodiumOverDays ?? 0;
  if (sodium != null &&
      (sodium > sodiumTarget || sodiumOver > summarySodiumOverDays)) {
    found.add(
      SummaryWatchpoint(
        kind: 'sodium',
        text:
            '나트륨 평균 ${formatNumber(sodium)}mg · '
            '${_basis(report.sodiumTarget)} ${formatNumber(sodiumTarget)}mg '
            '초과 $sodiumOver일',
        topic: sodiumOver > 0
            ? '나트륨 목표 초과 $sodiumOver일'
            : '나트륨 평균 ${formatNumber(sodium)}mg',
        severity: 85,
      ),
    );
  }

  final sugarTarget = report.sugarTarget ?? summarySugarTargetG;
  final sugarOver = report.sugarWeek.where((g) => g > sugarTarget).length;
  final sugarMean = _mean(report.sugarWeek);
  if (sugarMean != null &&
      (sugarOver > summarySugarOverDays || sugarMean > sugarTarget)) {
    found.add(
      SummaryWatchpoint(
        kind: 'sugar',
        text:
            '당류 평균 ${formatNumber(sugarMean.round())}g · '
            '${_basis(report.sugarTarget)} ${formatNumber(sugarTarget.round())}g '
            '초과 $sugarOver일',
        topic: sugarOver > 0
            ? '당류 목표 초과 $sugarOver일'
            : '당류 평균 ${formatNumber(sugarMean.round())}g',
        severity: 80,
      ),
    );
  }

  final calorieTarget =
      (report.calorieTarget ?? summaryCalorieTargetKcal).toDouble();
  final calorieMean = _mean(report.caloriesWeek);
  if (calorieMean != null && calorieTarget > 0) {
    final gap = (calorieMean - calorieTarget) / calorieTarget;
    if (gap.abs() > summaryCalorieTolerance) {
      final direction = gap > 0 ? '초과' : '부족';
      found.add(
        SummaryWatchpoint(
          kind: 'calories',
          text:
              '칼로리 평균 ${formatNumber(calorieMean.round())}kcal · '
              '${_basis(report.calorieTarget)} '
              '${formatNumber(calorieTarget.round())}kcal '
              '대비 $direction ${(gap.abs() * 100).round()}%',
          topic: '칼로리 $direction',
          severity: 75,
        ),
      );
    }
  }

  // 탄·단·지는 **개인 목표가 있을 때만** 본다. 공통 기본값이 없는 값이라,
  // 지어낸 기준으로 균형을 나무랄 수 없다.
  final macros = <({String label, List<double> series, double? target})>[
    (label: '탄수화물', series: report.carbsWeek, target: report.carbsTarget),
    (label: '단백질', series: report.proteinWeek, target: report.proteinTarget),
    (label: '지방', series: report.fatWeek, target: report.fatTarget),
  ];
  for (final macro in macros) {
    final target = macro.target;
    if (target == null || target <= 0) continue;
    final mean = _mean(macro.series);
    if (mean == null) continue;
    final gap = (mean - target) / target;
    if (gap.abs() <= summaryMacroTolerance) continue;
    final direction = gap > 0 ? '초과' : '부족';
    found.add(
      SummaryWatchpoint(
        kind: 'macro',
        text:
            '${macro.label} 평균 ${formatNumber(mean.round())}g · '
            '개인 목표 ${formatNumber(target.round())}g '
            '대비 $direction ${(gap.abs() * 100).round()}%',
        topic: '${macro.label} $direction',
        severity: 60,
      ),
    );
  }

  found.sort((a, b) => b.severity.compareTo(a.severity));
  return found;
}

/// 그 주에 건너뛴 운동 이름. 이행률이 왜 100%가 아닌지의 답이다.
List<String> summarySkippedExercises(WeeklyReport report) {
  final skipped = <String>[];
  for (final day in report.days) {
    for (final line in day.exercises) {
      if (!line.contains('✗')) continue;
      // 분량을 뗀 이름으로 묶는다 — 같은 운동을 요일마다 건너뛴 것이 서로 다른
      // 운동 셋으로 읽히면 안 된다(#1177).
      final name = exerciseBaseName(line);
      if (name.isNotEmpty && !skipped.contains(name)) skipped.add(name);
    }
  }
  return skipped.take(summaryMaxPoints).toList(growable: false);
}

/// 카드에 실을 근거. 주의사항이 먼저고, 잘린 만큼은 `외 N건` 으로 알린다.
List<String> summaryPoints(List<String> evidence) {
  if (evidence.length <= summaryMaxPoints) return evidence;
  final kept = evidence.take(summaryMaxPoints - 1).toList();
  return <String>[...kept, '외 ${evidence.length - kept.length}건 — 리포트 본문에서 확인'];
}

/// 화면의 수치를 요약이 인용할 수 있는 문장으로 굳힌다.
///
/// **여기 없는 말은 근거가 될 수 없다.** 백엔드가 모델에 주는 목록과 같은
/// 규칙이라, 데모에서 본 문장과 실서버에서 본 문장이 같은 자리에서 나온다.
List<String> summaryEvidence(WeeklyReport report) {
  final watch = summaryWatchpoints(report);
  final kinds = watch.map((w) => w.kind).toSet();
  final lines = <String>[for (final w in watch) w.text];

  // 주의로 잡히지 않은 항목은 '잘 지켰다'는 근거다. 같은 값을 두 번 적지 않도록
  // 주의사항이 이미 말한 지표는 건너뛴다.
  final completion = report.completionAvg;
  if (completion != null && !kinds.contains('completion')) {
    lines.add('운동 이행률 평균 $completion%');
  }
  final sodium = report.sodiumAvg;
  if (sodium != null && !kinds.contains('sodium')) {
    final target = report.sodiumTarget ?? summarySodiumTargetMg;
    lines.add(
      '나트륨 평균 ${formatNumber(sodium)}mg · '
      '${_basis(report.sodiumTarget)} ${formatNumber(target)}mg '
      '초과 ${report.sodiumOverDays ?? 0}일',
    );
  }
  final calories = _mean(report.caloriesWeek);
  if (calories != null && !kinds.contains('calories')) {
    lines.add('칼로리 평균 ${formatNumber(calories.round())}kcal');
  }
  return lines;
}

/// 모델 없이 수치에서 조립하는 요약.
///
/// 데모의 기본값이자 실서버의 실패 경로다 — 공급자가 죽어도 카드가 비지
/// 않는다. 백엔드의 `_rule_summary` 와 같은 문장을 만든다.
ReportSummary ruleReportSummary(WeeklyReport report, TrainerClient client) {
  final evidence = summaryEvidence(report);
  final name = client.name;
  if (evidence.isEmpty) {
    return ReportSummary(
      headline: '$name 회원은 그 주 기록이 없어 다음 주 시작을 함께 잡아 주세요.',
      points: const <String>[],
      generatedBy: 'rule',
    );
  }

  final watch = summaryWatchpoints(report);
  final good = <String>[];
  final completion = report.completionAvg;
  if (completion != null && completion >= summaryLowCompletion) {
    good.add('운동 이행률 $completion%');
  }
  final sodium = report.sodiumAvg;
  if (sodium != null && !watch.any((w) => w.kind == 'sodium')) {
    final over = report.sodiumOverDays ?? 0;
    good.add(
      over > 0
          ? '나트륨 목표 초과 $over일'
          : '나트륨 평균 ${formatNumber(sodium)}mg',
    );
  }

  final String headline;
  if (watch.isEmpty) {
    headline = '$name 회원은 기록이 목표 범위 안에 있어 지금 강도를 유지해도 좋습니다.';
  } else {
    // 주의사항이 하나라도 있으면 `목표 범위 안` 이라고 말하지 않는다. 여럿이면
    // 가장 위험한 것을 머리에 두고, 나머지는 근거 줄이 빠짐없이 말한다.
    final top = watch.first.topic;
    final rest = watch.length > 1 ? ' 그 밖에 ${watch.length - 1}가지도 함께 보세요.' : '';
    if (good.isNotEmpty) {
      final kept = good.first;
      final keptJosa = hasFinalConsonant(kept) ? '으로' : '로';
      final careJosa = hasFinalConsonant(top) ? '을' : '를';
      headline =
          '$name 회원은 $kept$keptJosa 잘 지켰고, '
          '다음 주는 $top$careJosa 함께 챙기면 좋겠습니다.$rest';
    } else {
      final subject = hasFinalConsonant(top) ? '이' : '가';
      headline = '$name 회원은 $top$subject 목표를 벗어나 다음 주 조정이 필요합니다.$rest';
    }
  }
  return ReportSummary(
    headline: headline,
    points: summaryPoints(evidence),
    generatedBy: 'rule',
  );
}


/// 그 주 수치에서 곧바로 나오는 **다음 주 할 일**.
///
/// 요약은 지난 한 주를 말하고, 이 목록은 그래서 무엇을 하면 되는지를 말한다.
/// 트레이너에게 하는 말이라 회원에게 보낼 초안([ReportSummary.asDraft])에는
/// 넣지 않는다 — 문장의 상대가 다르다(#1177).
///
/// 모델을 부르지 않는다. 화면이 이미 보여 주는 수치에서만 나오므로 실서버든
/// 데모든 같은 제안이 뜨고, 요약 생성이 실패한 주에도 카드가 비지 않는다.
List<String> summaryCoachingActions(AppLocalizations l, WeeklyReport report) {
  final actions = <String>[];
  // 판정은 `summaryWatchpoints` 한 곳에서만 한다 — 예전에는 여기서 당류를 따로
  // 계산해, 같은 카드의 AI 요약과 이 목록이 다른 고객 상태를 말할 수 있었다.
  final watch = summaryWatchpoints(report);
  for (final w in watch) {
    switch (w.kind) {
      case 'sodium':
        actions.add(l.reportsActionSodium);
      case 'sugar':
        actions.add(
          l.reportsActionSugar(
            formatNumber((report.sugarTarget ?? summarySugarTargetG).round()),
          ),
        );
      case 'completion':
        actions.add(l.reportsActionLowCompletion);
      case 'skipped':
        final names = summarySkippedExercises(report).take(2).join(', ');
        actions.add(
          l.reportsActionSkipped('$names${hasFinalConsonant(names) ? '은' : '는'}'),
        );
      case 'calories':
        actions.add(
          l.reportsActionCalories(
            formatNumber(report.calorieTarget ?? summaryCalorieTargetKcal),
          ),
        );
      case 'macro':
        actions.add(w.text);
    }
  }

  final unlogged = report.weekCompletion.where((v) => v == 0).length;
  // 아직 오지 않은 날은 세지 않는다 — 이번 주 목요일에 "사흘 비었다" 고 하면
  // 오지도 않은 날을 나무라는 말이 된다.
  final pending = report.isCurrentWeek
      ? report.weekCompletion.length - elapsedWeekdays(nowKst())
      : 0;
  if (unlogged - pending > 0) {
    actions.add(l.reportsActionUnlogged(unlogged - pending));
  }
  final completion = report.completionAvg;
  if (completion != null && completion >= 90 && actions.isEmpty) {
    actions.add(l.reportsActionHighCompletion);
  }
  // 둘까지만. 근거 세 줄 아래에 제안이 셋까지 붙으면 왼쪽 열에서 카드가
  // 스스로 스크롤하기 시작해, 채우려던 자리가 오히려 잘려 보인다. 잘린 만큼은
  // 카드가 `외 N건` 으로 말한다(#1430).
  return actions.take(summaryMaxActions).toList(growable: false);
}

/// 카드가 다 보여 주지 못한 주의사항 수. 0 이면 숨긴 것이 없다. (#1430)
int summaryHiddenWatchCount(AppLocalizations l, WeeklyReport report) {
  final total = summaryCoachingActionsAll(l, report).length;
  return total > summaryMaxActions ? total - summaryMaxActions : 0;
}

/// 자르기 전의 전체 제안. 몇 건이 빠졌는지 세는 데 쓴다.
List<String> summaryCoachingActionsAll(AppLocalizations l, WeeklyReport report) {
  final all = <String>[for (final w in summaryWatchpoints(report)) w.text];
  final unlogged = report.weekCompletion.where((v) => v == 0).length;
  final pending = report.isCurrentWeek
      ? report.weekCompletion.length - elapsedWeekdays(nowKst())
      : 0;
  if (unlogged - pending > 0) all.add(l.reportsActionUnlogged(unlogged - pending));
  return all;
}

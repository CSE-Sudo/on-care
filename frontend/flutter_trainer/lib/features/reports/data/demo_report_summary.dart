import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 데모 리포트의 AI 요약 고정본(#2669).
///
/// 데모에는 모델이 없다. 규칙 기반 요약만 내면 실서버에서 늘 보이는 `생성`
/// 배지와 모델이 쓴 듯한 머리 문장을 데모에서 볼 수 없다. 그래서 그 주의
/// **가장 위험한 주의사항 종류**마다 미리 써 둔 머리 문장을 고르고, 근거 줄은
/// 규칙 요약의 것을 그대로 쓴다 — 수치는 리포트 화면이 보여 주는 값과 같다.
///
/// 머리 문장은 숫자를 말하지 않는다. 요일에 따라 시드 수치가 달라져도 문장이
/// 그래프와 어긋나지 않게 하려는 것이다. 이번 주와 지난 주는 다른 문장을
/// 쓴다([demoSummaryHeadline]). 근거가 하나도 없는 주는 규칙 요약
/// (`기록 없음`)을 그대로 돌려준다 — 없는 기록을 생성된 문장으로 꾸미지 않는다.
ReportSummary demoGeneratedReportSummary(
  AppLocalizations l,
  WeeklyReport report,
  TrainerClient client,
) {
  final ReportSummary rule = ruleReportSummary(l, report, client);
  if (rule.points.isEmpty) return rule;
  final List<SummaryWatchpoint> watch = summaryWatchpoints(l, report);
  final String kind = watch.isEmpty ? _steady : watch.first.kind;
  final String? headline = demoSummaryHeadline(
    l,
    kind,
    client.name,
    isCurrentWeek: report.isCurrentWeek,
  );
  if (headline == null) return rule;
  return ReportSummary(
    headline: headline,
    points: rule.points,
    generatedBy: 'llm',
  );
}

const String _steady = 'steady';

/// 주의사항 종류 [kind] 의 데모 머리 문장. 모르는 종류면 null 이다. (#2775)
///
/// 이번 주([isCurrentWeek])와 지난 주는 다른 문장이다 — 지난 주 리포트에서
/// `이번 주` 라고 하면 머리·요일 표·자동 문구가 보여 주는 주와 요약이 어긋난다.
/// 지난 주 문장은 어느 주인지를 리포트 머리의 날짜에 맡기고 `그 주` 라고 쓰며,
/// 이미 지나간 주를 두고 `다음 주` 를 약속하지 않는다. 문장은 전부 ARB 에서
/// 온다 — 언어 분기를 여기 두지 않는다.
String? demoSummaryHeadline(
  AppLocalizations l,
  String kind,
  String name, {
  required bool isCurrentWeek,
}) => switch (kind) {
  _steady =>
    isCurrentWeek
        ? l.reportsDemoSummarySteadyThisWeek(name)
        : l.reportsDemoSummarySteadyPastWeek(name),
  'completion' =>
    isCurrentWeek
        ? l.reportsDemoSummaryCompletionThisWeek(name)
        : l.reportsDemoSummaryCompletionPastWeek(name),
  'skipped' =>
    isCurrentWeek
        ? l.reportsDemoSummarySkippedThisWeek(name)
        : l.reportsDemoSummarySkippedPastWeek(name),
  'sodium' =>
    isCurrentWeek
        ? l.reportsDemoSummarySodiumThisWeek(name)
        : l.reportsDemoSummarySodiumPastWeek(name),
  'sugar' =>
    isCurrentWeek
        ? l.reportsDemoSummarySugarThisWeek(name)
        : l.reportsDemoSummarySugarPastWeek(name),
  'calories' =>
    isCurrentWeek
        ? l.reportsDemoSummaryCaloriesThisWeek(name)
        : l.reportsDemoSummaryCaloriesPastWeek(name),
  'macro' =>
    isCurrentWeek
        ? l.reportsDemoSummaryMacroThisWeek(name)
        : l.reportsDemoSummaryMacroPastWeek(name),
  _ => null,
};

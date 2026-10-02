import 'package:flutter/material.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

/// 리포트 PDF 한 장 — A4 한 쪽에 모든 것을 담는 결과지. (#2485)
///
/// 그리는 일은 회원 앱과 함께 쓰는 [ReportSheetDocument](`oncare_report`)가
/// 한다(#2652). 트레이너가 보낸 파일과 회원이 앱에서 여는 리포트가 같은 위젯·
/// 같은 계산이어야, 같은 주를 두 사람이 다른 모양·다른 점수로 보지 않는다.
/// 여기서는 이 앱의 타입과 시계(`nowKst`, 테스트가 고정할 수 있다)를 넘긴다.
class ReportResultSheet extends StatelessWidget {
  /// Creates the sheet.
  const ReportResultSheet({
    super.key,
    required this.report,
    required this.feedback,
    this.trend,
    this.history = const <WeeklyReport>[],
    this.today,
  });

  final WeeklyReport report;

  /// 회원에게 보낼 트레이너의 글.
  final String feedback;

  /// 여덟 주 운동 실적. 읽지 못했으면 null — 유형별 줄과 추이가 `미집계`.
  final ReportTrend? trend;

  /// 직전 주들의 리포트 — 4주 평균 대비에 쓴다.
  final List<WeeklyReport> history;

  /// 이번 주 리포트에서 지난 날 수를 셀 기준일. 없으면 지금.
  final DateTime? today;

  /// 결과지의 논리 크기. 높이는 폭의 √2 배 — A4 와 같은 비율이다.
  static const double width = ReportSheetDocument.width;
  static const double height = ReportSheetDocument.height;

  @override
  Widget build(BuildContext context) => ReportSheetDocument(
    report: report,
    feedback: feedback,
    trend: trend,
    history: history,
    today: today ?? nowKst(),
  );
}

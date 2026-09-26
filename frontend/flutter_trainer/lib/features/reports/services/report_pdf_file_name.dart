import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 리포트 PDF 파일명. 저장·전송(#1378)이 같은 이름을 쓴다.
///
/// 파일명은 로컬 저장뿐 아니라 multipart 헤더의 `filename` 으로도 그대로
/// 나간다. 경로 구분자 외에 제어문자까지 지우는 이유다 — 고객 이름에 개행이
/// 섞이면 헤더가 깨진다. 지운 결과가 비면 날짜만 남은 이름이 되므로 대체어를
/// 쓴다.
String reportPdfFileName(AppLocalizations l, WeeklyReport report) {
  final safeName = report.client.name
      .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f\x7f]'), '_')
      .trim();
  final name = safeName.replaceAll('_', '').trim().isEmpty
      ? l.reportsPdfFallbackClient
      : safeName;
  return '${name}_${ymd(report.weekStart)}_${l.reportsPdfFileSuffix}.pdf';
}

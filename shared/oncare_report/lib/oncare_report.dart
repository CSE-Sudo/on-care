/// 주간 리포트 결과지 — 트레이너 웹과 회원 앱이 함께 쓰는 한 장. (#2485, #2652)
///
/// 계산(`ReportSheet`)·화면(`ReportSheetDocument`)·PDF 굽기·서버 응답 읽기·데모
/// 자료를 한 패키지에 둔다. 두 앱이 각자 들고 있으면 같은 주가 두 앱에서 다른
/// 모양·다른 점수로 보인다.
library;

export 'gen/l10n/report_sheet_localizations.dart';
export 'src/demo_report_sheet.dart';
export 'src/report_jpeg_encoder.dart' show encodeReportJpeg;
export 'src/report_pdf_image.dart';
export 'src/report_sheet.dart';
export 'src/report_sheet_data.dart';
export 'src/report_sheet_document.dart';
export 'src/report_sheet_json.dart';
export 'src/report_sheet_l10n.dart';
export 'src/report_sheet_pdf.dart';
export 'src/report_sheet_values.dart';
export 'src/report_widget_capture.dart';

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_report/oncare_report.dart' show printPdf;

/// PDF 한 부를 인쇄 창에 넘긴다. 인쇄 창을 닫지 않고 끝까지 갔으면 true 다.
typedef ReportPdfPrinter =
    Future<bool> Function(Uint8List pdf, {required String name});

/// ③ 전송의 `인쇄` 가 PDF 를 인쇄 창에 넘기는 방법(#2451).
///
/// 인쇄 창은 공용 [printPdf] 가 띄운다 — 웹은 브라우저 인쇄, 네이티브는
/// `printing` 플러그인이다. 위젯 테스트에는 그 둘이 없어 이 자리를 갈아 끼운다 — 무엇을 인쇄에
/// 넘기는지는 그대로 검증된다.
final Provider<ReportPdfPrinter> reportPdfPrinterProvider =
    Provider<ReportPdfPrinter>((_) => printReportPdf);

/// [pdf] 를 그대로 인쇄한다.
///
/// 미리보기와 전송에 쓰는 한 부를 그대로 찍는다. 웹에서 `printing` 의
/// `Printing.layoutPdf` 를 쓰지 않는다 — CSP 에 막혀(#2828) 인쇄 창이 뜨지
/// 않았다.
Future<bool> printReportPdf(Uint8List pdf, {required String name}) =>
    printPdf(pdf, name: name);

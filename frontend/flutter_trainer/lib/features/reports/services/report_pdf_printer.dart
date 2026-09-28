import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

/// PDF 한 부를 인쇄 창에 넘긴다. 인쇄 창을 닫지 않고 끝까지 갔으면 true 다.
typedef ReportPdfPrinter =
    Future<bool> Function(Uint8List pdf, {required String name});

/// ③ 전송의 `인쇄` 가 PDF 를 인쇄 창에 넘기는 방법(#2451).
///
/// 인쇄 창은 `printing` 플러그인(웹에서는 브라우저 인쇄)이 띄운다. 위젯
/// 테스트에는 그 플러그인이 없어 이 자리를 갈아 끼운다 — 무엇을 인쇄에
/// 넘기는지는 그대로 검증된다.
final Provider<ReportPdfPrinter> reportPdfPrinterProvider =
    Provider<ReportPdfPrinter>((_) => printReportPdf);

/// [pdf] 를 그대로 인쇄한다.
///
/// 용지에 맞춰 다시 만들지 않는다(`dynamicLayout: false`) — 미리보기와 전송에
/// 쓰는 한 부를 그대로 찍어야 화면에서 본 것과 종이가 같다.
Future<bool> printReportPdf(Uint8List pdf, {required String name}) =>
    Printing.layoutPdf(
      onLayout: (_) async => pdf,
      name: name,
      dynamicLayout: false,
    );

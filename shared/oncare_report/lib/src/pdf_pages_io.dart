import 'dart:typed_data';

import 'package:printing/printing.dart';

/// [pdf] 의 모든 쪽을 [dpi] 해상도의 PNG 로 굽는다.
Future<List<Uint8List>> rasterPdfPages(
  Uint8List pdf, {
  double dpi = 144,
}) async {
  final List<Uint8List> pages = <Uint8List>[];
  await for (final PdfRaster page in Printing.raster(pdf, dpi: dpi)) {
    pages.add(await page.toPng());
  }
  return pages;
}

/// [pdf] 를 그대로 인쇄 창에 넘긴다. 인쇄 창을 닫지 않고 끝까지 갔으면 true 다.
///
/// 용지에 맞춰 다시 만들지 않는다(`dynamicLayout: false`) — 화면에서 본 한 부를
/// 그대로 찍어야 종이가 같다.
Future<bool> printPdf(Uint8List pdf, {required String name}) =>
    Printing.layoutPdf(
      onLayout: (_) async => pdf,
      name: name,
      dynamicLayout: false,
    );

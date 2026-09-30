/// 결과지 한 장을 PDF 한 쪽으로. (#2485, #2652)
///
/// 두 앱이 같은 순서로 만든다 — 결과지를 화면 밖에서 굽고, 한 번 양보하고,
/// A4 한 쪽에 여백 없이 얹는다. 결과지가 A4 비율이라 남는 자리가 없다.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:oncare_report/src/report_pdf_image.dart';
import 'package:oncare_report/src/report_sheet_document.dart';
import 'package:oncare_report/src/report_widget_capture.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 굽는 배율. 결과지 폭(1,000)을 1,500px 로 구우면 A4 폭에 담았을 때 180dpi
/// 남짓이라, 인쇄해도 작은 글씨가 뭉개지지 않는다. 더 올리면 웹에서 굽고
/// 싣는 동안 화면이 멈춘다(#2484).
const double kReportSheetPixelRatio = 1.5;

/// [framed] — 테마·로케일을 이미 두른 [ReportSheetDocument] — 를 구워 A4 한
/// 쪽짜리 PDF 로 만든다.
Future<Uint8List> reportSheetPdf(
  Widget framed, {
  ReportWidgetCapture capture = captureReportWidget,
  ReportJpegEncoder encode = platformReportJpegEncoder,
  ReportFrameYield yieldFrame = yieldToFrame,
  double pixelRatio = kReportSheetPixelRatio,
}) async {
  final CapturedWidget shot = await capture(
    framed,
    width: ReportSheetDocument.width,
    pixelRatio: pixelRatio,
  );
  // 굽기는 웹에서 UI 스레드에서 돈다 — 싣기 전에 한 번 양보한다(#2484).
  await yieldFrame();
  return reportSheetOnePage(shot, encode: encode, yieldFrame: yieldFrame);
}

/// 구운 결과지를 A4 한 쪽에 가득 얹는다.
Future<Uint8List> reportSheetOnePage(
  CapturedWidget shot, {
  ReportJpegEncoder encode = platformReportJpegEncoder,
  ReportFrameYield yieldFrame = yieldToFrame,
}) async {
  const PdfPageFormat format = PdfPageFormat.a4;
  final pw.Document document = pw.Document();
  final pw.ImageProvider image = await embedReportImage(
    document.document,
    shot,
    encode: encode,
    yieldFrame: yieldFrame,
  );
  document.addPage(
    pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(image, width: format.width, height: format.height),
    ),
  );
  // 날 RGB 로 실은 그림의 압축이 여기서 돈다 — 도는 동안 양보한다.
  return document.save(enableEventLoopBalancing: true);
}

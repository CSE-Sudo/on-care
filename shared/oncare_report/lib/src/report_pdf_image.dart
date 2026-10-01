import 'dart:typed_data';

import 'package:oncare_report/src/report_jpeg_encoder.dart' as platform;
import 'package:oncare_report/src/report_widget_capture.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 구운 그림을 JPEG 로 바꾸는 방법. 바꾸지 못하면 null 이다.
typedef ReportJpegEncoder =
    Future<Uint8List?> Function(
      Uint8List rgba, {
      required int width,
      required int height,
    });

/// 플랫폼 기본 인코더 — 웹은 브라우저 캔버스, 네이티브는 null(날 RGB).
const ReportJpegEncoder platformReportJpegEncoder = platform.encodeReportJpeg;

/// 긴 계산 중에 이벤트 루프에 양보하는 방법. 테스트가 세어 본다.
typedef ReportFrameYield = Future<void> Function();

/// 한 번 양보한다 — 그 사이 브라우저가 밀린 프레임을 그린다(#2484).
///
/// 웹의 Dart 는 UI 스레드 하나에서 돈다. 양보 없이 이어지는 계산 동안에는
/// 로딩 표시조차 멈춘 그림으로 남는다.
Future<void> yieldToFrame() => Future<void>.delayed(Duration.zero);

/// 한 번에 옮길 픽셀 수. 이만큼마다 [yieldToFrame] 한다 — 웹에서 한 묶음이
/// 한 프레임(16ms)을 넘지 않을 만큼이다.
const int _pixelsPerSlice = 1 << 18;

/// `RGBA` 에서 투명도를 뺀 `RGB` 를 묶음마다 양보하며 만든다.
///
/// 카드는 바탕까지 칠해 구운 불투명한 그림이라 투명도는 버려도 된다.
Future<Uint8List> rgbOfRgba(
  Uint8List rgba, {
  ReportFrameYield yieldFrame = yieldToFrame,
}) async {
  final int pixels = rgba.length ~/ 4;
  final Uint8List out = Uint8List(pixels * 3);
  for (int start = 0; start < pixels; start += _pixelsPerSlice) {
    final int end = start + _pixelsPerSlice < pixels
        ? start + _pixelsPerSlice
        : pixels;
    for (int i = start; i < end; i++) {
      out[i * 3] = rgba[i * 4];
      out[i * 3 + 1] = rgba[i * 4 + 1];
      out[i * 3 + 2] = rgba[i * 4 + 2];
    }
    if (end < pixels) await yieldFrame();
  }
  return out;
}

/// 구운 그림 [image] 를 [document] 에 싣는다(#2484).
///
/// [encode] 가 JPEG 를 주면 그대로 싣는다(`/DCTDecode`) — `pdf` 가 다시
/// 압축하지 않아 UI 스레드에서 도는 순수 Dart zlib 을 건너뛴다. 주지 못하면
/// 날 RGB 로 싣고, 압축은 `pdf` 가 문서를 저장할 때 한다.
Future<pw.ImageProvider> embedReportImage(
  PdfDocument document,
  CapturedWidget image, {
  ReportJpegEncoder encode = platformReportJpegEncoder,
  ReportFrameYield yieldFrame = yieldToFrame,
}) async {
  final Uint8List? jpeg = await encode(
    image.rgba,
    width: image.width,
    height: image.height,
  );
  if (jpeg != null) {
    return pw.ImageProxy(PdfImage.jpeg(document, image: jpeg));
  }
  final Uint8List rgb = await rgbOfRgba(image.rgba, yieldFrame: yieldFrame);
  await yieldFrame();
  // 카드는 불투명하다 — 투명도 가면(SMask)을 따로 싣지 않는다. 실으면
  // 그림마다 한 장씩 더 붙는다.
  return pw.ImageProxy(
    PdfImage(
      document,
      image: rgb,
      width: image.width,
      height: image.height,
      alpha: false,
    ),
  );
}

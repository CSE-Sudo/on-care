import 'dart:typed_data';

/// 네이티브·테스트에는 기본 JPEG 인코더가 없다 — 날 RGB 로 싣게 null 이다.
Future<Uint8List?> encodeReportJpeg(
  Uint8List rgba, {
  required int width,
  required int height,
}) async => null;

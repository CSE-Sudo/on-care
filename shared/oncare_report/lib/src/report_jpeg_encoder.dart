/// 구운 카드를 PDF 에 싣기 전에 JPEG 로 바꾸는 플랫폼별 구현(#2484).
///
/// 웹은 브라우저 캔버스가 네이티브로, 비동기로 인코딩한다. 네이티브에는 기본
/// 인코더가 없어 null 을 돌려주고, 생성기가 날 RGB 그림으로 싣는다 — 그쪽은
/// `pdf` 가 `dart:io` 의 zlib(네이티브)으로 압축해 빠르다.
library;

export 'report_jpeg_encoder_io.dart'
    if (dart.library.js_interop) 'report_jpeg_encoder_web.dart';

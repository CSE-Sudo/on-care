import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// JPEG 품질. 카드의 가는 글자 둘레가 번지지 않을 만큼 높게 둔다.
const double _quality = 0.95;

/// [rgba] 를 브라우저 캔버스로 JPEG 인코딩한다(#2484).
///
/// 웹에서 `pdf` 는 그림을 순수 Dart zlib 으로 압축하는데, 카드 그림 몇 장이면
/// UI 스레드가 초 단위로 멈춘다. 캔버스의 `toBlob` 은 네이티브 인코더를
/// 비동기로 돌려 그동안 화면이 계속 그려진다. 실패하면 null 을 돌려 생성기가
/// 예전처럼 날 RGB 로 싣게 한다.
Future<Uint8List?> encodeReportJpeg(
  Uint8List rgba, {
  required int width,
  required int height,
}) async {
  try {
    final web.HTMLCanvasElement canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement
          ..width = width
          ..height = height;
    final web.CanvasRenderingContext2D? context =
        canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) return null;
    final Uint8ClampedList pixels = Uint8ClampedList.view(
      rgba.buffer,
      rgba.offsetInBytes,
      rgba.lengthInBytes,
    );
    context.putImageData(web.ImageData(pixels.toJS, width, height.toJS), 0, 0);
    final Completer<web.Blob?> done = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? blob) => done.complete(blob)).toJS,
      'image/jpeg',
      _quality.toJS,
    );
    final web.Blob? blob = await done.future;
    if (blob == null) return null;
    final JSArrayBuffer buffer = await blob.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}

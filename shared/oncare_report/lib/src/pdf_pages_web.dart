import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// `index.html` 이 올려 둔 pdf.js. 없으면 미리보기를 만들 수 없다 — 부르는
/// 쪽이 실패 안내를 띄운다.
JSObject get _pdfjs {
  final JSObject? lib = globalContext.getProperty<JSObject?>('pdfjsLib'.toJS);
  if (lib == null) throw StateError('pdf.js is not loaded');
  return lib;
}

/// [pdf] 의 모든 쪽을 [dpi] 해상도의 PNG 로 굽는다.
///
/// pdf.js 는 받은 버퍼를 워커로 넘기며(transfer) 비운다 — 부른 쪽의 바이트가
/// 망가지지 않게 복사본을 준다.
Future<List<Uint8List>> rasterPdfPages(
  Uint8List pdf, {
  double dpi = 144,
}) async {
  final JSObject source = JSObject()
    ..setProperty('data'.toJS, Uint8List.fromList(pdf).toJS);
  final JSObject task = _pdfjs.callMethod<JSObject>('getDocument'.toJS, source);
  final JSObject document = await task
      .getProperty<JSPromise<JSObject>>('promise'.toJS)
      .toDart;
  try {
    final int count = document.getProperty<JSNumber>('numPages'.toJS).toDartInt;
    final List<Uint8List> pages = <Uint8List>[];
    for (int number = 1; number <= count; number++) {
      final JSObject page = await document
          .callMethod<JSPromise<JSObject>>('getPage'.toJS, number.toJS)
          .toDart;
      try {
        pages.add(await _renderPage(page, dpi / 72));
      } finally {
        page.callMethod<JSAny?>('cleanup'.toJS);
      }
    }
    return pages;
  } finally {
    document.callMethod<JSAny?>('destroy'.toJS);
  }
}

/// 한 쪽을 캔버스에 그려 PNG 로 만든다. [scale] 은 PDF 포인트(1/72인치)당 픽셀.
Future<Uint8List> _renderPage(JSObject page, double scale) async {
  final JSObject viewport = page.callMethod<JSObject>(
    'getViewport'.toJS,
    JSObject()..setProperty('scale'.toJS, scale.toJS),
  );
  final web.HTMLCanvasElement canvas =
      web.document.createElement('canvas') as web.HTMLCanvasElement
        ..width = viewport
            .getProperty<JSNumber>('width'.toJS)
            .toDartDouble
            .ceil()
        ..height = viewport
            .getProperty<JSNumber>('height'.toJS)
            .toDartDouble
            .ceil();
  final web.CanvasRenderingContext2D? context =
      canvas.getContext('2d') as web.CanvasRenderingContext2D?;
  if (context == null) throw StateError('no 2d canvas for the pdf page');
  final JSObject render = page.callMethod<JSObject>(
    'render'.toJS,
    JSObject()
      ..setProperty('canvasContext'.toJS, context)
      ..setProperty('viewport'.toJS, viewport),
  );
  await render.getProperty<JSPromise<JSAny?>>('promise'.toJS).toDart;
  final Completer<web.Blob?> done = Completer<web.Blob?>();
  canvas.toBlob(((web.Blob? blob) => done.complete(blob)).toJS, 'image/png');
  final web.Blob? blob = await done.future;
  if (blob == null) throw StateError('failed to encode a pdf page');
  final JSArrayBuffer buffer = await blob.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// 인쇄용 숨은 틀의 id. 다시 인쇄하면 지난 틀을 치우고 새로 단다.
const String _frameId = 'oncare-pdf-print-frame';

/// 틀이 PDF 를 다 읽기까지 기다리는 시간. 넘기면 실패로 끝낸다(#3246) —
/// `load` 가 오지 않는 브라우저에서 인쇄 버튼이 영영 `인쇄 중` 으로 잠겼다.
const Duration _printFrameLoadTimeout = Duration(seconds: 20);

/// 인쇄 창을 띄운 뒤 blob 주소를 쥐고 있는 시간. 새 창으로 연 경우 그 창이
/// 주소를 읽을 틈이 있어야 해서 바로 풀지 않는다.
const Duration _printUrlLifetime = Duration(minutes: 1);

/// 지금 달린 틀의 blob 주소와 그것을 풀 타이머.
String? _frameUrl;
Timer? _releaseTimer;

/// 지난 틀을 치우고 그 blob 주소를 푼다(#3246). 풀지 않으면 인쇄할 때마다 PDF
/// 한 부가 탭이 닫힐 때까지 메모리에 남는다.
void _releaseFrame() {
  _releaseTimer?.cancel();
  _releaseTimer = null;
  web.document.getElementById(_frameId)?.remove();
  final String? url = _frameUrl;
  _frameUrl = null;
  if (url != null) web.URL.revokeObjectURL(url);
}

/// [pdf] 를 브라우저 인쇄 창에 넘긴다.
///
/// 파일을 blob 주소로 숨은 `<iframe>` 에 띄우고 그 창의 인쇄를 부른다 —
/// CSP 의 `frame-src blob:` 이 여는 길이다. 브라우저가 인쇄 결과를 알려 주지
/// 않으므로, 인쇄 창을 띄웠으면 true 다. 틀이 [_printFrameLoadTimeout] 안에
/// 읽히지 않거나 읽다 실패하면 틀을 치우고 오류로 끝난다 — 부르는 쪽이 실패
/// 안내를 띄우고 버튼을 푼다.
Future<bool> printPdf(Uint8List pdf, {required String name}) async {
  _releaseFrame();
  final web.Blob blob = web.Blob(
    <JSAny>[Uint8List.fromList(pdf).toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final String url = web.URL.createObjectURL(blob);
  _frameUrl = url;
  final web.HTMLIFrameElement frame =
      web.document.createElement('iframe') as web.HTMLIFrameElement
        ..id = _frameId
        ..title = name
        ..style.position = 'fixed'
        ..style.right = '0'
        ..style.bottom = '0'
        ..style.width = '0'
        ..style.height = '0'
        ..style.border = '0';
  final Completer<bool> done = Completer<bool>();
  late final Timer timeout;
  void fail(Object error) {
    if (done.isCompleted) return;
    timeout.cancel();
    // 다음 인쇄가 이미 새 틀을 달았으면 그 틀은 건드리지 않는다.
    if (_frameUrl == url) _releaseFrame();
    done.completeError(error);
  }

  timeout = Timer(
    _printFrameLoadTimeout,
    () => fail(
      TimeoutException('the print frame did not load', _printFrameLoadTimeout),
    ),
  );
  frame.onload = ((web.Event _) {
    if (done.isCompleted) return;
    timeout.cancel();
    try {
      frame.contentWindow?.print();
    } catch (_) {
      // 틀 안의 인쇄를 막는 브라우저(사파리 등) — 새 창에 열어 거기서 찍게 한다.
      web.window.open(url, '_blank');
    }
    done.complete(true);
    if (_frameUrl == url) {
      _releaseTimer?.cancel();
      _releaseTimer = Timer(_printUrlLifetime, _releaseFrame);
    }
  }).toJS;
  frame.onerror = ((web.Event _) {
    fail(StateError('the print frame failed to load'));
  }).toJS;
  frame.src = url;
  web.document.body?.append(frame);
  return done.future;
}

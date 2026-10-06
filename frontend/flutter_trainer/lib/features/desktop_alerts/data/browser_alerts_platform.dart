/// 웹이면 브라우저 구현, 아니면 아무것도 하지 않는 구현(#3285).
library;

export 'browser_alerts_stub.dart'
    if (dart.library.js_interop) 'browser_alerts_web.dart';

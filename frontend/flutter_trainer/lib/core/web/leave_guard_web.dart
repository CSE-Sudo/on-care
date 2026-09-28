import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _listener;

/// `beforeunload` 로 새로 고침·탭 닫기 앞에서 브라우저 확인창을 띄운다.
void setLeaveGuard(bool Function()? shouldBlock) {
  final JSFunction? previous = _listener;
  if (previous != null) {
    web.window.removeEventListener('beforeunload', previous);
    _listener = null;
  }
  if (shouldBlock == null) return;
  final JSFunction listener = ((web.Event event) {
    if (!shouldBlock()) return;
    // 표준은 preventDefault, 오래된 브라우저는 returnValue 를 본다.
    event.preventDefault();
    (event as web.BeforeUnloadEvent).returnValue = '';
  }).toJS;
  web.window.addEventListener('beforeunload', listener);
  _listener = listener;
}

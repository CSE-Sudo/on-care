import 'dart:js_interop';

import 'package:oncare_trainer/core/web/leave_guard_registry.dart';
import 'package:web/web.dart' as web;

JSFunction? _listener;

/// `beforeunload` 로 새로 고침·탭 닫기 앞에서 브라우저 확인창을 띄운다.
///
/// 리스너는 하나만 건다 — 지키는 화면이 생기면 걸고, 모두 풀리면 뗀다. 막을지는
/// 떠나는 순간 [leaveGuards] 전체에 묻는다(#2873).
void setLeaveGuard(Object owner, bool Function()? shouldBlock) {
  leaveGuards.set(owner, shouldBlock);
  final JSFunction? current = _listener;
  if (leaveGuards.isEmpty) {
    if (current != null) {
      web.window.removeEventListener('beforeunload', current);
      _listener = null;
    }
    return;
  }
  if (current != null) return;
  final JSFunction listener = ((web.Event event) {
    if (!leaveGuards.shouldBlock()) return;
    // 표준은 preventDefault, 오래된 브라우저는 returnValue 를 본다.
    event.preventDefault();
    (event as web.BeforeUnloadEvent).returnValue = '';
  }).toJS;
  web.window.addEventListener('beforeunload', listener);
  _listener = listener;
}

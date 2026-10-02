import 'package:oncare_trainer/core/web/leave_guard_registry.dart';

/// 웹이 아닌 곳에서는 막을 새로 고침·탭 닫기가 없다 — 목록만 든다(위젯
/// 테스트가 지킴 조건을 읽을 수 있게).
void setLeaveGuard(Object owner, bool Function()? shouldBlock) =>
    leaveGuards.set(owner, shouldBlock);

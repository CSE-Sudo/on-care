import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/web/leave_guard.dart';

/// 여러 화면이 함께 쓰는 이탈 지킴 (#2873).
void main() {
  group('LeaveGuardRegistry', () {
    test('아무도 지키지 않으면 막지 않는다', () {
      final LeaveGuardRegistry registry = LeaveGuardRegistry();
      expect(registry.isEmpty, isTrue);
      expect(registry.shouldBlock(), isFalse);
    });

    test('여러 소유자 중 하나라도 참이면 막는다', () {
      final LeaveGuardRegistry registry = LeaveGuardRegistry();
      final Object my = Object();
      final Object coaching = Object();
      var myDirty = false;
      var coachingDirty = false;
      registry
        ..set(my, () => myDirty)
        ..set(coaching, () => coachingDirty);

      expect(registry.shouldBlock(), isFalse);
      coachingDirty = true;
      expect(registry.shouldBlock(), isTrue);
      coachingDirty = false;
      myDirty = true;
      expect(registry.shouldBlock(), isTrue);
    });

    test('한 소유자를 풀어도 다른 소유자의 지킴은 남는다', () {
      final LeaveGuardRegistry registry = LeaveGuardRegistry();
      final Object my = Object();
      final Object coaching = Object();
      registry
        ..set(my, () => true)
        ..set(coaching, () => true);

      registry.set(coaching, null);

      expect(registry.isRegistered(coaching), isFalse);
      expect(registry.isRegistered(my), isTrue);
      expect(registry.shouldBlock(), isTrue);

      registry.set(my, null);
      expect(registry.isEmpty, isTrue);
      expect(registry.shouldBlock(), isFalse);
    });

    test('같은 소유자가 다시 등록하면 조건을 바꾼다', () {
      final LeaveGuardRegistry registry = LeaveGuardRegistry();
      final Object owner = Object();
      registry
        ..set(owner, () => true)
        ..set(owner, () => false);

      expect(registry.shouldBlock(), isFalse);
    });
  });

  test('setLeaveGuard 는 앱 전체 목록에 소유자별로 적는다', () {
    final Object a = Object();
    final Object b = Object();
    addTearDown(() {
      setLeaveGuard(a, null);
      setLeaveGuard(b, null);
    });

    setLeaveGuard(a, () => false);
    setLeaveGuard(b, () => true);
    expect(leaveGuards.shouldBlock(), isTrue);

    // 나중에 등록한 쪽을 풀어도 앞 소유자는 그대로다 — 예전에는 마지막
    // 등록 하나만 남아 서로의 지킴을 풀었다.
    setLeaveGuard(b, null);
    expect(leaveGuards.isRegistered(a), isTrue);
    expect(leaveGuards.shouldBlock(), isFalse);
  });
}

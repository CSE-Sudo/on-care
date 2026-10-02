/// 여러 화면이 함께 쓰는 새로 고침·탭 닫기 지킴 목록. (#2873)
///
/// 탭 상태가 유지되는 셸(`StatefulShellRoute.indexedStack`)에서는 MY 프로필
/// 수정과 코칭 화면이 동시에 살아 있을 수 있다. 지킴을 하나만 들면 나중에
/// 등록한 화면이 앞 화면의 지킴을 풀어 버린다 — 그래서 화면(소유자)마다 조건을
/// 따로 들고, 떠나려는 순간 **하나라도** 막으려 하면 막는다.
///
/// 브라우저와 무관한 순수 Dart 라 단위 테스트에서 그대로 쓴다.
library;

/// 소유자별 이탈 지킴 조건.
class LeaveGuardRegistry {
  final Map<Object, bool Function()> _guards = <Object, bool Function()>{};

  /// [owner] 의 조건을 등록한다. [shouldBlock] 이 `null` 이면 그 소유자의
  /// 지킴만 푼다 — 다른 소유자의 것은 그대로 남는다.
  void set(Object owner, bool Function()? shouldBlock) {
    if (shouldBlock == null) {
      _guards.remove(owner);
    } else {
      _guards[owner] = shouldBlock;
    }
  }

  /// 지키는 화면이 하나도 없다.
  bool get isEmpty => _guards.isEmpty;

  /// [owner] 가 지킴을 등록해 두었다.
  bool isRegistered(Object owner) => _guards.containsKey(owner);

  /// 지금 떠나면 막아야 하는가 — 하나라도 참이면 막는다.
  bool shouldBlock() {
    for (final bool Function() guard in List<bool Function()>.of(
      _guards.values,
    )) {
      if (guard()) return true;
    }
    return false;
  }
}

/// 앱 전체가 함께 쓰는 지킴 목록.
final LeaveGuardRegistry leaveGuards = LeaveGuardRegistry();

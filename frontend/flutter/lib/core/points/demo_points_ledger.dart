import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/core/utils/clock.dart';

// 원장을 쓰는 목업들이 규칙도 함께 읽으므로 같이 내보낸다.
export 'package:oncare/core/points/points_rules.dart';

/// 데모 회원(김민수)의 시작 잔액. 백엔드 시드(`DEMO_OPENING_POINTS`)와 같은 값이다.
const int kDemoOpeningPoints = 1240;

/// 목업 API 의 포인트 원장. 서버 `points_ledger` 의 대역이다. (#1786)
///
/// 데모에서 기록을 만드는 곳이 셋으로 갈려 있다 — 식단은 `LocalApiInterceptor`,
/// 운동은 `MockExerciseRepository`, 루틴 완료는 `MockMemberCoachRepository`.
/// 셋이 이 원장 하나를 함께 써야 하루 한도와 MY 잔액이 한 숫자로 움직인다.
///
/// 규칙은 서버와 같다: 같은 기록은 한 번만, 한도를 넘으면 0, 기록을 지우면
/// 회수하되 잔액은 0 아래로 내려가지 않고, 회수된 적립은 그날 한도에서 빠진다.
class DemoPointsLedger {
  DemoPointsLedger({
    int openingBalance = kDemoOpeningPoints,
    DateTime Function()? now,
  }) : _balance = openingBalance,
       _now = now ?? nowKst;

  final DateTime Function() _now;
  int _balance;

  /// `sourceType/sourceId` → 그 기록이 받은 적립.
  final Map<String, _Earned> _earned = <String, _Earned>{};

  /// 현재 잔액.
  int get balance => _balance;

  /// [sourceId] 기록에 [rule] 대로 적립한다. 이미 적립한 기록이면 새로 쌓지 않고
  /// 그때 받은 값을 돌려준다.
  PointsAward award(PointsRule rule, String sourceId) {
    final _Earned? existing = _earned[_key(rule.sourceType, sourceId)];
    if (existing != null) {
      return PointsAward(awarded: existing.liveDelta, balance: _balance);
    }
    final String day = _day(_now());
    final int live = _earned.values
        .where((_Earned e) => e.rule == rule && e.day == day && !e.revoked)
        .length;
    if (live >= rule.dailyCap) {
      return PointsAward(awarded: 0, balance: _balance);
    }
    _earned[_key(rule.sourceType, sourceId)] = _Earned(
      rule: rule,
      day: day,
      delta: rule.points,
    );
    _balance += rule.points;
    return PointsAward(awarded: rule.points, balance: _balance);
  }

  /// 이미 저장된 기록이 받은 적립. 아무것도 바꾸지 않는다(재시도 응답).
  PointsAward awardedFor(PointsRule rule, String sourceId) {
    final _Earned? existing = _earned[_key(rule.sourceType, sourceId)];
    return PointsAward(awarded: existing?.liveDelta ?? 0, balance: _balance);
  }

  /// 지워지는 기록의 적립을 회수한다. 실제로 뺀 포인트를 돌려준다.
  int revoke(String sourceType, String sourceId) {
    final _Earned? existing = _earned[_key(sourceType, sourceId)];
    if (existing == null || existing.revoked) return 0;
    final int taken = math.min(existing.delta, math.max(_balance, 0));
    existing.revoked = true;
    _balance -= taken;
    return taken;
  }

  /// `sourceId` → 그 쿠폰을 교환하며 쓴 포인트(#1787). 반환하면 지운다.
  final Map<String, int> _spent = <String, int>{};

  /// 반환까지 끝난 사용. 같은 쿠폰을 두 번 돌려주지 않는다.
  final Set<String> _refunded = <String>{};

  /// 쿠폰 교환에 [cost] 만큼 쓴다. 잔액이 모자라면 아무것도 바꾸지 않고 false.
  bool spend(String sourceId, int cost) {
    if (_balance < cost || _spent.containsKey(sourceId)) return false;
    _spent[sourceId] = cost;
    _balance -= cost;
    return true;
  }

  /// [sourceId] 로 쓴 포인트를 돌려준다. 돌려준 포인트(0 이상).
  ///
  /// 서버의 `refund` 와 같다 — 회수가 적립의 짝이듯 반환은 사용의 짝이고, 같은
  /// 쿠폰에는 한 번뿐이다.
  int refund(String sourceId) {
    final int? cost = _spent[sourceId];
    if (cost == null || _refunded.contains(sourceId)) return 0;
    _refunded.add(sourceId);
    _balance += cost;
    return cost;
  }

  static String _key(String sourceType, String sourceId) =>
      '$sourceType/$sourceId';

  static String _day(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
}

class _Earned {
  _Earned({required this.rule, required this.day, required this.delta});

  final PointsRule rule;
  final String day;
  final int delta;
  bool revoked = false;

  int get liveDelta => revoked ? 0 : delta;
}

/// 목업 경로가 함께 쓰는 포인트 원장 하나.
///
/// 계정 전환에 초기화하지 않는다 — 식단 기록을 든 drift DB 도 앱 수명 동안
/// 남으므로, 원장만 비우면 남은 끼니를 지울 때 회수할 적립이 사라진다. 데모는
/// 김민수 한 계정뿐이다.
final demoPointsLedgerProvider = Provider<DemoPointsLedger>(
  (ref) => DemoPointsLedger(),
  name: 'demoPointsLedger',
);

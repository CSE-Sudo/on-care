import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/core/utils/clock.dart';

// 원장을 쓰는 목업들이 규칙도 함께 읽으므로 같이 내보낸다.
export 'package:oncare/core/points/points_rules.dart';

/// 데모 회원(김민수)의 시작 잔액. 백엔드 시드(`DEMO_OPENING_POINTS`)와 같은 값이다.
///
/// 사용처의 두 쿠폰(PT 재등록 21,000P·개인 락커 7,000P)을 데모에서 바로 교환해 볼 수
/// 있는 값이다(#1787).
const int kDemoOpeningPoints = 25000;

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

  /// 잔액이 움직인 줄(#2146). 서버 `points_ledger` 처럼 적립·사용·회수·반환마다
  /// 사유와 함께 한 줄이다 — 포인트 내역 화면이 읽는다.
  final List<_Entry> _entries = <_Entry>[];

  void _log(String kind, String reason, int delta) {
    final DateTime at = _now();
    _entries.add(
      _Entry(
        id: 'pl-demo-${_entries.length + 1}',
        kind: kind,
        reason: reason,
        delta: delta,
        day: _day(at),
        at: at,
      ),
    );
  }

  /// 적립 규칙의 사유 코드 — 서버 `EarnRule.reason` 과 같다.
  static String _reasonOf(PointsRule rule) => switch (rule) {
    PointsRule.dietEntry => 'diet_entry',
    PointsRule.exerciseManual => 'exercise_manual',
    PointsRule.routineComplete => 'routine_complete',
  };

  /// `GET /me/points/history` — 서버 `points_history_service` 와 같은 모양이다(#2146).
  ///
  /// 기록이 있는 날 기준 최근 [pageDays] 일치를 최신순으로 주고, [before] 가 있으면
  /// 그 날짜보다 앞을 준다. AI 코치 대화 차감은 하루 한 줄로 묶는다.
  Map<String, Object?> historyJson({String? before, int pageDays = 14}) {
    final List<String> days =
        <String>{
          for (final _Entry e in _entries)
            if (before == null || e.day.compareTo(before) < 0) e.day,
        }.toList()
          ..sort((String a, String b) => b.compareTo(a));
    final bool hasMore = days.length > pageDays;
    final List<String> page = days.take(pageDays).toList();
    final List<_Entry> rows =
        _entries.where((_Entry e) => page.contains(e.day)).toList()
          ..sort((_Entry a, _Entry b) => b.at.compareTo(a.at));
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    final Map<String, Map<String, Object?>> chats =
        <String, Map<String, Object?>>{};
    for (final _Entry e in rows) {
      if (e.kind == 'spend' && e.reason == 'ai_chat') {
        final Map<String, Object?> grouped = chats.putIfAbsent(e.day, () {
          final Map<String, Object?> row = e.toJson()
            ..['delta'] = 0
            ..['count'] = 0;
          items.add(row);
          return row;
        });
        grouped['delta'] = (grouped['delta']! as int) + e.delta;
        grouped['count'] = (grouped['count']! as int) + 1;
        continue;
      }
      items.add(e.toJson());
    }
    return <String, Object?>{
      'balance': _balance,
      'items': items,
      'next_before': hasMore && page.isNotEmpty ? page.last : null,
    };
  }

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
    _log('earn', _reasonOf(rule), rule.points);
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
    _log('revoke', _reasonOf(existing.rule), -taken);
    return taken;
  }

  /// `sourceId` → 그 쿠폰을 교환하며 쓴 포인트(#1787). 반환하면 지운다.
  final Map<String, int> _spent = <String, int>{};

  /// `sourceId` → 그 사용의 사유. 반환 줄도 같은 사유를 단다.
  final Map<String, String> _spentReason = <String, String>{};

  /// 반환까지 끝난 사용. 같은 쿠폰을 두 번 돌려주지 않는다.
  final Set<String> _refunded = <String>{};

  /// [cost] 만큼 쓴다. 잔액이 모자라면 아무것도 바꾸지 않고 false.
  ///
  /// [reason] 은 서버 원장과 같은 사유 코드다(`coupon_<항목>`·`streak_shield`·
  /// `ai_chat` …) — 포인트 내역이 무엇에 썼는지 적는다(#2146).
  bool spend(String sourceId, int cost, {required String reason}) {
    if (_balance < cost || _spent.containsKey(sourceId)) return false;
    _spent[sourceId] = cost;
    _spentReason[sourceId] = reason;
    _balance -= cost;
    _log('spend', reason, -cost);
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
    _log('refund', _spentReason[sourceId] ?? 'refund', cost);
    return cost;
  }

  /// 하루 한도 없는 적립 — 주간 챌린지 보상(#1789). 같은 [sourceId] 에는 한 번뿐이다.
  ///
  /// 서버의 `credit` 과 같다. 적립한 포인트(0 이상)를 돌려준다.
  final Set<String> _credited = <String>{};

  int credit(
    String sourceId,
    int amount, {
    String reason = 'challenge_reward',
  }) {
    if (amount <= 0 || !_credited.add(sourceId)) return 0;
    _balance += amount;
    _log('earn', reason, amount);
    return amount;
  }

  static String _key(String sourceType, String sourceId) =>
      '$sourceType/$sourceId';

  static String _day(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
}

class _Entry {
  _Entry({
    required this.id,
    required this.kind,
    required this.reason,
    required this.delta,
    required this.day,
    required this.at,
  });

  final String id;
  final String kind;
  final String reason;
  final int delta;
  final String day;
  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'reason': reason,
    'delta': delta,
    'count': 1,
    'kst_date': day,
    'created_at': at.toIso8601String(),
  };
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

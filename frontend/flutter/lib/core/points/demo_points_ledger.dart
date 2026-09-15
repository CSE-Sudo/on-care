import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/core/utils/clock.dart';

/// 데모 회원(김민수)의 시작 잔액. 백엔드 시드(`DEMO_OPENING_POINTS`)와 같은 값이다.
const int kDemoOpeningPoints = 1240;

/// 적립 규칙 — 백엔드 `points_service` 의 규칙과 같다. (#1786)
///
/// 하루 한도는 KST 달력 날짜로 센다. 한쪽만 고치면 데모와 실서버가 같은 기록에
/// 다른 포인트를 준다.
enum PointsRule {
  /// 사진 분석으로 끼니가 새로 저장될 때.
  dietEntry(sourceType: 'diet_entry', points: 50, dailyCap: 3),

  /// 회원이 직접 추가한 운동.
  exerciseManual(sourceType: 'exercise_session', points: 20, dailyCap: 3),

  /// AI 가 추천한 루틴을 완료해 생긴 운동 기록.
  aiRoutineComplete(sourceType: 'exercise_session', points: 50, dailyCap: 1);

  const PointsRule({
    required this.sourceType,
    required this.points,
    required this.dailyCap,
  });

  /// 적립의 근거가 된 기록 종류. 회수할 때 이 값과 기록 id 로 찾는다.
  final String sourceType;
  final int points;
  final int dailyCap;
}

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

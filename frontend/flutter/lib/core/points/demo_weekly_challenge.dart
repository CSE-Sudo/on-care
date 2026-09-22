import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_coupon_book.dart' show DemoCouponResult;
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';

/// [monday] 주에 운동 기록이 있는 날들(자정으로 자른 날짜).
typedef DemoExerciseDays = Future<Set<DateTime>> Function(DateTime monday);

/// 목업 API 의 주간 운동 챌린지. 서버 `weekly_challenge_service` 의 대역이다. (#1789)
///
/// 규칙은 서버와 같다:
/// - 한 주는 월요일~일요일. 참가는 월·화요일에만, 한 주에 한 번이고 100P 를 건다.
/// - 목표는 참가할 때의 주간 운동 횟수 목표로 고정한다(없으면 3, 7 초과는 7).
/// - 진행은 운동 기록이 있는 날 수다. 같은 날 여러 번은 1회, 오늘 이후 날짜는 세지 않는다.
/// - 주가 끝난 뒤 [settleDue] 가 한 번 판정한다. 채웠으면 200P 를 적립하고, 못 채웠으면
///   건 포인트는 사라진다. 판정마다 결과 알림 한 건([DemoChallengeNotice])을 돌려준다.
///
/// 판정은 읽는 쪽이 먼저 부른다 — 목업 API 가 챌린지·사용처·잔액·알림함을 답하기
/// 전에 부른다. 서버의 늦은 판정과 같은 자리다.
///
/// 운동한 날은 목업 운동 저장소가 붙이는 [recordedDays] 로 센다. 저장소가 아직
/// 만들어지지 않았으면 목업 API 가 자기 운동 표로 센다.
class DemoWeeklyChallenge {
  DemoWeeklyChallenge({
    required DemoPointsLedger ledger,
    DateTime Function()? now,
  }) : _ledger = ledger,
       _now = now ?? nowKst;

  /// 참가할 때 거는 포인트와 목표를 채우면 돌려받는 포인트. 서버와 같다.
  static const int stake = 100;
  static const int reward = 200;

  /// 목표가 없을 때의 목표와, 한 주에 셀 수 있는 최대 날 수.
  static const int defaultGoal = 3;
  static const int maxGoal = 7;

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  final List<_DemoChallenge> _challenges = <_DemoChallenge>[];
  int _sequence = 0;

  /// 목업 운동 저장소가 붙이는 운동한 날 출처. 앱의 목업 모드에서 회원이 추가한
  /// 운동은 그 저장소에만 있다.
  Set<DateTime> Function(DateTime monday)? recordedDays;

  /// 참가하면 걸릴 목표 — 서버 `goal_for` 와 같은 규칙.
  static int goalOf(int? weeklyWorkoutGoal) =>
      weeklyWorkoutGoal == null || weeklyWorkoutGoal < 1
      ? defaultGoal
      : math.min(weeklyWorkoutGoal, maxGoal);

  /// 주가 끝난 진행 중 챌린지를 판정한다. 이번에 판정한 것의 결과 알림을 돌려준다.
  Future<List<DemoChallengeNotice>> settleDue(DemoExerciseDays daysOf) async {
    final DateTime thisMonday = _mondayOf(_today());
    final List<DemoChallengeNotice> notices = <DemoChallengeNotice>[];
    for (final _DemoChallenge c in List<_DemoChallenge>.of(_challenges)) {
      if (c.status != _active || !c.weekStart.isBefore(thisMonday)) continue;
      final int days = _count(
        await daysOf(c.weekStart),
        c.weekStart,
        _addDays(c.weekStart, 6),
      );
      // 기다리는 사이 다른 읽기가 먼저 판정했으면 건너뛴다 — 보상·알림은 한 번이다.
      if (c.status != _active) continue;
      final bool succeeded = days >= c.goal;
      c
        ..status = succeeded ? _succeeded : _failed
        ..finalDays = days
        ..settledAt = _now();
      if (succeeded) _ledger.credit(c.id, c.reward);
      notices.add(_notice(c, days: days, succeeded: succeeded));
    }
    return notices;
  }

  /// `GET /me/challenges/weekly`. [goal] 은 회원의 주간 운동 횟수 목표.
  Future<Map<String, Object?>> stateJson({
    required DemoExerciseDays daysOf,
    int? goal,
  }) async {
    final DateTime today = _today();
    final DateTime monday = _mondayOf(today);
    final _DemoChallenge? row = _forWeek(monday);
    final int balance = _ledger.balance;
    final int progress = _count(await daysOf(monday), monday, today);
    final String? blocked = row != null
        ? 'already_joined'
        : !_isJoinDay(today)
        ? 'join_closed'
        : balance < stake
        ? 'insufficient_points'
        : null;
    return <String, Object?>{
      'week_start': _ymd(monday),
      'week_end': _ymd(_addDays(monday, 6)),
      'join_until': _ymd(_addDays(monday, 1)),
      'stake': row?.stake ?? stake,
      'reward': row?.reward ?? reward,
      'goal': row?.goal ?? goalOf(goal),
      'progress': progress,
      'balance': balance,
      'joinable': blocked == null,
      'blocked_reason': blocked,
      'shortfall': math.max(stake - balance, 0),
      'challenge': row == null ? null : _json(row, progress: progress),
    };
  }

  /// `POST /me/challenges/weekly/join`.
  Future<DemoCouponResult> join({
    required DemoExerciseDays daysOf,
    int? goal,
    String? clientRequestId,
  }) async {
    if (clientRequestId != null) {
      final _DemoChallenge? existing = _challenges
          .where((_DemoChallenge c) => c.clientRequestId == clientRequestId)
          .firstOrNull;
      if (existing != null) {
        return DemoCouponResult(201, await _joinJson(existing, daysOf));
      }
    }
    final DateTime today = _today();
    final DateTime monday = _mondayOf(today);
    if (_forWeek(monday) != null) {
      return _error(409, '이번 주 챌린지에 이미 참가했어요.');
    }
    if (!_isJoinDay(today)) {
      return _error(409, '주간 챌린지는 월·화요일에만 참가할 수 있어요.');
    }
    final int shortfall = stake - _ledger.balance;
    if (shortfall > 0) return _error(409, '포인트가 ${shortfall}P 부족해요.');

    final _DemoChallenge challenge = _DemoChallenge(
      id: 'chl-demo-${++_sequence}',
      weekStart: monday,
      goal: goalOf(goal),
      clientRequestId: clientRequestId,
    );
    if (!_ledger.spend(challenge.id, stake, reason: 'challenge_stake')) {
      return _error(409, '포인트가 부족해요.');
    }
    _challenges.add(challenge);
    return DemoCouponResult(201, await _joinJson(challenge, daysOf));
  }

  /// `GET /me/challenges` — 최근 주 먼저, 최대 20.
  Future<List<Map<String, Object?>>> historyJson({
    required DemoExerciseDays daysOf,
  }) async {
    final DateTime today = _today();
    final List<_DemoChallenge> ordered = List<_DemoChallenge>.of(_challenges)
      ..sort(
        (_DemoChallenge a, _DemoChallenge b) =>
            b.weekStart.compareTo(a.weekStart),
      );
    return <Map<String, Object?>>[
      for (final _DemoChallenge c in ordered.take(20))
        _json(
          c,
          progress: c.status == _active
              ? _count(await daysOf(c.weekStart), c.weekStart, today)
              : null,
        ),
    ];
  }

  // ---- 내부 ----

  static const String _active = 'active';
  static const String _succeeded = 'succeeded';
  static const String _failed = 'failed';

  DateTime _today() {
    final DateTime now = _now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

  static DateTime _addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  static bool _isJoinDay(DateTime day) =>
      day.weekday == DateTime.monday || day.weekday == DateTime.tuesday;

  _DemoChallenge? _forWeek(DateTime monday) => _challenges
      .where((_DemoChallenge c) => c.weekStart == monday)
      .firstOrNull;

  /// [days] 중 [monday] ~ min(일요일, [last]) 안의 날 수.
  static int _count(Set<DateTime> days, DateTime monday, DateTime last) {
    final DateTime sunday = _addDays(monday, 6);
    final DateTime end = last.isAfter(sunday) ? sunday : last;
    return days
        .map((DateTime d) => DateTime(d.year, d.month, d.day))
        .where((DateTime d) => !d.isBefore(monday) && !d.isAfter(end))
        .toSet()
        .length;
  }

  Future<Map<String, Object?>> _joinJson(
    _DemoChallenge c,
    DemoExerciseDays daysOf,
  ) async => <String, Object?>{
    'challenge': _json(
      c,
      progress: c.status == _active
          ? _count(await daysOf(c.weekStart), c.weekStart, _today())
          : null,
    ),
    'spent': c.stake,
    'balance': _ledger.balance,
  };

  Map<String, Object?> _json(_DemoChallenge c, {int? progress}) {
    final int days = c.finalDays ?? progress ?? 0;
    return <String, Object?>{
      'id': c.id,
      'week_start': _ymd(c.weekStart),
      'week_end': _ymd(_addDays(c.weekStart, 6)),
      'goal': c.goal,
      'progress': days,
      'stake': c.stake,
      'reward': c.reward,
      'status': c.status,
      'achieved': days >= c.goal,
      'rewarded': c.status == _succeeded ? c.reward : 0,
      'joined_at': c.joinedAt.toIso8601String(),
      'settled_at': c.settledAt?.toIso8601String(),
    };
  }

  /// 서버 `_result_message` 와 같은 문구.
  static DemoChallengeNotice _notice(
    _DemoChallenge c, {
    required int days,
    required bool succeeded,
  }) {
    final DateTime end = _addDays(c.weekStart, 6);
    final String period =
        '${c.weekStart.month}월 ${c.weekStart.day}일~${end.month}월 ${end.day}일';
    return succeeded
        ? DemoChallengeNotice(
            id: 'noti-${c.id}',
            title: '주간 챌린지 성공! ${c.reward}P를 받았어요',
            body: '$period 목표 ${c.goal}회를 채워 ${c.reward}P를 돌려받았어요.',
          )
        : DemoChallengeNotice(
            id: 'noti-${c.id}',
            title: '주간 챌린지 목표를 채우지 못했어요',
            body:
                '$period 목표 ${c.goal}회 중 $days회 운동해 건 ${c.stake}P는 사라졌어요. '
                '다음 주 월·화요일에 다시 참가할 수 있어요.',
          );
  }

  static DemoCouponResult _error(int status, String detail) =>
      DemoCouponResult(status, <String, Object?>{'detail': detail});

  static String _ymd(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// 판정 결과 알림 한 건. 목업 API 가 알림함에 넣는다(`category: benefits`).
class DemoChallengeNotice {
  const DemoChallengeNotice({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;
}

class _DemoChallenge {
  _DemoChallenge({
    required this.id,
    required this.weekStart,
    required this.goal,
    this.clientRequestId,
  }) : joinedAt = nowKst();

  final String id;
  final DateTime weekStart;
  final int goal;
  final int stake = DemoWeeklyChallenge.stake;
  final int reward = DemoWeeklyChallenge.reward;
  final String? clientRequestId;
  final DateTime joinedAt;
  String status = 'active';
  int? finalDays;
  DateTime? settledAt;
}

/// 목업 경로가 함께 쓰는 주간 챌린지 하나 — 목업 API 와 목업 운동 저장소가 같은
/// 인스턴스를 본다. 포인트는 [demoPointsLedgerProvider] 에서 빠지고 들어온다.
///
/// 계정 전환에 초기화하지 않는다 — 건 포인트가 든 원장과 함께 앱 수명 동안 남는다.
final demoWeeklyChallengeProvider = Provider<DemoWeeklyChallenge>(
  (ref) => DemoWeeklyChallenge(ledger: ref.watch(demoPointsLedgerProvider)),
  name: 'demoWeeklyChallenge',
);

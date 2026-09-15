/// 주간 운동 챌린지 — 이번 주 상태와 참가 기록. (#1789)
///
/// 참가 가능 여부·목표·진행은 서버(`GET /me/challenges/weekly`)가 정한다. 앱이
/// "월·화요일에만" 같은 규칙을 따로 들고 있으면 규칙이 바뀔 때 화면만 옛 규칙으로 남는다.
library;

import 'dart:math' as math;

enum ChallengeStatus { active, succeeded, failed }

ChallengeStatus _statusFrom(Object? raw) => switch (raw) {
  'succeeded' => ChallengeStatus.succeeded,
  'failed' => ChallengeStatus.failed,
  _ => ChallengeStatus.active,
};

/// 참가 버튼을 막는 이유. 앱이 모르는 값은 [unknown] 이고 버튼만 막는다.
enum ChallengeBlockReason {
  alreadyJoined,
  joinClosed,
  insufficientPoints,
  unknown,
}

ChallengeBlockReason? _blockFrom(Object? raw) => switch (raw) {
  null => null,
  'already_joined' => ChallengeBlockReason.alreadyJoined,
  'join_closed' => ChallengeBlockReason.joinClosed,
  'insufficient_points' => ChallengeBlockReason.insufficientPoints,
  _ => ChallengeBlockReason.unknown,
};

/// `YYYY-MM-DD` → 그날 자정. 깨진 값은 1970-01-01 이다.
DateTime _dayFrom(Object? raw) {
  final DateTime? parsed = DateTime.tryParse(raw is String ? raw : '');
  if (parsed == null) return DateTime(1970);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

/// 참가한 챌린지 한 건.
class Challenge {
  const Challenge({
    required this.id,
    required this.weekStart,
    required this.weekEnd,
    required this.goal,
    required this.progress,
    required this.stake,
    required this.reward,
    required this.status,
    this.rewarded = 0,
  });

  final String id;

  /// 그 주의 월요일·일요일.
  final DateTime weekStart;
  final DateTime weekEnd;

  /// 참가할 때 고정된 목표(운동한 날 수).
  final int goal;

  /// 운동 기록이 있는 날 수. 진행 중이면 지금까지, 판정했으면 판정 때 값.
  final int progress;
  final int stake;
  final int reward;
  final ChallengeStatus status;

  /// 받은 보상. 성공이 아니면 0.
  final int rewarded;

  /// 목표를 채웠는가. 진행 중에도 참일 수 있다 — 보상은 주가 끝나야 받는다.
  bool get achieved => progress >= goal;

  /// 목표까지 남은 날 수.
  int get remaining => math.max(goal - progress, 0);

  factory Challenge.fromJson(Map<String, Object?> json) => Challenge(
    id: json['id']! as String,
    weekStart: _dayFrom(json['week_start']),
    weekEnd: _dayFrom(json['week_end']),
    goal: _int(json['goal']),
    progress: _int(json['progress']),
    stake: _int(json['stake']),
    reward: _int(json['reward']),
    status: _statusFrom(json['status']),
    rewarded: _int(json['rewarded']),
  );
}

/// 이번 주 챌린지와 지금 참가할 수 있는지.
class WeeklyChallenge {
  const WeeklyChallenge({
    required this.weekStart,
    required this.weekEnd,
    required this.joinUntil,
    required this.stake,
    required this.reward,
    required this.goal,
    required this.progress,
    required this.balance,
    required this.joinable,
    this.blockReason,
    this.shortfall = 0,
    this.challenge,
  });

  final DateTime weekStart;
  final DateTime weekEnd;

  /// 참가할 수 있는 마지막 날(화요일).
  final DateTime joinUntil;
  final int stake;
  final int reward;

  /// 참가했으면 고정된 목표, 아니면 지금 참가하면 걸릴 목표.
  final int goal;

  /// 이번 주 오늘까지 운동 기록이 있는 날 수(참가 여부와 상관없다).
  final int progress;
  final int balance;
  final bool joinable;
  final ChallengeBlockReason? blockReason;

  /// 건 포인트에 모자란 포인트. 모자라지 않으면 0.
  final int shortfall;

  /// 이번 주 참가 기록. 참가하지 않았으면 null.
  final Challenge? challenge;

  factory WeeklyChallenge.fromJson(Map<String, Object?> json) {
    final Object? raw = json['challenge'];
    return WeeklyChallenge(
      weekStart: _dayFrom(json['week_start']),
      weekEnd: _dayFrom(json['week_end']),
      joinUntil: _dayFrom(json['join_until']),
      stake: _int(json['stake']),
      reward: _int(json['reward']),
      goal: _int(json['goal']),
      progress: _int(json['progress']),
      balance: _int(json['balance']),
      joinable: json['joinable'] == true,
      blockReason: _blockFrom(json['blocked_reason']),
      shortfall: _int(json['shortfall']),
      challenge: raw is Map
          ? Challenge.fromJson(raw.cast<String, Object?>())
          : null,
    );
  }
}

/// 참가 응답 — 참가 기록, 건 포인트, 그 뒤의 잔액.
class ChallengeJoin {
  const ChallengeJoin({
    required this.challenge,
    required this.spent,
    required this.balance,
  });

  final Challenge challenge;
  final int spent;
  final int balance;

  factory ChallengeJoin.fromJson(Map<String, Object?> json) => ChallengeJoin(
    challenge: Challenge.fromJson(
      (json['challenge']! as Map<Object?, Object?>).cast<String, Object?>(),
    ),
    spent: _int(json['spent']),
    balance: _int(json['balance']),
  );
}

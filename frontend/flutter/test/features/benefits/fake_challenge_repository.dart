import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/domain/repositories/challenge_repository.dart';

/// 위젯 테스트용 주간 챌린지 저장소 — 넣어 준 상태를 돌려주고 참가를 기록한다. (#1789)
class FakeChallengeRepository implements ChallengeRepository {
  FakeChallengeRepository({WeeklyChallenge? weekly, List<Challenge>? history})
    : weekly = weekly ?? weeklyWith(),
      history = history ?? <Challenge>[];

  WeeklyChallenge weekly;
  List<Challenge> history;

  /// 참가 요청 수.
  int joins = 0;

  /// 참가를 서버 오류(409)로 실패시킨다.
  bool failJoin = false;

  int weeklyCalls = 0;
  int historyCalls = 0;

  @override
  Future<WeeklyChallenge> fetchWeekly() async {
    weeklyCalls++;
    return weekly;
  }

  @override
  Future<List<Challenge>> fetchHistory() async {
    historyCalls++;
    return history;
  }

  @override
  Future<ChallengeJoin> join({String? clientRequestId}) async {
    joins++;
    if (failJoin) throw const ServerError(statusCode: 409);
    final Challenge joined = challengeOf(
      id: 'chl-new-$joins',
      goal: weekly.goal,
      progress: weekly.progress,
    );
    final int balance = weekly.balance - weekly.stake;
    weekly = weeklyWith(
      balance: balance,
      goal: weekly.goal,
      progress: weekly.progress,
      joinable: false,
      blockReason: ChallengeBlockReason.alreadyJoined,
      challenge: joined,
    );
    history = <Challenge>[joined, ...history];
    return ChallengeJoin(challenge: joined, spent: 100, balance: balance);
  }
}

/// 2026-09-14(월) 주의 챌린지 상태.
WeeklyChallenge weeklyWith({
  int balance = 1240,
  int goal = 3,
  int progress = 0,
  bool joinable = true,
  ChallengeBlockReason? blockReason,
  int shortfall = 0,
  Challenge? challenge,
}) => WeeklyChallenge(
  weekStart: DateTime(2026, 9, 14),
  weekEnd: DateTime(2026, 9, 20),
  joinUntil: DateTime(2026, 9, 15),
  stake: 100,
  reward: 200,
  goal: goal,
  progress: progress,
  balance: balance,
  joinable: joinable,
  blockReason: blockReason,
  shortfall: shortfall,
  challenge: challenge,
);

Challenge challengeOf({
  String id = 'chl-1',
  int goal = 3,
  int progress = 0,
  ChallengeStatus status = ChallengeStatus.active,
  DateTime? weekStart,
}) {
  final DateTime start = weekStart ?? DateTime(2026, 9, 14);
  return Challenge(
    id: id,
    weekStart: start,
    weekEnd: DateTime(start.year, start.month, start.day + 6),
    goal: goal,
    progress: progress,
    stake: 100,
    reward: 200,
    status: status,
    rewarded: status == ChallengeStatus.succeeded ? 200 : 0,
  );
}

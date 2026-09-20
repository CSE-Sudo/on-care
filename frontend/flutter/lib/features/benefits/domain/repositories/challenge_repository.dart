import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';

/// 주간 운동 챌린지. (#1789)
///
/// 구현은 Dio 하나다 — 데모 모드에서는 `LocalApiInterceptor` 가 같은 경로를 받아
/// 서버와 같은 규칙으로 답한다. 그래서 건 포인트·보상이 목업 원장에서 움직여 MY
/// 잔액과 한 숫자가 된다.
abstract interface class ChallengeRepository {
  /// 이번 주 챌린지와 지금 참가할 수 있는지. 끝난 주는 서버가 먼저 판정한다.
  Future<WeeklyChallenge> fetchWeekly();

  /// 이번 주 챌린지에 참가한다(포인트를 건다). [clientRequestId] 가 같은 재시도는
  /// 두 번 걸지 않는다. 규칙에 막히면(월·화요일 아님 등) 서버 오류로 올라온다.
  Future<ChallengeJoin> join({String? clientRequestId});
}

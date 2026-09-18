/// 데모에서 담당 트레이너 연결을 끊으면 담당 코치도 없어진다. (#1865)
///
/// 연결 상태는 헬스장 저장소가 들고 있다. 코치 저장소가 그것과 따로 고정값을
/// 돌려주면, 트레이너를 끊었는데 헤더는 여전히 트레이너 채팅으로 가는 한쪽만
/// 끊긴 화면이 된다(#1840 의 전환이 일어나지 않는다).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

void main() {
  MockMemberCoachRepository coachOf(MockGymRepository gym) =>
      MockMemberCoachRepository(linked: () => gym.hasTrainer);

  test('트레이너를 끊으면 담당 코치가 없어진다', () async {
    final MockGymRepository gym = MockGymRepository();
    final MockMemberCoachRepository coach = coachOf(gym);
    expect(await coach.fetchCoach(), isNotNull);

    await gym.disconnectMyTrainer();

    expect(await coach.fetchCoach(), isNull);
  });

  test('헬스장을 떠나도 담당 코치가 없어진다', () async {
    final MockGymRepository gym = MockGymRepository();
    final MockMemberCoachRepository coach = coachOf(gym);

    await gym.disconnectMyGym();

    expect(await coach.fetchCoach(), isNull);
  });

  test('담당이 없으면 대화·미읽음은 내 것이 아니다', () async {
    final MockGymRepository gym = MockGymRepository();
    final MockMemberCoachRepository coach = coachOf(gym);
    expect(await coach.fetchChat(), isNotEmpty);

    await gym.disconnectMyTrainer();

    expect(await coach.fetchChat(), isEmpty);
    expect(await coach.unreadCount(), 0);
  });

  test('담당이 없으면 배정 운동 대신 AI 추천이 온다 (#2014)', () async {
    // 서버는 담당이 없는 회원에게 보수적으로 좁힌 추천을 내려준다(#782).
    // 데모가 빈 목록을 돌려주면 연결을 끊은 회원의 운동 탭에 받을 것이 하나도
    // 남지 않는다.
    final MockGymRepository gym = MockGymRepository();
    final MockMemberCoachRepository coach = coachOf(gym);
    final List<CoachRoutine> assigned = await coach.fetchRoutines();
    expect(assigned, isNotEmpty);
    expect(assigned.any((CoachRoutine r) => r.isTrainerRecommended), isTrue);

    await gym.disconnectMyTrainer();

    final List<CoachRoutine> auto = await coach.fetchRoutines();
    expect(auto, isNotEmpty);
    // 전부 AI 추천이다 — 트레이너가 배정한 것이 남아 있으면 안 된다.
    expect(auto.every((CoachRoutine r) => r.isAiRecommended), isTrue);
  });

  test('연결을 물을 곳이 없으면 예전처럼 담당이 있다', () async {
    // 연결을 끊을 길이 없는 테스트·단독 사용에서는 지금 동작 그대로다.
    final MockMemberCoachRepository coach = MockMemberCoachRepository();

    expect(await coach.fetchCoach(), isNotNull);
    expect(await coach.fetchRoutines(), isNotEmpty);
  });
}

/// 데모에서 담당 트레이너 연결을 끊으면 담당 코치도 없어진다. (#1865)
///
/// 연결 상태는 헬스장 저장소가 들고 있다. 코치 저장소가 그것과 따로 고정값을
/// 돌려주면, 트레이너를 끊었는데 헤더는 여전히 트레이너 채팅으로 가는 한쪽만
/// 끊긴 화면이 된다(#1840 의 전환이 일어나지 않는다).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';

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

  test('담당이 없으면 배정 운동·대화·미읽음도 내 것이 아니다', () async {
    final MockGymRepository gym = MockGymRepository();
    final MockMemberCoachRepository coach = coachOf(gym);
    expect(await coach.fetchRoutines(), isNotEmpty);
    expect(await coach.fetchChat(), isNotEmpty);

    await gym.disconnectMyTrainer();

    expect(await coach.fetchRoutines(), isEmpty);
    expect(await coach.fetchChat(), isEmpty);
    expect(await coach.unreadCount(), 0);
  });

  test('연결을 물을 곳이 없으면 예전처럼 담당이 있다', () async {
    // 연결을 끊을 길이 없는 테스트·단독 사용에서는 지금 동작 그대로다.
    final MockMemberCoachRepository coach = MockMemberCoachRepository();

    expect(await coach.fetchCoach(), isNotNull);
    expect(await coach.fetchRoutines(), isNotEmpty);
  });
}

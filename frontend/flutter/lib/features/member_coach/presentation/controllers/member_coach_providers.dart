import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/active_polling_stream.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';

/// Selects the real Dio-backed coach repository against the FastAPI backend,
/// or the in-memory demo for `USE_MOCK_API=true`. One mock instance per
/// provider lifetime so demo chat sends persist for the session.
final memberCoachRepositoryProvider = Provider<MemberCoachRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    // 데모에는 서버가 없다. 실서버는 루틴 완료를 받으면 회원 운동 기록 한 건을
    // 함께 만들고 취소하면 지우는데(#1131), 그 일을 이 대역이 대신하도록 운동
    // 저장소를 건네준다 — 그러지 않으면 체크해도 `운동 현황` 이 꿈쩍하지 않는다.
    // 파생 기록(출처 `assigned_routine`)을 만들고 지우는 일은 목업 저장소만
    // 할 수 있다. 테스트가 운동 저장소를 다른 대역으로 갈아 끼우면 루틴 상태만
    // 바뀌는 예전 동작으로 떨어진다 — 화면이 죽는 것보다 낫다.
    final ExerciseRepository exercise = ref.watch(exerciseRepositoryProvider);
    final GymRepository gym = ref.watch(gymRepositoryProvider);
    return MockMemberCoachRepository(
      exercise: exercise is MockExerciseRepository ? exercise : null,
      // 루틴 완료(추천·배정) 적립도 같은 원장이다(#1786).
      points: ref.watch(demoPointsLedgerProvider),
      // 담당 트레이너 연결은 헬스장 저장소가 들고 있다 — 트레이너를 끊으면
      // 담당 코치도 없어야 헤더가 AI 챗봇 입구로 바뀐다(#1840, #1865).
      linked: gym is MockGymRepository ? () => gym.hasTrainer : null,
    );
  }
  return DioMemberCoachRepository(ref.watch(dioProvider));
}, name: 'memberCoachRepository');

/// The member's assigned coach (null when none).
final memberCoachProvider = FutureProvider<MemberCoach?>((ref) {
  return ref.watch(memberCoachRepositoryProvider).fetchCoach();
});

/// Routines the coach has assigned to the member.
final coachRoutinesProvider = FutureProvider<List<CoachRoutine>>((ref) {
  return ref.watch(memberCoachRepositoryProvider).fetchRoutines();
});

/// 트레이너가 잡아 준 PT 일정. 담당이 없거나 잡힌 일정이 없으면 빈 목록이라,
/// 화면이 늘어나지 않는다. (#490)
final coachSessionsProvider = FutureProvider<List<CoachSession>>((ref) {
  return ref.watch(memberCoachRepositoryProvider).fetchSessions();
}, name: 'coachSessions');

/// The member↔coach chat thread (oldest → newest). Auto-dispose ends
/// real-API polling as soon as the full-screen chat route is closed.
final coachChatProvider = StreamProvider.autoDispose<List<CoachMessage>>((ref) {
  return ref.watch(memberCoachRepositoryProvider).watchChat();
});

/// Unread coach-sent message count for the entry badge.
final coachUnreadProvider = FutureProvider<int>((ref) {
  return ref.watch(memberCoachRepositoryProvider).unreadCount();
});

/// 트레이너가 나에게 보낸 담당 요청. 수락·거절 뒤에는 invalidate 한다. (#919)
///
/// 앱 어디서든 뜨는 담당 요청 창(`CoachInvitePrompter`, #1801)이 이 값을 듣는다.
/// 실시간 푸시가 아직 없어(#474) 알림 배지와 같은 규칙으로 받는다 — 듣기 시작할 때
/// (앱을 켤 때)와 앱으로 돌아올 때 바로, 켜져 있는 동안 15초마다. 데모에는 따라갈
/// 서버가 없어 한 번만 받는다.
///
/// 듣는 곳(회원 셸)이 사라지면 폴링도 멈추도록 autoDispose 다. invalidate 하면
/// 스트림이 새로 시작되며 곧바로 다시 받는다.
final coachInvitesProvider = StreamProvider.autoDispose<List<CoachInvite>>((
  ref,
) {
  final MemberCoachRepository repository = ref.watch(
    memberCoachRepositoryProvider,
  );
  if (ref.watch(appConfigProvider).useMockApi) {
    return Stream<List<CoachInvite>>.fromFuture(repository.fetchInvites());
  }
  return activePollingStream<List<CoachInvite>>(
    load: repository.fetchInvites,
    interval: const Duration(seconds: 15),
  );
}, name: 'coachInvites');

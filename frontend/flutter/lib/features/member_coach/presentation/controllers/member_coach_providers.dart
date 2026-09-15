import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
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
    return MockMemberCoachRepository(
      exercise: exercise is MockExerciseRepository ? exercise : null,
      // 루틴 완료(추천·배정) 적립도 같은 원장이다(#1786).
      points: ref.watch(demoPointsLedgerProvider),
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
final coachInvitesProvider = FutureProvider<List<CoachInvite>>((ref) {
  return ref.watch(memberCoachRepositoryProvider).fetchInvites();
}, name: 'coachInvites');

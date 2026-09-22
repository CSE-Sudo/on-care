import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/points/demo_emote_pass.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/active_polling_stream.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_emote_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_emote_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/emote_repository.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';

/// Selects the real Dio-backed coach repository against the FastAPI backend,
/// or the in-memory demo for `USE_MOCK_API=true`. One mock instance per
/// provider lifetime so demo chat sends persist for the session.
final Provider<MemberCoachRepository> memberCoachRepositoryProvider =
    Provider<MemberCoachRepository>((ref) {
      if (ref.watch(appConfigProvider).useMockApi) {
        // 데모에는 서버가 없다. 실서버는 루틴 완료를 받으면 회원 운동 기록 한 건을
        // 함께 만들고 취소하면 지우는데(#1131), 그 일을 이 대역이 대신하도록 운동
        // 저장소를 건네준다 — 그러지 않으면 체크해도 `운동 현황` 이 꿈쩍하지 않는다.
        // 파생 기록(출처 `assigned_routine`)을 만들고 지우는 일은 목업 저장소만
        // 할 수 있다. 테스트가 운동 저장소를 다른 대역으로 갈아 끼우면 루틴 상태만
        // 바뀌는 예전 동작으로 떨어진다 — 화면이 죽는 것보다 낫다.
        final ExerciseRepository exercise = ref.watch(
          exerciseRepositoryProvider,
        );
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

/// 오늘의 추천 개인운동 — 오늘 걸려 있는 목록과 오늘 완료. (#2161)
///
/// 매일 미완료로 다시 시작하는 목록이다. 날이 바뀌면 앱이 돌아올 때 다시 읽는다
/// (셸의 `_refreshMemberData`).
final coachRoutinesProvider = FutureProvider<List<CoachRoutine>>((ref) {
  return ref.watch(memberCoachRepositoryProvider).fetchRoutines();
});

/// 지난 날짜의 추천 개인운동 — 그날 걸려 있던 목록과 그날 완료. (#2161)
///
/// 읽기 전용이다. 키는 날짜만 남긴 값이라 같은 날을 시각만 달리 불러도 한 번만
/// 읽는다 — 부르는 쪽이 [dateOnly] 로 넘긴다.
final coachRoutinesOnDayProvider =
    FutureProvider.family<List<CoachRoutine>, DateTime>((ref, DateTime day) {
      return ref.watch(memberCoachRepositoryProvider).fetchRoutinesOn(day);
    }, name: 'coachRoutinesOnDay');

/// 날짜만 남긴다 — [coachRoutinesOnDayProvider] 의 키.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 추천 개인운동의 체크가 바뀌면 함께 달라지는 것을 다시 읽는다. (#2161)
///
/// 오늘 목록, 지난 날짜 목록, 그리고 **운동 AI 맞춤 조언**. 조언은 추천 개인운동
/// 중 무엇을 했는지를 읽고 말하므로(#2162), 체크한 뒤에도 옛 조언이 남으면
/// "다음 운동" 이 방금 끝낸 운동을 가리킨다.
void refreshCoachRoutines(WidgetRef ref) {
  ref
    ..invalidate(coachRoutinesProvider)
    ..invalidate(coachRoutinesOnDayProvider)
    ..invalidate(exerciseAdviceProvider);
}

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

/// 폴링이 주는 최신 쪽 **앞**에 붙는, 손으로 더 받아 온 옛 메시지들. (#1943)
///
/// 서버는 한 번에 최신 [chatPageSize] 건만 주고 그 앞은 커서로 준다. 앱은
/// 커서 없이 부르기만 해서 51번째 이전 메시지는 위로 올려도 나오지 않았다.
///
/// 폴링 쪽(`coachChatProvider`)과 따로 두는 이유는, 15초마다 새로 받는 최신
/// 쪽이 손으로 받아 둔 옛 쪽을 지우면 안 되기 때문이다. 화면이 둘을 합쳐 그린다.
class CoachChatHistory extends AutoDisposeNotifier<CoachChatHistoryState> {
  @override
  CoachChatHistoryState build() {
    // 대화 자체가 새로 열리면(담당이 바뀌면) 받아 둔 옛 쪽도 버린다.
    ref.watch(memberCoachRepositoryProvider);
    return const CoachChatHistoryState();
  }

  /// [oldest] 앞의 한 쪽을 더 받는다. [oldest] 는 지금 화면에 있는 가장 오래된
  /// 메시지다 — 화면이 합쳐 그리므로 커서는 화면이 안다.
  Future<void> loadOlder(CoachMessage oldest) async {
    if (state.loading || state.exhausted) return;
    state = state.copyWith(loading: true);
    try {
      final List<CoachMessage> older = await ref
          .read(memberCoachRepositoryProvider)
          .fetchChat(before: oldest);
      state = CoachChatHistoryState(
        messages: <CoachMessage>[...older, ...state.messages],
        // 한 쪽이 다 차지 않았으면 그 앞에는 없다.
        exhausted: older.length < chatPageSize,
      );
    } on Object {
      // 못 받아 왔다고 받아 둔 것을 버리지 않는다 — 다시 누르면 된다.
      state = state.copyWith(loading: false);
    }
  }
}

/// [CoachChatHistory] 가 들고 있는 것.
class CoachChatHistoryState {
  const CoachChatHistoryState({
    this.messages = const <CoachMessage>[],
    this.loading = false,
    this.exhausted = false,
  });

  /// 손으로 더 받아 온 옛 메시지(오래된→최신).
  final List<CoachMessage> messages;

  /// 지금 한 쪽을 받고 있는가.
  final bool loading;

  /// 더 받을 것이 없다 — 마지막 쪽이 다 차지 않았다.
  final bool exhausted;

  CoachChatHistoryState copyWith({bool? loading}) => CoachChatHistoryState(
    messages: messages,
    loading: loading ?? this.loading,
    exhausted: exhausted,
  );
}

final coachChatHistoryProvider =
    NotifierProvider.autoDispose<CoachChatHistory, CoachChatHistoryState>(
      CoachChatHistory.new,
      name: 'coachChatHistory',
    );

/// 헤더 배지에 뜨는 트레이너 대화 미읽음 수.
///
/// 아래 [coachInvitesProvider] 와 **같은 규칙**으로 받는다 — 앱을 켤 때와 돌아올
/// 때 바로, 켜져 있는 동안 15초마다. 예전에는 한 번만 조회해서, 앱을 켜 둔 채
/// 트레이너가 메시지를 보내도 배지가 켤 때의 수(대개 0)로 남았다(#1929).
/// 데모에는 따라갈 서버가 없어 한 번만 받는다.
final coachUnreadProvider = StreamProvider.autoDispose<int>((ref) {
  final MemberCoachRepository repository = ref.watch(
    memberCoachRepositoryProvider,
  );
  if (ref.watch(appConfigProvider).useMockApi) {
    return Stream<int>.fromFuture(repository.unreadCount());
  }
  return activePollingStream<int>(
    load: repository.unreadCount,
    interval: const Duration(seconds: 15),
  );
}, name: 'coachUnread');

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

/// 채팅 이모티콘 이용권 저장소. (#2020)
final emoteRepositoryProvider = Provider<EmoteRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return MockEmoteRepository(ref.watch(demoEmotePassBookProvider));
  }
  return DioEmoteRepository(ref.watch(dioProvider));
});

/// 이용권 상태 — 고르는 창이 열릴 때 한 번 읽는다. 남은 시간은 창이 스스로 센다.
final emoteStateProvider = FutureProvider.autoDispose<EmoteState>((ref) {
  return ref.watch(emoteRepositoryProvider).fetchState();
});

/// 알림에서 선택한 요청을 전역 팝업이 먼저 연다. 창 생성은 prompter만 맡는다.
final selectedCoachInviteProvider = StateProvider<String?>((ref) => null);

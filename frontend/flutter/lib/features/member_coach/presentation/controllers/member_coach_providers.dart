import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_emote_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/active_polling_stream.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/routine_session_log.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_emote_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_emote_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/coach_chat_thread.dart';
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
        // 기록이 사는 곳을 건네준다 — 그러지 않으면 체크해도 `운동 현황` 이 꿈쩍하지
        // 않는다. 앱에서는 운동 탭·홈·챌린지가 읽는 로컬 목업 API(drift)다(#2662).
        // 테스트가 운동 저장소를 기록 자리를 갖춘 대역으로 갈아 끼우면 그 대역에 남긴다.
        // 둘 다 없으면 루틴 상태만 바뀌는 예전 동작으로 떨어진다 — 화면이 죽는
        // 것보다 낫다.
        //
        // 완료할 때 찾는다 — 여기서 watch 하면 코치 화면만 그리는 데도 Dio 와
        // 로컬 DB 가 서야 한다.
        final GymRepository gym = ref.watch(gymRepositoryProvider);
        return MockMemberCoachRepository(
          exercise: _LazyRoutineSessionLog(() {
            final ExerciseRepository exercise = ref.read(
              exerciseRepositoryProvider,
            );
            return switch (exercise) {
              final RoutineSessionLog log => log,
              _ => LocalApiInterceptor.of(ref.read(dioProvider)),
            };
          }),
          // 루틴 완료(추천·배정) 적립도 같은 원장이다(#1786).
          points: ref.watch(demoPointsLedgerProvider),
          // 담당 트레이너 연결은 헬스장 저장소가 들고 있다 — 트레이너를 끊으면
          // 담당 코치도 없어야 헤더가 AI 챗봇 입구로 바뀐다(#1840, #1865).
          linked: gym is MockGymRepository ? () => gym.hasTrainer : null,
          // 끊긴 뒤 온 담당 요청을 수락하면 같은 곳에 다시 잇는다(#2659).
          relink: gym is MockGymRepository ? gym.linkTrainer : null,
        );
      }
      return DioMemberCoachRepository(ref.watch(dioProvider));
    }, name: 'memberCoachRepository');

/// The member's assigned coach (null when none).
final memberCoachProvider = FutureProvider<MemberCoach?>((ref) {
  return ref.watch(memberCoachRepositoryProvider).fetchCoach();
});

/// 담당 코치에 딸린 화면 묶음 — 배정 운동·PT 일정·대화·미읽음. (#1865, #2843)
///
/// 담당이 끊기면 이 묶음도 함께 비워야 한다. 연결 해제(`confirmDisconnect`)와
/// 앱 복귀 재확인([recheckMemberCoach])이 같은 목록을 쓰도록 한곳에 둔다 —
/// 한쪽에만 항목을 더하면 다른 쪽에서 해제된 트레이너의 화면이 남는다.
/// `WidgetRef.invalidate`·`Ref.invalidate`·`ProviderContainer.invalidate` 를
/// 그대로 넘긴다.
void invalidateCoachBoundData(void Function(ProviderOrFamily) invalidate) {
  invalidate(coachRoutinesProvider);
  invalidate(coachSessionsProvider);
  invalidate(coachChatProvider);
  invalidate(coachUnreadProvider);
}

/// 담당 코치를 다시 읽고, 있던 담당이 사라졌으면 딸린 묶음도 비운다. (#2843)
///
/// [memberCoachProvider] 는 앱을 켤 때 한 번 읽은 값을 계속 쓴다. 앱을 떠난
/// 사이 트레이너가 웹에서 담당을 해제하면, 돌아와도 헤더가 트레이너 대화로 남고
/// 홈 트레이너 카드도 그대로였다. 셸이 앱 복귀·홈 재진입에서 부른다.
///
/// 다시 읽다 실패하면 아무것도 비우지 않는다 — 실패는 해제가 아니다. 위젯이
/// 사라져도 끝까지 돌도록 [ProviderContainer] 를 받는다.
Future<void> recheckMemberCoach(ProviderContainer container) async {
  final MemberCoach? before = container.read(memberCoachProvider).valueOrNull;
  container.invalidate(memberCoachProvider);
  final MemberCoach? after;
  try {
    after = await container.read(memberCoachProvider.future);
  } on Object {
    return;
  }
  if (before != null && after == null) {
    invalidateCoachBoundData(container.invalidate);
  }
}

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
/// 폴링 쪽(`coachChatProvider`)과 따로 두는 이유는, 몇 초마다 새로 받는 최신
/// 쪽이 손으로 받아 둔 옛 쪽을 지우면 안 되기 때문이다. 화면이 둘을
/// [mergeCoachThread] 로 합쳐 그린다.
///
/// **옛 쪽을 한 번 받은 뒤로는 폴링으로 받은 최신 쪽도 여기 모아 둔다**(#2640).
/// 폴링은 언제나 최신 50건만 주므로, 옛 쪽을 m[k] 앞까지 받아 둔 채 새 메시지가
/// 오면 최신 쪽이 m[k+1..] 로 밀려 경계의 m[k] 가 어느 쪽에도 없게 된다. 받은
/// 쪽을 모두 id 로 합쳐 들고 있으면 폴링끼리 서로 겹치는 한 틈이 생기지 않는다.
/// 폴링 사이에 한 쪽이 넘게 와서 겹침이 끊기면 그 틈을 커서로 다시 받아 메운다.
class CoachChatHistory extends AutoDisposeNotifier<CoachChatHistoryState> {
  @override
  CoachChatHistoryState build() {
    // 대화 자체가 새로 열리면(담당이 바뀌면) 받아 둔 옛 쪽도 버린다.
    ref.watch(memberCoachRepositoryProvider);
    ref.listen<AsyncValue<List<CoachMessage>>>(coachChatProvider, (
      AsyncValue<List<CoachMessage>>? previous,
      AsyncValue<List<CoachMessage>> next,
    ) {
      final List<CoachMessage>? latest = next.valueOrNull;
      if (latest != null) absorbLatest(latest);
    });
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
      // 처음 옛 쪽을 받는 때에는 지금 보이는 최신 쪽도 함께 붙잡아 둔다 — 그래야
      // 다음 폴링이 앞으로 밀려도 경계가 남는다.
      final List<CoachMessage> latest =
          ref.read(coachChatProvider).valueOrNull ?? const <CoachMessage>[];
      state = CoachChatHistoryState(
        messages: mergeCoachThread(
          older,
          mergeCoachThread(state.messages, latest),
        ),
        // 한 쪽이 다 차지 않았으면 그 앞에는 없다.
        exhausted: older.length < chatPageSize,
      );
    } on Object {
      // 못 받아 왔다고 받아 둔 것을 버리지 않는다 — 다시 누르면 된다.
      state = state.copyWith(loading: false);
    }
  }

  /// 폴링이 준 최신 쪽 [latest] 를 받아 둔 것에 합친다. (#2640)
  ///
  /// 옛 쪽을 받기 전에는 아무것도 하지 않는다 — 그때는 최신 쪽만으로 온전하다.
  void absorbLatest(List<CoachMessage> latest) {
    if (state.messages.isEmpty || latest.isEmpty) return;
    final Set<String> known = <String>{
      for (final CoachMessage m in state.messages) m.id,
    };
    final bool overlaps = latest.any((CoachMessage m) => known.contains(m.id));
    state = state.copyWith(messages: mergeCoachThread(state.messages, latest));
    // 겹치는 것이 하나도 없고 최신 쪽이 꽉 찼다면 그 사이에 받지 못한 것이
    // 있을 수 있다. 덜 찼다면 최신 쪽이 곧 대화 전체의 끝부분이라 틈이 없다.
    if (!overlaps && latest.length >= chatPageSize) {
      unawaited(_fillGap(latest.first, known));
    }
  }

  /// [from] 앞을 거슬러 받아, 이미 가진 [known] 에 닿을 때까지 채운다.
  Future<void> _fillGap(CoachMessage from, Set<String> known) async {
    CoachMessage cursor = from;
    for (int i = 0; i < maxGapFillPages; i++) {
      final List<CoachMessage> page;
      try {
        page = await ref
            .read(memberCoachRepositoryProvider)
            .fetchChat(before: cursor);
      } on Object {
        // 채우지 못했다고 받아 둔 것을 버리지 않는다. 다음 폴링이 다시 본다.
        return;
      }
      if (page.isEmpty) return;
      state = state.copyWith(messages: mergeCoachThread(state.messages, page));
      if (page.any((CoachMessage m) => known.contains(m.id)) ||
          page.length < chatPageSize) {
        return;
      }
      cursor = page.first;
    }
  }
}

/// 틈을 메우러 거슬러 받을 쪽 수의 상한 — 커서가 앞으로 나가지 않는 서버를
/// 만나도 멈추게 한다.
const int maxGapFillPages = 20;

/// [CoachChatHistory] 가 들고 있는 것.
class CoachChatHistoryState {
  const CoachChatHistoryState({
    this.messages = const <CoachMessage>[],
    this.loading = false,
    this.exhausted = false,
  });

  /// 받아 둔 메시지(오래된→최신). 손으로 더 받아 온 옛 쪽과, 그 뒤로 폴링이
  /// 준 최신 쪽이 id 로 합쳐져 있다.
  final List<CoachMessage> messages;

  /// 지금 한 쪽을 받고 있는가.
  final bool loading;

  /// 더 받을 것이 없다 — 마지막 쪽이 다 차지 않았다.
  final bool exhausted;

  CoachChatHistoryState copyWith({
    List<CoachMessage>? messages,
    bool? loading,
  }) => CoachChatHistoryState(
    messages: messages ?? this.messages,
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
    return MockEmoteRepository(ref.watch(demoEmoteBookProvider));
  }
  return DioEmoteRepository(ref.watch(dioProvider));
});

/// 이용권 상태 — 고르는 창이 열릴 때 한 번 읽는다. 남은 시간은 창이 스스로 센다.
final emoteStateProvider = FutureProvider.autoDispose<EmoteState>((ref) {
  return ref.watch(emoteRepositoryProvider).fetchState();
});

/// 알림에서 선택한 요청을 전역 팝업이 먼저 연다. 창 생성은 prompter만 맡는다.
final selectedCoachInviteProvider = StateProvider<String?>((ref) => null);

/// 루틴 완료 기록을 남길 곳을 **부를 때** 찾는다. (#2662)
///
/// 찾지 못하면(목업 API 가 없는 테스트) 기록 없이 루틴 상태만 바뀐다 — id 가
/// 없는 세션을 돌려주므로 코치 저장소가 되돌릴 기록으로 적어 두지 않는다.
class _LazyRoutineSessionLog implements RoutineSessionLog {
  _LazyRoutineSessionLog(this._resolve);

  final RoutineSessionLog? Function() _resolve;

  @override
  Future<ExerciseSession> addAssignedRoutineSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    required String routineId,
    required String name,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? durationSeconds,
  }) async {
    final RoutineSessionLog? log = _resolve();
    if (log == null) {
      return ExerciseSession(
        dayLabel: '',
        type: type,
        minutes: minutes,
        calories: calories,
      );
    }
    return log.addAssignedRoutineSession(
      type: type,
      minutes: minutes,
      calories: calories,
      date: date,
      routineId: routineId,
      name: name,
      intensity: intensity,
      durationSeconds: durationSeconds,
    );
  }

  @override
  Future<void> removeAssignedRoutineSession(String id) async =>
      _resolve()?.removeAssignedRoutineSession(id);

  @override
  Future<List<ExerciseSession>> assignedRoutineSessions() async =>
      await _resolve()?.assignedRoutineSessions() ?? const <ExerciseSession>[];
}

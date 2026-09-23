import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// The member's view of their assigned coach: profile, received routines,
/// and the shared chat thread (the same thread the trainer app writes to).
///
/// Two implementations sit behind this contract (selected by
/// [memberCoachRepositoryProvider] via `AppConfig.useMockApi`):
///  * `MockMemberCoachRepository` — demo / `USE_MOCK_API=true`;
///  * `DioMemberCoachRepository` — the real FastAPI backend.
/// 대화 한 쪽의 크기. 서버 기본값(`GET /me/coach/chat` 의 `limit`)과 같다 —
/// 받아 온 건수가 이 값과 같으면 그 앞에 더 있을 수 있다(#1943).
const int chatPageSize = 50;

abstract interface class MemberCoachRepository {
  /// The assigned coach, or `null` when the member has none yet (404).
  Future<MemberCoach?> fetchCoach();

  /// 오늘의 추천 개인운동 — 오늘 걸려 있는 목록과 오늘 완료. (#2161)
  ///
  /// 추천 개인운동은 매일 새로 체크하는 목록이다. 트레이너가 바꾸기 전까지 같은
  /// 목록이 날마다 미완료로 다시 시작하므로 `completed` 는 **오늘** 했는가다.
  Future<List<CoachRoutine>> fetchRoutines();

  /// [day] 에 걸려 있던 목록과 그날 완료 — 지난 날짜 화면이 읽는다. (#2161)
  ///
  /// 읽기 전용이다. 완료·해제는 오늘에만 한다([completeRoutine]). 아직 오지 않은
  /// 날은 오류다.
  Future<List<CoachRoutine>> fetchRoutinesOn(DateTime day);

  /// 오늘의 운동 기록으로 완료한다 — 배정 하나당 하루 한 번. (#2161)
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    required int minutes,
    String intensity = 'moderate',
  });

  /// 완료 표시를 되돌린다 — 그 배정으로 남은 운동 기록을 지운다. (#1131)
  ///
  /// 체크를 잘못 눌렀을 때 되돌릴 방법이 없으면, 하지 않은 운동이 주간 시간·
  /// 칼로리에 그대로 남는다. 배정 자체는 지우지 않는다 — 되돌리는 것은 `수행`
  /// 이지 `할 일` 이 아니다. 완료가 아닌 배정에 불러도 아무 일도 일어나지 않는다.
  Future<CoachRoutine> uncompleteRoutine(String routineId);

  /// 개인 운동을 취소한다. **담당 트레이너가 없을 때만** 서버가 받아 준다 —
  /// 담당이 배정한 것을 회원이 조용히 없애면 다음 상담에서 둘이 서로 다른
  /// 기록을 본다. (#1020)
  ///
  /// 이미 수행한 기록은 남는다. 지우는 것은 배정이지 한 일이 아니다.
  Future<void> deleteRoutine(String routineId);

  /// PT sessions the coach booked. The trainer owns the schedule — the
  /// member reads it only. (#490)
  Future<List<CoachSession>> fetchSessions();

  /// The chat thread (oldest → newest).
  /// 담당 트레이너와의 대화(오래된→최신).
  ///
  /// 서버는 한 번에 최신 [chatPageSize] 건만 준다. 그 앞을 더 받으려면 지금까지
  /// 받은 것 중 **가장 오래된 메시지**를 커서로 넘긴다(#1943) — 전에는 앱이
  /// 커서 없이 부르기만 해서 51번째 이전 메시지는 위로 올려도 나오지 않았다.
  Future<List<CoachMessage>> fetchChat({CoachMessage? before});

  /// Watches the chat while its screen is active. Real API implementations
  /// poll the shared thread; demo implementations emit their in-memory state.
  Stream<List<CoachMessage>> watchChat();

  /// Sends a message to the coach. No-ops on blank text.
  /// 글 또는 이모티콘 하나를 보낸다. [emoteId] 를 주면 이모티콘 메시지다(#2020) —
  /// 이용권이 없으면 서버가 막는다.
  Future<void> sendMessage(String text, {String? emoteId});

  /// Marks the thread read up to the newest coach message.
  Future<void> markRead();

  /// Unread coach-sent message count for the entry badge.
  Future<int> unreadCount();

  /// 트레이너가 나에게 보낸, 아직 답하지 않은 담당 요청. (#919)
  Future<List<CoachInvite>> fetchInvites();

  /// 요청을 수락한다 — 담당 관계는 이 호출로 생긴다.
  /// 담당 요청을 수락한다 — 담당 링크가 여기서 생긴다.
  ///
  /// [dataSharingConsent] 없이는 서버가 400 으로 막는다. 수락하는 순간
  /// 트레이너가 회원의 식단·운동·신체 정보를 읽기 때문이다. (#1022)
  Future<void> acceptInvite(
    String inviteId, {
    required bool dataSharingConsent,
  });

  /// 요청을 거절한다. 담당은 생기지 않는다.
  Future<void> rejectInvite(String inviteId);
}

import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// The member's view of their assigned coach: profile, received routines,
/// and the shared chat thread (the same thread the trainer app writes to).
///
/// Two implementations sit behind this contract (selected by
/// [memberCoachRepositoryProvider] via `AppConfig.useMockApi`):
///  * `MockMemberCoachRepository` — demo / `USE_MOCK_API=true`;
///  * `DioMemberCoachRepository` — the real FastAPI backend.
abstract interface class MemberCoachRepository {
  /// The assigned coach, or `null` when the member has none yet (404).
  Future<MemberCoach?> fetchCoach();

  /// Routines the coach has assigned (newest first).
  Future<List<CoachRoutine>> fetchRoutines();

  /// Records an assigned routine once in the member's exercise history.
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
  Future<List<CoachMessage>> fetchChat();

  /// Watches the chat while its screen is active. Real API implementations
  /// poll the shared thread; demo implementations emit their in-memory state.
  Stream<List<CoachMessage>> watchChat();

  /// Sends a message to the coach. No-ops on blank text.
  Future<void> sendMessage(String text);

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

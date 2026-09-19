/// One member's consultation request as the trainer sees it.
///
/// The member app writes these (`POST /consultations`); until a trainer
/// accepts one there is no trainer↔member link, so this is the only place
/// a real roster can start. Accepting is what creates the link — the demo
/// roster comes from seed data instead.
class ConsultationRequest {
  /// Creates a request card.
  const ConsultationRequest({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.goalCode,
    required this.purposeCode,
    required this.preferredDate,
    required this.preferredTimeCode,
    required this.status,
    this.slotStartsAt,
    this.slotDurationMinutes,
    this.message,
    this.purposeDetail,
    this.decisionNote,
    this.createdAt,
  });

  /// Server id — the path segment for accept / reject.
  final String id;

  /// The requesting member's user id.
  final String memberId;

  /// Display name. Falls back to a placeholder when the account is gone.
  final String memberName;

  /// 운동 목표, already localized (체중 감량 …).
  /// 서버 enum 코드('weight_loss' …). 화면 문구는 [exerciseGoalLabels] 로 만든다.
  final String goalCode;

  /// 건강관리 목적, already localized (만성질환 관리 …).
  /// 서버 enum 코드('chronic' …). 화면 문구는 [healthPurposeLabels] 로 만든다.
  final String purposeCode;

  /// Free-text detail the member added to 건강관리 목적, if any.
  final String? purposeDetail;

  /// Requested date (`YYYY-MM-DD` parsed).
  final DateTime preferredDate;

  /// 서버 코드 — `flexible` 또는 `HH:MM` 정확한 시각(#1256). 과거
  /// morning/afternoon/evening 값도 남아 있을 수 있다. 화면 문구는
  /// [preferredTimeLabel] 로 만든다.
  final String preferredTimeCode;

  /// 회원이 고른 자리의 시작 시각과 길이. (#1873)
  ///
  /// 회원이 희망 시각을 적어 보내던 방식을 버리고 **트레이너가 열어 둔 자리**를
  /// 고르게 하면서 생겼다. 승인하면 이 자리가 그대로 첫 일정이 되므로, 카드는
  /// 이 값을 보여 줘야 트레이너가 무엇을 수락하는지 안다.
  ///
  /// 자리 선택 이전에 접수된 요청에는 없다 — 그때는 위 두 칸(희망 날짜·시각)이
  /// 회원이 적어 보낸 값이다.
  final DateTime? slotStartsAt;
  final int? slotDurationMinutes;

  /// The member's own note to the trainer.
  final String? message;

  /// `pending` | `accepted` | `rejected` | `cancelled` | `expired`.
  ///
  /// `expired` 는 시간 안에 확인하지 않아 자리가 풀린 요청이다(#1873) — 트레이너의
  /// 판단인 `rejected` 와 구분한다.
  final String status;

  /// Rejection reason, once decided.
  final String? decisionNote;

  /// 요청이 접수된 시각. 인박스가 이어 받을 때 커서로 쓴다(#980).
  ///
  /// 목록 정렬키라 서버 응답에는 항상 실려 오지만, 데모 인박스는 메모리 목록이라
  /// 값이 없다 — 그쪽은 이어 받을 것도 없다.
  final DateTime? createdAt;

  /// Whether this request is still waiting on a decision.
  bool get isPending => status == 'pending';
}

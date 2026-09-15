/// 회원이 잡아 둔 예약 한 건. `GET /reservations/me`. (#502)
///
/// 예약 패널이 "이 자리는 내가 잡았다" 를 표시하고 취소를 걸기 위해 필요하다.
/// 슬롯 목록(`TrainerSlot`)만으로는 잔여 자리만 알 뿐, 그중 어느 것이 내 것인지
/// 알 수 없다.
library;

class MyReservation {
  const MyReservation({
    required this.id,
    required this.slotId,
    required this.trainerId,
    required this.startsAt,
    required this.cancellable,
    this.sessionType = '1:1 PT',
    this.pointsCost = 0,
    this.pointsRefundable = false,
  });

  final String id;
  final String slotId;
  final String trainerId;
  final DateTime startsAt;

  /// 지금 취소할 수 있는가.
  ///
  /// **서버 판단을 그대로 쓴다.** 기기 시계로 다시 계산하면 시각이 어긋난
  /// 기기에서 버튼은 눌리는데 서버가 409 를 주는 상태가 된다.
  final bool cancellable;

  /// 예약한 자리의 종류 — `1:1 PT`·`상담`·`체험`(#1790).
  final String sessionType;

  /// 이 예약에 쓴 포인트(체험 예약만 500).
  final int pointsCost;

  /// 지금 취소하면 포인트를 돌려받는가 — 체험 예약을 시작 24시간 전까지 취소할
  /// 때만 true. [cancellable] 과 같은 이유로 서버 판단을 그대로 쓴다.
  final bool pointsRefundable;

  /// 포인트 체험 예약인가.
  bool get isPointsTrial => sessionType == '체험';

  factory MyReservation.fromJson(Map<String, Object?> json) => MyReservation(
    id: json['id']! as String,
    slotId: json['slot_id']! as String,
    trainerId: json['trainer_id']! as String,
    startsAt: DateTime.parse(json['starts_at']! as String).toLocal(),
    cancellable: (json['cancellable'] as bool?) ?? false,
    sessionType: (json['session_type'] as String?) ?? '1:1 PT',
    pointsCost: (json['points_cost'] as num?)?.toInt() ?? 0,
    pointsRefundable: (json['points_refundable'] as bool?) ?? false,
  );
}

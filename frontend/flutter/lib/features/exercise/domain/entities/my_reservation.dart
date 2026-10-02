/// 회원이 잡아 둔 예약 한 건. `GET /reservations/me`. (#502)
///
/// 예약 패널이 "이 자리는 내가 잡았다" 를 표시하고 취소를 걸기 위해 필요하다.
/// 슬롯 목록(`TrainerSlot`)만으로는 잔여 자리만 알 뿐, 그중 어느 것이 내 것인지
/// 알 수 없다.
library;

import 'package:oncare/core/utils/clock.dart';

class MyReservation {
  const MyReservation({
    required this.id,
    required this.slotId,
    required this.trainerId,
    required this.startsAt,
    required this.cancellable,
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

  factory MyReservation.fromJson(Map<String, Object?> json) => MyReservation(
    id: json['id']! as String,
    slotId: json['slot_id']! as String,
    trainerId: json['trainer_id']! as String,
    // KST 벽시계로 읽는다 — 다음 PT 계산이 KST 인 nowKst 와 견준다(#2876).
    startsAt: toKst(DateTime.parse(json['starts_at']! as String)),
    cancellable: (json['cancellable'] as bool?) ?? false,
  );
}

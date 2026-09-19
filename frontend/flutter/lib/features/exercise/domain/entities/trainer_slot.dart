/// One bookable time on a trainer's calendar.
///
/// Slots belong to a trainer, not to a gym: a gym employs several trainers and
/// each keeps their own hours, so the same gym shows different times depending
/// on who you are booking.
///
/// 자리는 언제나 한 사람 몫이다 — 1:1 PT 든 상담이든 여럿이 함께 듣지 않는다.
/// 그래서 정원과 잔여 인원 개념이 없고, 슬롯은 **비었거나 예약된** 두 상태뿐이다
/// (#1072).
class TrainerSlot {
  const TrainerSlot({
    required this.id,
    required this.trainerId,
    required this.startsAt,
    required this.booked,
    required this.sessionType,
    this.durationMinutes = 60,
  });

  final String id;
  final String trainerId;

  /// When the session starts. Rendered with the device locale rather than a
  /// fixed "오늘/내일" string, so the label stays true as days pass.
  final DateTime startsAt;

  /// 이미 예약된 자리인가. 예약된 자리도 숨기지 않고 비활성으로 남겨, 그
  /// 트레이너의 하루가 "비어 있음" 이 아니라 "찼음" 으로 읽히게 한다.
  final bool booked;

  /// `'1:1 PT'` 또는 `'상담'` — 트레이너 앱 스케줄 탭의 세션 종류와 같은
  /// 계약값이다. 회원이 이 시간을 예약하면 만들어지는 일정이 이 종류를
  /// 그대로 물려받는다.
  final String sessionType;
  final int durationMinutes;

  TrainerSlot copyWith({bool? booked}) {
    return TrainerSlot(
      id: id,
      trainerId: trainerId,
      startsAt: startsAt,
      booked: booked ?? this.booked,
      sessionType: sessionType,
      durationMinutes: durationMinutes,
    );
  }
}

/// 서버 `TrainerSlotOut` → 엔티티. 헬스장 탭의 예약 가능 시간 목록과 상담 신청
/// 폼이 같은 모양의 응답을 읽어 한곳에 둔다. (#1873)
TrainerSlot trainerSlotFromJson(Map<String, Object?> j) => TrainerSlot(
  id: j['id']! as String,
  trainerId: (j['trainer_id'] as String?) ?? '',
  startsAt: DateTime.parse(j['starts_at']! as String).toLocal(),
  // 서버는 아직 좌석 수로 자리를 센다. 한 사람 몫뿐인 자리라 남은 좌석이
  // 0인지만 의미가 있으므로 여기서 예약 여부로 접고, 좌석 수는 앱 안으로
  // 들이지 않는다(#1072).
  booked: ((j['remaining'] as num?) ?? 0).toInt() <= 0,
  sessionType: (j['session_type'] as String?) ?? '1:1 PT',
  durationMinutes: (j['duration_minutes'] as num?)?.toInt() ?? 60,
);

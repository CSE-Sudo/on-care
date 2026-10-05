import 'package:oncare_core/clock.dart';

/// A reservable time exposed by a trainer — 1:1 PT or 상담.
///
/// 자리는 언제나 한 사람 몫이다 — 1:1 PT 든 상담이든 여럿이 함께 듣지 않는다.
/// 그래서 정원과 잔여 인원 개념이 없고, 자리는 **비었거나 예약된** 두 상태뿐이다
/// (#1072).
class ReservationSlot {
  const ReservationSlot({
    required this.id,
    required this.startsAt,
    this.durationMinutes = 60,
    required this.booked,
    required this.isClosed,
    required this.sessionType,
    this.bookedByName,
    this.overlapped = false,
  });

  final String id;
  final DateTime startsAt;
  final int durationMinutes;

  /// 회원이 이미 잡아 간 자리인가.
  final bool booked;

  final bool isClosed;

  /// `SessionType.personalTraining`(`1:1 PT`) 또는 `SessionType.consultation`
  /// (`상담`) — 스케줄 탭의 세션 종류와 같은 계약값이다(#1083).
  final String sessionType;

  /// 이 자리를 잡은 회원 이름. [booked] 인 트레이너용 슬롯에서만 채워진다
  /// (#1394) — 서버가 트레이너 목록에서만 이 값을 내려준다.
  final String? bookedByName;

  /// 자리를 연 뒤 트레이너가 같은 시간에 다른 일정을 잡아, 회원이 고를 수 없는
  /// 자리인가(#2761). 회원 앱에는 마감으로 보인다. 자리를 닫지 않은 상태라
  /// 일정을 취소·이동하면 저절로 다시 빈 자리가 된다.
  final bool overlapped;

  /// 아직 비어 있어 회원이 잡을 수 있는 자리인가.
  bool get open => !isClosed && !booked && !overlapped;

  factory ReservationSlot.fromJson(Map<String, dynamic> json) {
    return ReservationSlot(
      id: json['id'] as String,
      // 서버 순간을 KST 벽시계로 읽는다 — `toLocal()` 은 브라우저 시간대라
      // KST 가 아닌 기기에서 슬롯 창만 다른 시각을 그렸다(#2759).
      startsAt: toKst(DateTime.parse(json['starts_at'] as String)),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
      // 서버는 아직 좌석 수로 자리를 센다. 한 사람 몫뿐인 자리라 남은 좌석이
      // 0인지만 의미가 있으므로 여기서 예약 여부로 접는다(#1072).
      booked: ((json['remaining'] as num?) ?? 0).toInt() <= 0,
      isClosed: json['is_closed'] as bool? ?? false,
      sessionType: json['session_type'] as String? ?? '1:1 PT',
      bookedByName: json['booked_by_name'] as String?,
      overlapped: json['overlapped'] as bool? ?? false,
    );
  }
}

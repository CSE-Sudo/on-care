import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// 다음 PT — 트레이너가 잡아 준 일정과 회원이 잡은 예약 중 **지금 이후** 가장
/// 이른 것. 없으면 null. (#1021, #1137, #2636)
///
/// 예전에는 트레이너 일정을 날짜만 오늘과 견줘, 오늘 10시에 끝난 PT 가 오후에도
/// `다음 PT · 오늘 오전 10:00` 으로 남고 내일 일정을 가렸다. 시각까지 [now] 와
/// 견준다.
///
/// * 트레이너 일정: 예정(`isUpcoming`)이고 날짜가 있어야 한다. 시각(`HH:MM`)이
///   있으면 그 시각이 [now] 이후여야 하고, 시각이 비었거나 읽을 수 없으면
///   날짜가 오늘 이후면 남긴다 — 시각을 모르는 오늘 일정을 지났다고 단정하지
///   않는다.
/// * 예약: 취소할 수 있는(= 서버가 아직 오지 않았다고 본) 자리. 지남 여부는
///   **서버 판단을 그대로 쓴다.**
///
/// [now] 와 두 후보는 모두 KST 벽시계다 — 트레이너 일정은 KST 날짜·시각 그대로,
/// 예약 시각은 엔티티가 `toKst` 로 읽어 온다(#2876). 그래서 기기 타임존과
/// 상관없이 한 리스트에서 정렬해도 같은 기준이다.
DateTime? nextPtAt({
  required Iterable<CoachSession> sessions,
  required Iterable<MyReservation> reservations,
  required DateTime now,
}) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<DateTime> upcoming = <DateTime>[
    for (final CoachSession s in sessions)
      if (_sessionStart(s, now: now, today: today) case final DateTime at) at,
    for (final MyReservation r in reservations)
      if (r.cancellable) r.startsAt,
  ]..sort();
  return upcoming.isEmpty ? null : upcoming.first;
}

/// 다음 PT 후보로 남는 일정의 시작 시각. 후보가 아니면 null.
DateTime? _sessionStart(
  CoachSession s, {
  required DateTime now,
  required DateTime today,
}) {
  final DateTime? d = s.date;
  if (!s.isUpcoming || d == null) return null;
  final DateTime day = DateTime(d.year, d.month, d.day);
  final ({int hour, int minute})? time = parseSessionTime(s.time);
  if (time == null) {
    // 시각을 모르면 그날 자정으로 정렬한다 — 날짜가 오늘 이후면 남긴다.
    return day.isBefore(today) ? null : day;
  }
  final DateTime at = DateTime(
    day.year,
    day.month,
    day.day,
    time.hour,
    time.minute,
  );
  return at.isBefore(now) ? null : at;
}

/// `HH:MM` 을 읽는다. 비었거나 형식이 다르면 null.
({int hour, int minute})? parseSessionTime(String raw) {
  final List<String> parts = raw.trim().split(':');
  if (parts.length < 2) return null;
  final int? hour = int.tryParse(parts[0]);
  final int? minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return (hour: hour, minute: minute);
}

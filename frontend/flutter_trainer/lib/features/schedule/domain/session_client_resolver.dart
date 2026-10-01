import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';

/// 일정 카드에서 그 회원의 코칭 탭으로 갈 때 **어느 회원인지** 정한다. (#2864)
///
/// 이름은 표시 전용 값이다 — 같은 이름의 회원이 둘이면(동명이인, 성 없이
/// 이름만 같은 표시명) 이름으로 고른 첫 회원이 엉뚱한 사람일 수 있고, 그
/// 상태에서 프로그램을 보내면 다른 회원에게 배정된다. 그래서
///
///  * 일정에 회원 id 가 있으면 그 id 를 쓴다. 명단을 이미 읽었으면 그 id 가
///    명단에 있을 때만 쓴다(담당이 끊긴 회원의 코칭 탭으로 보내지 않는다).
///    명단을 아직 못 읽었으면([roster] 가 null) id 를 그대로 믿는다.
///  * id 가 없는 예전 일정만 이름으로 찾되, **정확히 한 명**이 일치할 때만
///    돌려준다. 0명이거나 2명 이상이면 null — 임의의 첫 회원을 고르지 않는다.
///
/// null 이면 화면이 회원 목록으로 보내고 회원을 골라 달라고 알린다.
String? resolveSessionClientId(
  ScheduleSession session,
  List<({String id, String name})>? roster,
) {
  final String? id = session.clientId;
  if (id != null && id.isNotEmpty) {
    if (roster == null) return id;
    return roster.any((c) => c.id == id) ? id : null;
  }
  return uniqueRosterIdByName(roster ?? const [], session.clientName);
}

/// [name] 과 같은 이름이 명단에 **정확히 하나**일 때만 그 회원 id. (#2864)
String? uniqueRosterIdByName(
  List<({String id, String name})> roster,
  String name,
) {
  if (name.trim().isEmpty) return null;
  String? found;
  for (final c in roster) {
    if (c.name != name) continue;
    if (found != null) return null; // 동명이인 — 고르지 않는다.
    found = c.id;
  }
  return found;
}

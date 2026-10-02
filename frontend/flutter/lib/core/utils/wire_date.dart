/// 서버 계약 형식(`YYYY-MM-DD`). (#1928)
///
/// 화면에는 로케일 형식으로 보여 주고, 나갈 때만 이 형식으로 바꾼다 — 사용자가
/// 형식을 맞출 일이 없어야 한다.
///
/// 예전에는 일정 추가 창에 있었는데, 일정 기능을 걷어내면서 그 값을 쓰는 식단
/// 쪽이 남아 공용 자리로 옮겼다.
String wireDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [wireDate] 의 역 — `YYYY-MM-DD` 를 시각 없는 날짜로 읽는다. 형식이 다르거나
/// 달력에 없는 날(`2026-02-30`)이면 null 이다. (#2881)
///
/// 주소창처럼 사람이 고칠 수 있는 곳에서 온 값을 읽는다 — `DateTime.parse` 는
/// 넘치는 날을 다음 달로 굴려 다른 날을 연다.
DateTime? parseWireDate(String? value) {
  if (value == null) return null;
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (m == null) return null;
  final int y = int.parse(m[1]!);
  final int mo = int.parse(m[2]!);
  final int d = int.parse(m[3]!);
  final DateTime parsed = DateTime(y, mo, d);
  if (parsed.year != y || parsed.month != mo || parsed.day != d) return null;
  return parsed;
}

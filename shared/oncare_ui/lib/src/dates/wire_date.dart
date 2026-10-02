/// 서버 계약 날짜 형식(`YYYY-MM-DD`)과 주 시작(월요일) 계산(#2908).
///
/// 날짜 키와 주 경계는 서버와 두 앱이 같은 날을 같은 주로 묶어야 하는 값이다.
/// 저장소·데모 원장·위젯마다 사본을 두면 한 곳만 다르게 고쳐지기 쉬워, 두 앱이
/// 여기 정의만 쓴다. 서버 쪽 짝은 `backend/app/core/week.py` 의 `monday_of` 다.
library;

final RegExp _wireDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// 서버 계약 형식(`YYYY-MM-DD`). (#1928)
///
/// 화면에는 로케일 형식으로 보여 주고, 나갈 때만 이 형식으로 바꾼다 — 사용자가
/// 형식을 맞출 일이 없어야 한다. 기기 저장소(drift)의 날짜 열도 같은 형식이다.
/// 시각 성분은 보지 않는다.
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
  final RegExpMatch? m = _wireDate.firstMatch(value);
  if (m == null) return null;
  final int y = int.parse(m[1]!);
  final int mo = int.parse(m[2]!);
  final int d = int.parse(m[3]!);
  final DateTime parsed = DateTime(y, mo, d);
  if (parsed.year != y || parsed.month != mo || parsed.day != d) return null;
  return parsed;
}

/// [d] 가 속한 주의 월요일 0시. (#2890, #2908)
///
/// 주 단위 조회 키·주간 화면의 첫 칸이다. **시각 성분을 버린다** —
/// `d.subtract(Duration(days: …))` 는 시각을 남기고, 서머타임이 있는 기기
/// 시간대에서는 정확히 24시간씩 빼 전날 23:00 으로 떨어질 수 있다. 결과를 날짜
/// 키로 견주는 곳에서 두 형태가 섞이면 같은 주가 다르게 비교된다. `DateTime`
/// 생성자는 넘친 일 수를 달력 기준으로 정규화하므로 월·연 경계도 그대로 넘는다.
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

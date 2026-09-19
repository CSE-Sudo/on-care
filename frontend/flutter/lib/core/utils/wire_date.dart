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

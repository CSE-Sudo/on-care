import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

// 달력 날 수는 두 앱이 함께 쓰는 시계 파일에 있다(#3250). 이 파일을 들이던
// 자리가 그대로 쓰도록 다시 내보낸다.
export 'package:oncare_core/clock.dart' show calendarDaysBetween;

/// Formats [d] as the `YYYY-MM-DD` string used by every date-keyed
/// drift column (seeding, schedule filters, reservation counts).
///
/// 정의는 두 앱이 함께 쓰는 `oncare_ui` 의 [wireDate] 하나뿐이다(#2908) —
/// 회원 앱·서버와 같은 날짜 키를 쓴다. 트레이너 웹 곳곳이 이 이름으로 부르므로
/// 이름만 남긴다.
const String Function(DateTime) ymd = wireDate;

/// 기간의 끝 날짜 표기 — 시작과 같은 해면 연도를 빼고 `MM-DD` 로 적는다.
///
/// 반복 일정의 `시작 - 종료일` 칸은 시간 칸과 한 줄을 반씩 나눠 쓴다. 두 날짜를
/// 모두 `YYYY-MM-DD` 로 적으면 그 폭에 들어가지 않아 종료일이 말줄임으로 잘렸다.
/// 해가 같으면 연도는 시작 날짜에서 이미 읽힌다. 해를 넘기는 기간은 연도를
/// 남긴다 — 그때 빼면 끝이 어느 해인지 헷갈린다.
String ymdRangeEnd(DateTime start, DateTime end) => start.year == end.year
    ? '${end.month.toString().padLeft(2, '0')}-'
          '${end.day.toString().padLeft(2, '0')}'
    : ymd(end);

/// Weekday names indexed by `DateTime.weekday - 1` (월 … 일), in the
/// current locale.
List<String> weekdayNames(AppLocalizations l) => <String>[
  l.weekdayMon,
  l.weekdayTue,
  l.weekdayWed,
  l.weekdayThu,
  l.weekdayFri,
  l.weekdaySat,
  l.weekdaySun,
];

/// Human date for page headers — `8/5 (화)` / `8/5 (Tue)`, with
/// `오늘`/`내일` prefixed when [relativeTo] (defaults to now) makes that
/// clearer.
///
/// 로케일을 인자로 받는다 — 순수 함수라 컨텍스트를 가질 수 없고, 호출부가
/// 어느 언어로 그리는지 명시하는 편이 읽기도 쉽다. (#501)
String dateLabel(AppLocalizations l, DateTime d, {DateTime? relativeTo}) {
  final base = relativeTo ?? nowKst();
  // 달력 날짜만 비교한다 — 로컬 자정끼리 빼면 서머타임이 시작하는 날은 두
  // 자정 사이가 23시간이라 `inDays` 가 0 이 되고, 내일이 `오늘`로 그려진다.
  // UTC 로 만들면 하루가 항상 24시간이라 날짜 차이만 남는다.
  final today = DateTime.utc(base.year, base.month, base.day);
  final target = DateTime.utc(d.year, d.month, d.day);
  final diff = target.difference(today).inDays;
  final prefix = switch (diff) {
    0 => l.dateToday,
    1 => l.dateTomorrow,
    -1 => l.dateYesterday,
    _ => '',
  };
  final date = l.dateMonthDayWeekday(
    d.month,
    d.day,
    weekdayNames(l)[d.weekday - 1],
  );
  return prefix.isEmpty ? date : l.datePrefixed(prefix, date);
}

/// 지난 날을 `오늘`·`어제`·`N일 전` 으로 — `Today`·`Yesterday`·`N days ago`.
///
/// 예전에는 서버가 이 문장을 한국어로 만들어 보냈다(#2300). 이제 서버는 날짜만
/// 주고 문장은 화면 언어로 여기서 만든다. 미래 날짜(시계 오차)는 `오늘` 로 접는다
/// — 서버 `relative_day_label` 과 같은 규칙이다.
String relativeDayLabel(AppLocalizations l, DateTime day, {DateTime? now}) {
  final int delta = calendarDaysBetween(day, now ?? nowKst());
  if (delta <= 0) return l.dateToday;
  if (delta == 1) return l.dateYesterday;
  return l.dateDaysAgo(delta);
}

/// 운동 기록 카드의 날짜 — `9/27 (오늘)`·`9/26 (어제)`·`9/25`.
///
/// 서버 `history_date_label` 과 같은 모양이다(#2300). 미래 날짜는 꼬리표 없이
/// 날짜만 적는다.
String historyDateLabel(AppLocalizations l, DateTime day, {DateTime? now}) {
  final String date = l.historyDate(day.month, day.day);
  final int delta = calendarDaysBetween(day, now ?? nowKst());
  return switch (delta) {
    0 => l.historyDateRelative(date, l.dateToday),
    1 => l.historyDateRelative(date, l.dateYesterday),
    _ => date,
  };
}

// 여러 식단 흐름이 함께 쓰는 날짜·글자 헬퍼.

part of '../diet_flows.dart';

/// Best-guess meal type for a new entry, based on the current time of day.
///
/// 21시 이후는 야식이다(#1988). 그전에는 그 자리가 간식이었는데, 밤늦게 먹은
/// 것과 낮의 간식이 한 칸에 섞여 코칭에서 갈라 보이지 않았다.
///
/// 간식에는 시간대를 주지 않는다. 어느 시간대를 떼어 주더라도 그 시간에 먹은
/// 끼니가 매번 간식으로 찍혀 회원이 고쳐야 한다 — 간식은 끼니 사이에 먹는
/// 것이지 특정 시각에 먹는 것이 아니다. 회원이 상세에서 직접 고른다.
String _currentMealType() {
  final int h = nowKst().hour;
  if (h < 11) return MealType.breakfast.name;
  if (h < 15) return MealType.lunch.name;
  if (h < 21) return MealType.dinner.name;
  return MealType.lateNight.name;
}

/// 오늘(KST)의 날짜. 시각은 버린다.
DateTime _todayKst() {
  final DateTime now = nowKst();
  return DateTime(now.year, now.month, now.day);
}

/// 시각을 버린 날짜. null 은 null 이다.
DateTime? _dayOf(DateTime? date) =>
    date == null ? null : DateTime(date.year, date.month, date.day);

/// 새 기록을 시작할 날(#2849). 넘겨받은 날이 없거나 아직 오지 않은 날이면
/// 오늘이다 — 앞날의 식사는 기록하지 않는다.
DateTime _startDate(DateTime? date) {
  final DateTime today = _todayKst();
  final DateTime? day = _dayOf(date);
  return day == null || day.isAfter(today) ? today : day;
}

/// 기록 날짜를 화면 언어로 — `2026년 9월 16일`.
String _recordDateLabel(BuildContext context, DateTime date) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date);

/// 역할 글자 + 색. 크기·굵기 숫자는 적지 않는다(#1690).
TextStyle _text(BuildContext context, TextStyle role, Color color) =>
    context.oncare.text(role).copyWith(color: color);

/// 그램 수치 한 줄. 소수 첫째 자리까지만, 정수는 콤마만 — 칼로리·나트륨 행과
/// 같은 서식이다. 당류와 탄·단·지가 이 함수를 같이 쓴다(#1564).
String _gramsText(double grams) => grams == grams.roundToDouble()
    ? NumberFormat('#,###').format(grams)
    : NumberFormat('#,##0.#').format(grams);

/// 입력 칸에 적는 g — 읽기용 [_gramsText] 와 달리 **자릿점을 넣지 않는다.**
///
/// 칸에 `1,640` 이 적히면 `double.tryParse` 가 null 을 돌려주어, 눈에는 보이는데
/// 읽을 수는 없는 값이 된다(숫자만 받는 입력기는 이미 적힌 글자를 걸러 주지
/// 않는다). 큰 1회 섭취량과 비례 환산으로 커진 값이 실제로 네 자리에 닿는다.
String _gramsFieldText(double grams) {
  final double rounded = (grams * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

/// 하단 내비·`+` 버튼 위에 뜨도록 루트 내비게이터에서 연다(#791). 탭 페이지는
/// 자기 내비게이터를 따로 갖고 있어, 그 안에서 열면 하단 바가 시트 위로 올라온다.
BuildContext _rootContext(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).context;

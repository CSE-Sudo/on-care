// 연속 기록 보호권·기록 그래프 경로(/me/streak-shields, /me/activity-calendar, /me/graph-color).

part of '../local_api_interceptor.dart';

extension _LocalApiStreakCalendar on LocalApiInterceptor {
  //
  // 규칙은 [DemoStreakShieldBook] 이 서버와 같게 들고 있다. 보호권이 지키는 것은
  // **기록 연속**이라, 그날 식단이나 운동 기록이 있는지를 이 인터셉터의 drift 로
  // 본다. 409 도 실서버처럼 상태코드로 돌려준다.

  Future<Response<Object?>> _streakShields(RequestOptions options) async {
    final Set<String> recorded = await _recordedDates();
    return _ok(
      options,
      _shields.statusJson(
        hasRecordOn: (DateTime day) => recorded.contains(wireDate(day)),
      ),
    );
  }

  /// 식단이나 운동 기록이 있는 날짜(YYYY-MM-DD) 전부.
  ///
  /// 기록 연속은 주 단위가 아니라 날짜를 거슬러 이어지므로 주별 집계로는 셀 수
  /// 없다. 데모 DB 는 한 회원의 기록뿐이라 통째로 읽어도 가볍다.
  Future<Set<String>> _recordedDates() async {
    final Set<String> days = <String>{};
    for (final row in await _db.select(_db.dietEntries).get()) {
      days.add(row.date);
    }
    for (final row in await _db.select(_db.exerciseSessions).get()) {
      if (row.minutes <= 0) continue;
      final int index = _weekdayLabels.indexOf(row.dayLabel);
      if (index < 0) continue;
      final DateTime monday = DateTime.parse(row.weekStart);
      days.add(
        wireDate(DateTime(monday.year, monday.month, monday.day + index)),
      );
    }
    return days;
  }

  /// (주 시작, 요일) 자리에 기록이 생겼다 — 그날 쓴 보호권을 되돌린다.
  /// 서버처럼 기록을 추가·수정하는 경로가 저장 뒤에 부른다.
  void _refundShieldOn(String weekStart, String dayLabel) {
    final int index = _weekdayLabels.indexOf(dayLabel);
    if (index < 0) return;
    final DateTime monday = DateTime.parse(weekStart);
    _refundShieldOnDate(
      wireDate(DateTime(monday.year, monday.month, monday.day + index)),
    );
  }

  /// `YYYY-MM-DD` 자리에 기록이 생겼다 — 식단 저장·수정이 부른다.
  void _refundShieldOnDate(String ymd) {
    if (!_isDateString(ymd)) return;
    _shields.refundFor(DateTime.parse(ymd));
  }

  Future<Response<Object?>> _streakShieldUse(RequestOptions options) async {
    final body = _jsonBody(options);
    final Object? raw = body['date'];
    if (raw is! String || !_isDateString(raw)) {
      return _unprocessable(options, 'date must be YYYY-MM-DD');
    }
    final DateTime day = DateTime.parse(raw);
    final Set<String> recorded = await _recordedDates();
    return _couponResponse(
      options,
      _shields.use(
        day,
        hasRecordOn: (DateTime d) => recorded.contains(wireDate(d)),
      ),
    );
  }

  Future<Response<Object?>> _activityCalendar(RequestOptions options) async {
    final DateTime today = _dateOnly(nowKst());
    final DateTime last = _minDate(_queryDate(options, 'to') ?? today, today);
    final DateTime first = _minDate(
      // 구간을 주지 않으면 오늘로 끝나는 371일(53주)이다 — 앱이 그리는 격자와
      // 같은 눈금이다. 서버 `activity_calendar_service.MAX_DAYS` 와 같은 값.
      _queryDate(options, 'from') ??
          DateTime(last.year, last.month, last.day - (_graphDays - 1)),
      last,
    );
    final Set<String> diet = await _dietDates();
    final Set<String> exercise = await _exerciseDates();
    final Set<String> recorded = <String>{...diet, ...exercise};
    final Map<String, Object?> shields = _shields.statusJson(
      hasRecordOn: (DateTime day) => recorded.contains(wireDate(day)),
    );
    return _ok(options, <String, Object?>{
      'from_date': wireDate(first),
      'to_date': wireDate(last),
      'days': <Map<String, Object?>>[
        for (
          DateTime cursor = first;
          !cursor.isAfter(last);
          cursor = DateTime(cursor.year, cursor.month, cursor.day + 1)
        )
          <String, Object?>{
            'date': wireDate(cursor),
            'has_diet': diet.contains(wireDate(cursor)),
            'has_exercise': exercise.contains(wireDate(cursor)),
            'protected': _shields.isProtected(cursor),
          },
      ],
      'record_streak_days': shields['record_streak_days'],
      'shields_held': shields['held'],
      'protectable_from': shields['protectable_from'],
      'protectable_to': shields['protectable_to'],
      'color': _palette.statusJson(),
    });
  }

  Future<Response<Object?>> _paletteColor(RequestOptions options) async {
    final body = _jsonBody(options);
    return _couponResponse(
      options,
      _palette.select((body['color'] as String?) ?? ''),
    );
  }

  /// 식단 기록이 있는 날짜(YYYY-MM-DD). 끼니 종류는 보지 않는다.
  Future<Set<String>> _dietDates() async => <String>{
    for (final row in await _db.select(_db.dietEntries).get()) row.date,
  };

  /// 운동 기록(분 > 0)이 있는 날짜(YYYY-MM-DD). 운동은 (주 시작, 요일)로 산다.
  Future<Set<String>> _exerciseDates() async {
    final Set<String> days = <String>{};
    for (final row in await _db.select(_db.exerciseSessions).get()) {
      if (row.minutes <= 0) continue;
      final int index = _weekdayLabels.indexOf(row.dayLabel);
      if (index < 0) continue;
      final DateTime monday = DateTime.parse(row.weekStart);
      days.add(
        wireDate(DateTime(monday.year, monday.month, monday.day + index)),
      );
    }
    return days;
  }
}

//
// 칸의 진하기는 그날 무엇을 남겼는가 세 단계다(없음 / 하나만 / 둘 다). 보호한
// 날은 실제 기록이 아니라 `protected` 만 true 다. 연속·보호권 값은 보호권
// 조회(`_streakShields`)와 같은 계산을 써서 한 화면의 두 자리가 어긋나지 않게 한다.

/// 기록 그래프가 한 번에 받는 날 수(53주). 서버
/// `activity_calendar_service.MAX_DAYS` 와 같은 값이다.
const int _graphDays = 371;

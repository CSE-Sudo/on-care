import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/repositories/activity_calendar_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';

/// 데모 모드의 기록 그래프 저장소 — 목업 API 의 답에 **운동만 덧씌운다**.
/// (#2075, #2076)
///
/// 데모의 기록은 두 곳에 있다: 식단은 로컬 목업 API 의 drift, 운동은 목업 운동
/// 저장소다. 목업 API(`GET /me/activity-calendar`)는 drift 만 보므로 식단·색·
/// 보호권은 맞지만 **운동 칸이 비어 있다.** 그래서 그 답을 받아 운동한 날만
/// 채우고, 기록 연속을 합친 기록으로 다시 센다.
///
/// 하루씩 묻지 않는다: 식단은 목업 API 한 번이 구간 전체를 주고, 운동은 주간
/// 응답 한 번이 그 주 7일을 준다. 1년(53주)이라도 기다리는 것은 **한 번 + 53번
/// (나란히)** 이다 — 날마다 식단을 물으면 371번이 된다.
class MockActivityCalendarRepository implements ActivityCalendarRepository {
  const MockActivityCalendarRepository({
    required ActivityCalendarRepository base,
    required DemoStreakShieldBook shields,
    required ExerciseRepository exercise,
    DateTime Function()? now,
  }) : _base = base,
       _shields = shields,
       _exercise = exercise,
       _now = now ?? nowKst;

  /// 목업 API 로 가는 저장소. 식단·그래프 색·보호권 상태는 여기서 온다.
  final ActivityCalendarRepository _base;

  final DemoStreakShieldBook _shields;
  final ExerciseRepository _exercise;
  final DateTime Function() _now;

  @override
  Future<ActivityCalendar> fetch({DateTime? from, DateTime? to}) async {
    final ActivityCalendar base = await _base.fetch(from: from, to: to);
    if (base.days.isEmpty) return base;

    final Set<String> exercised = await _exerciseDays(
      base.days.first.date,
      base.days.last.date,
    );
    final List<ActivityDay> days = <ActivityDay>[
      for (final ActivityDay day in base.days)
        ActivityDay(
          date: day.date,
          hasDiet: day.hasDiet,
          hasExercise: exercised.contains(_key(day.date)),
          // 보호한 날에 운동 기록이 생겼으면 목업 원장이 이미 보호를 되돌렸다.
          protected: day.protected,
        ),
    ];

    final Set<String> recorded = <String>{
      for (final ActivityDay day in days)
        if (!day.isEmpty) _key(day.date),
    };
    return ActivityCalendar(
      days: days,
      // 연속은 **합친 기록**으로 다시 센다 — 목업 API 가 센 값은 운동을 모른다.
      // 구간이 원장의 상한([DemoStreakShieldBook.streakDayLimit])보다 길어야
      // 정확하다. 화면은 늘 1년을 부르므로 그 조건을 넘는다.
      recordStreakDays: _shields.recordStreakDays(
        (DateTime day) => recorded.contains(_key(day)),
      ),
      shieldsHeld: base.shieldsHeld,
      protectableFrom: base.protectableFrom,
      protectableTo: base.protectableTo,
      color: base.color,
    );
  }

  @override
  Future<GraphColorState> selectColor(String color) => _base.selectColor(color);

  /// [first]…[last] 에서 운동 기록(분 > 0)이 있는 날. 주 단위로 나란히 읽는다.
  Future<Set<String>> _exerciseDays(DateTime first, DateTime last) async {
    final List<DateTime> mondays = <DateTime>[
      for (
        DateTime monday = _mondayOf(first);
        !monday.isAfter(last);
        monday = _shift(monday, 7)
      )
        monday,
    ];
    final List<ExerciseWeek> weeks = await Future.wait<ExerciseWeek>(
      mondays.map(_exercise.fetchWeek),
    );
    final Set<String> days = <String>{};
    for (int w = 0; w < mondays.length; w++) {
      final List<double> minutes = weeks[w].dailyMinutes;
      for (int i = 0; i < minutes.length && i < 7; i++) {
        if (minutes[i] <= 0) continue;
        final DateTime day = _shift(mondays[w], i);
        if (day.isBefore(first) || day.isAfter(last)) continue;
        days.add(_key(day));
      }
    }
    return days;
  }

  /// 오늘(KST). 구간을 정하는 쪽은 목업 API 지만, 시각을 바꿔 끼울 수 있게 둔다.
  DateTime get today => _dateOnly(_now());

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _shift(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static DateTime _mondayOf(DateTime d) => _shift(d, 1 - d.weekday);

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

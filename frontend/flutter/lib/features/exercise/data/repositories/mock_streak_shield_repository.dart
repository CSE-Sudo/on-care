import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/streak_shield_repository.dart';

/// 데모 모드의 보호권 저장소. 규칙은 [DemoStreakShieldBook] 이 서버와 같게 들고
/// 있다. (#1788)
///
/// 보호권이 지키는 것은 **기록 연속**이라 식단과 운동을 함께 봐야 하는데, 데모의
/// 두 기록은 사는 곳이 다르다 — 운동은 목업 운동 저장소, 식단은 로컬 목업 API 의
/// drift 다. 그래서 두 저장소에 [_maxWalk] 일치를 물어 날짜별 기록 여부를 만든다.
///
/// 하루씩 묻지 않는다: 운동은 구간이 걸치는 주를 나란히 읽고(주간 응답 하나가 그
/// 주 7일을 준다), 식단은 그중 운동이 없는 날만 나란히 읽는다. 기다리는 것은
/// 연속이 얼마나 길든 **두 번**이다 — 기록 그래프(`MockActivityCalendarRepository`)
/// 가 한 해치를 읽는 방식과 같다.
class MockStreakShieldRepository implements StreakShieldRepository {
  const MockStreakShieldRepository({
    required DemoStreakShieldBook book,
    required ExerciseRepository exercise,
    required DietRepository diet,
    DateTime Function()? now,
  }) : _book = book,
       _exercise = exercise,
       _diet = diet,
       _now = now ?? nowKst;

  /// 거슬러 올라가며 볼 날의 상한. 원장이 연속을 세는 상한과 **같은 값**이어야
  /// 한다 — 여기서 덜 읽으면 원장은 그 앞을 "기록 없음" 으로 보고 연속을 짧게
  /// 센다.
  static const int _maxWalk = DemoStreakShieldBook.streakDayLimit;

  final DemoStreakShieldBook _book;
  final ExerciseRepository _exercise;
  final DietRepository _diet;
  final DateTime Function() _now;

  @override
  Future<StreakShields> fetch() async =>
      StreakShields.fromJson(_book.statusJson(hasRecordOn: await _recorded()));

  @override
  Future<StreakShields> use(DateTime date) async {
    final DateTime day = DateTime(date.year, date.month, date.day);
    final DemoCouponResult result = _book.use(
      day,
      hasRecordOn: await _recorded(around: day),
    );
    if (result.statusCode >= 400) {
      throw ServerError(statusCode: result.statusCode);
    }
    return StreakShields.fromJson(
      (result.body! as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }

  /// [around](없으면 오늘)부터 [_maxWalk] 일치를 거슬러 날짜별 기록 여부를 미리
  /// 읽어 둔다. 원장은 동기 함수를 기대하므로 비동기 조회를 여기서 끝낸다.
  ///
  /// 연속이 끊기는 날에서 멈추지 않고 구간 전체를 읽는다. 원장이 기록 여부를
  /// 묻는 곳은 연속 계산만이 아니다 — 보호할 수 있는 날인지도 묻는데(최근
  /// [DemoStreakShieldBook.protectWindowDays] 일), 끊긴 데서 멈추면 그 너머의
  /// 기록한 날이 "기록 없음" 으로 답해 이미 기록이 있는 날에 보호권을 쓰게 된다.
  Future<bool Function(DateTime day)> _recorded({DateTime? around}) async {
    final DateTime today = _dateOnly(_now());
    final DateTime last = around == null
        ? today
        : (around.isAfter(today) ? around : today);
    final DateTime first = _shift(last, -(_maxWalk - 1));

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

    final Set<String> recorded = <String>{};
    // 운동이 있는 날은 식단을 묻지 않는다 — 답이 이미 정해졌다.
    final List<DateTime> ask = <DateTime>[];
    for (int w = 0; w < mondays.length; w++) {
      final List<double> minutes = weeks[w].dailyMinutes;
      for (int i = 0; i < 7; i++) {
        final DateTime day = _shift(mondays[w], i);
        if (day.isBefore(first) || day.isAfter(last)) continue;
        if (i < minutes.length && minutes[i] > 0) {
          recorded.add(_key(day));
          continue;
        }
        ask.add(day);
      }
    }

    final List<DietDay> diets = await Future.wait<DietDay>(
      ask.map(_diet.fetchByDate),
    );
    for (int i = 0; i < ask.length; i++) {
      if (diets[i].entries.isNotEmpty) recorded.add(_key(ask[i]));
    }

    return (DateTime day) => recorded.contains(_key(_dateOnly(day)));
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _shift(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static DateTime _mondayOf(DateTime d) => _shift(d, 1 - d.weekday);

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

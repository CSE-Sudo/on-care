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
/// drift 다. 그래서 두 저장소에 물어 이어진 길이를 센다. 연속이 끊기는 주에서
/// 멈추므로 보통 몇 번이면 끝나고, 아주 긴 연속에서도 [_maxWalk] 일에서 멈춘다.
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

  /// 오늘부터(또는 [around] 부터) 거슬러 올라가며 날짜별 기록 여부를 미리 읽어
  /// 둔다. 원장은 동기 함수를 기대하므로 비동기 조회를 여기서 끝낸다.
  ///
  /// 하루씩 묻지 않고 **주 단위로** 읽는다: 운동은 주간 응답 한 번이 그 주 7일을
  /// 다 주고(하루마다 부르면 같은 주를 일곱 번 다시 읽는다), 식단은 그 주에서
  /// 아직 모르는 날만 나란히 읽는다. 그래서 한 주에 기다리는 횟수가 둘이다.
  Future<bool Function(DateTime day)> _recorded({DateTime? around}) async {
    final DateTime today = _dateOnly(_now());
    final Set<String> recorded = <String>{};
    final Map<String, bool> known = <String, bool>{};
    DateTime cursor = around == null
        ? today
        : (around.isAfter(today) ? around : today);
    final DateTime start = cursor;
    for (int i = 0; i < _maxWalk; i++) {
      if (!known.containsKey(_key(cursor))) {
        await _loadWeekOf(cursor, upTo: start, into: known);
      }
      final bool has = known[_key(cursor)] ?? false;
      if (has) recorded.add(_key(cursor));
      // 보호한 날도 이어진 날이라 거기서 멈추지 않는다.
      if (!has && !_book.isProtected(cursor) && cursor.isBefore(today)) break;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return (DateTime day) => recorded.contains(_key(_dateOnly(day)));
  }

  /// [day] 가 든 주의 기록 여부를 [into] 에 채운다. [upTo] 뒤의 날은 거슬러
  /// 올라가는 길에 없으니 읽지 않는다.
  Future<void> _loadWeekOf(
    DateTime day, {
    required DateTime upTo,
    required Map<String, bool> into,
  }) async {
    final DateTime monday = _mondayOf(day);
    final List<DateTime> days = <DateTime>[
      for (int i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final ExerciseWeek week = await _exercise.fetchWeek(monday);

    // 운동이 있는 날은 식단을 묻지 않는다 — 답이 이미 정해졌다.
    final List<DateTime> ask = <DateTime>[];
    for (int i = 0; i < days.length; i++) {
      if (days[i].isAfter(upTo)) continue;
      if (i < week.dailyMinutes.length && week.dailyMinutes[i] > 0) {
        into[_key(days[i])] = true;
        continue;
      }
      ask.add(days[i]);
    }
    final List<DietDay> diets = await Future.wait<DietDay>(
      ask.map((DateTime d) => _diet.fetchByDate(d)),
    );
    for (int i = 0; i < ask.length; i++) {
      into[_key(ask[i])] = diets[i].entries.isNotEmpty;
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

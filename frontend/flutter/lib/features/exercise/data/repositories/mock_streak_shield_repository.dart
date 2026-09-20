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
/// drift 다. 그래서 두 저장소에 날짜별로 물어 이어진 길이를 센다. 연속이 끊기는
/// 날에서 멈추므로 보통 몇 번이면 끝나고, 아주 긴 연속에서도 [_maxWalk] 일에서
/// 멈춘다.
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

  /// 거슬러 올라가며 볼 날의 상한. 데모 픽스처가 35주치라 그보다 넉넉하다.
  static const int _maxWalk = 365;

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
  Future<bool Function(DateTime day)> _recorded({DateTime? around}) async {
    final DateTime today = _dateOnly(_now());
    final Set<String> recorded = <String>{};
    DateTime cursor = around == null
        ? today
        : (around.isAfter(today) ? around : today);
    for (int i = 0; i < _maxWalk; i++) {
      final bool has = await _hasRecordOn(cursor);
      if (has) recorded.add(_key(cursor));
      // 보호한 날도 이어진 날이라 거기서 멈추지 않는다.
      if (!has && !_book.isProtected(cursor) && cursor.isBefore(today)) break;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return (DateTime day) => recorded.contains(_key(_dateOnly(day)));
  }

  Future<bool> _hasRecordOn(DateTime day) async {
    final ExerciseWeek week = await _exercise.fetchWeek(_mondayOf(day));
    final int i = day.weekday - 1;
    if (i < week.dailyMinutes.length && week.dailyMinutes[i] > 0) return true;
    final DietDay diet = await _diet.fetchByDate(day);
    return diet.entries.isNotEmpty;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

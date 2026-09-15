import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/streak_shield_repository.dart';

/// 데모 모드의 보호권 저장소. 규칙은 [DemoStreakShieldBook] 이 서버와 같게 들고
/// 있다. (#1788)
///
/// 데모의 운동 기록은 목업 운동 저장소에 있다(로컬 목업 API 의 drift 가 아니다).
/// 그래서 "그날 운동 기록이 있나" 는 [ExerciseRepository.fetchWeek] 으로 운동
/// 현황이 보는 것과 같은 주를 받아 판단한다.
class MockStreakShieldRepository implements StreakShieldRepository {
  const MockStreakShieldRepository({
    required DemoStreakShieldBook book,
    required ExerciseRepository exercise,
  }) : _book = book,
       _exercise = exercise;

  final DemoStreakShieldBook _book;
  final ExerciseRepository _exercise;

  @override
  Future<StreakShields> fetch() async =>
      StreakShields.fromJson(_book.statusJson());

  @override
  Future<StreakShields> use(DateTime date) async {
    final DateTime day = DateTime(date.year, date.month, date.day);
    final ExerciseWeek week = await _exercise.fetchWeek(
      DateTime(day.year, day.month, day.day - (day.weekday - 1)),
    );
    final int i = day.weekday - 1;
    final bool exercised =
        i < week.dailyMinutes.length && week.dailyMinutes[i] > 0;
    final DemoCouponResult result = _book.use(
      day,
      hasExerciseOn: (_) => exercised,
    );
    if (result.statusCode >= 400) {
      throw ServerError(statusCode: result.statusCode);
    }
    return StreakShields.fromJson(
      (result.body! as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }
}

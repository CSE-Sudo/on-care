/// 데모 모드의 연속 기록 보호권 — 목업 운동 저장소와 보호권 원장이 한 규칙으로
/// 움직인다. (#1788)
///
/// 데모의 기록은 김민수 픽스처라 어제 운동 기록이 있는지는 픽스처가 정한다. 그래서
/// 기대값을 그 주의 실제 기록에서 끌어낸다 — 규칙은 "기록이 있으면 보호하지 않는다"
/// 하나다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_streak_shield_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';

/// 목요일. 어제(수)는 이번 주 안이다.
final DateTime _today = DateTime(2026, 8, 20, 9);
final DateTime _yesterday = DateTime(2026, 8, 19);
const int _yesterdayIndex = 2;

void main() {
  late DemoStreakShieldBook book;
  late MockExerciseRepository exercise;

  setUp(() {
    book = DemoStreakShieldBook(
      ledger: DemoPointsLedger(openingBalance: 1000),
      now: () => _today,
    );
    exercise = MockExerciseRepository(today: _today, shields: book);
  });

  test('이번 주 조회에 보호권 상태가 실리고, 보호한 날은 연속 일수에만 들어간다', () async {
    expect(book.exchange().statusCode, 201);

    final ExerciseWeek before = await exercise.fetchThisWeek();
    final bool exercisedYesterday =
        before.dailyMinutes[_yesterdayIndex] > 0;
    expect(before.streakShield?.held, 1);
    expect(
      before.streakShield?.protectableDate,
      exercisedYesterday ? isNull : _yesterday,
    );

    // 주간 조립을 재려고 기록 여부와 상관없이 어제를 보호한다.
    expect(book.use(_yesterday, hasExerciseOn: (_) => false).statusCode, 200);

    final ExerciseWeek after = await exercise.fetchThisWeek();
    expect(after.isProtectedDay(_yesterdayIndex), isTrue);
    expect(
      after.streakDays,
      longestActiveStreak(after.dailyMinutes, protectedDays: after.protectedDays),
    );
    expect(after.totalMinutes, before.totalMinutes);
    expect(after.totalCalories, before.totalCalories);
    expect(after.dailyMinutes, before.dailyMinutes);
    expect(after.streakShield?.held, 0);
    expect(after.streakShield?.protectableDate, isNull);

    // 지난 주 조회에는 보호권 상태가 없다.
    final ExerciseWeek past = await exercise.fetchWeek(DateTime(2026, 8, 10));
    expect(past.streakShield, isNull);
  });

  test('보호한 날에 직접 추가·수정·루틴 완료로 기록이 생기면 보호권이 돌아온다', () async {
    expect(book.exchange().statusCode, 201);
    // 기록 여부와 상관없이 되돌리기만 재려고 어제를 보호해 둔다.
    expect(book.use(_yesterday, hasExerciseOn: (_) => false).statusCode, 200);
    expect(book.held, 0);

    await exercise.addSession(
      type: ExerciseType.cardio,
      minutes: 20,
      calories: 100,
      date: _yesterday,
      name: '걷기',
    );
    expect(book.held, 1);
    expect(book.isProtected(_yesterday), isFalse);
    // 한 번 더 기록해도 더 돌려주지 않는다.
    await exercise.addSession(
      type: ExerciseType.cardio,
      minutes: 10,
      calories: 50,
      date: _yesterday,
    );
    expect(book.held, 1);

    // 수정으로 그날로 옮긴 경우.
    expect(book.use(_yesterday, hasExerciseOn: (_) => false).statusCode, 200);
    expect(book.held, 0);
    final ExerciseSession monday = await exercise.addSession(
      type: ExerciseType.cardio,
      minutes: 15,
      calories: 60,
      date: DateTime(2026, 8, 17),
    );
    await exercise.updateSession(
      id: monday.id!,
      type: ExerciseType.cardio,
      minutes: 15,
      calories: 60,
      date: _yesterday,
    );
    expect(book.held, 1);

    // 루틴 완료 기록도 같다.
    expect(book.use(_yesterday, hasExerciseOn: (_) => false).statusCode, 200);
    await exercise.addAssignedRoutineSession(
      type: ExerciseType.cardio,
      minutes: 20,
      calories: 100,
      date: _yesterday,
      routineId: 'routine-1',
      name: '걷기',
    );
    expect(book.held, 1);
  });

  test('목업 보호권 저장소는 그날 기록이 있으면 쓰지 않고, 없으면 한 장을 쓴다', () async {
    expect(book.exchange().statusCode, 201);
    final MockStreakShieldRepository repo = MockStreakShieldRepository(
      book: book,
      exercise: exercise,
    );
    final ExerciseWeek week = await exercise.fetchThisWeek();

    if (week.dailyMinutes[_yesterdayIndex] > 0) {
      await expectLater(repo.use(_yesterday), throwsA(isA<ServerError>()));
      expect((await repo.fetch()).held, 1);
    } else {
      final StreakShields status = await repo.use(_yesterday);
      expect(status.held, 0);
      expect(status.used.single.date, _yesterday);
    }
    // 오늘은 어느 경우에도 보호하지 않는다.
    await expectLater(
      repo.use(DateTime(2026, 8, 20)),
      throwsA(isA<ServerError>()),
    );
  });
}

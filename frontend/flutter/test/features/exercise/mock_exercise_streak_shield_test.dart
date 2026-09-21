/// 데모 모드의 연속 기록 보호권 — 목업 운동 저장소·목업 식단과 보호권 원장이 한
/// 규칙으로 움직인다. (#1788)
///
/// 보호권은 **기록 연속**(식단 한 끼든 운동 한 건이든)을 지킨다. 운동 탭의 주간
/// 응답에는 보호권이 실리지 않고 연속 일수도 운동만 센다 — 여기서 그 경계를 본다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_streak_shield_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';

/// 목요일. 어제(수)는 이번 주 안이다.
final DateTime _today = DateTime(2026, 8, 20, 9);
final DateTime _yesterday = DateTime(2026, 8, 19);
const int _yesterdayIndex = 2;

/// 날짜별 끼니 수만 아는 식단 저장소 — 기록 연속은 "한 끼라도 있나" 만 본다.
class _FakeDiet implements DietRepository {
  _FakeDiet([Set<DateTime>? days])
    : _days = <String>{for (final DateTime d in days ?? <DateTime>{}) _key(d)};

  final Set<String> _days;

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static const DietDay _empty = DietDay(
    entries: <DietEntry>[],
    totalCalories: 0,
    macros: DietMacros.zero(),
    totalSodiumMg: 0,
    totalSugarG: 0,
    aiCoachMessage: '',
  );

  @override
  Future<DietDay> fetchByDate(DateTime date) async => _days.contains(_key(date))
      ? DietDay(
          entries: <DietEntry>[
            DietEntry(
              id: 'e-${_key(date)}',
              mealType: MealType.lunch,
              timeLabel: '12:00',
              foods: const <FoodItem>[],
              totalCalories: 500,
            ),
          ],
          totalCalories: 500,
          macros: const DietMacros.zero(),
          totalSodiumMg: 0,
          totalSugarG: 0,
          aiCoachMessage: '',
        )
      : _empty;

  @override
  Future<DietDay> fetchToday() => fetchByDate(_today);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

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

  MockStreakShieldRepository repoWith(_FakeDiet diet) =>
      MockStreakShieldRepository(
        book: book,
        exercise: exercise,
        diet: diet,
        now: () => _today,
      );

  test('보호권은 운동 주간 응답에 실리지 않고 연속 일수도 바꾸지 않는다', () async {
    expect(book.exchange().statusCode, 201);

    final ExerciseWeek before = await exercise.fetchThisWeek();
    // 기록 여부와 상관없이 주간 조립을 재려고 어제를 보호한다.
    expect(book.use(_yesterday, hasRecordOn: (_) => false).statusCode, 200);

    final ExerciseWeek after = await exercise.fetchThisWeek();
    expect(after.streakDays, longestActiveStreak(after.dailyMinutes));
    expect(after.streakDays, before.streakDays);
    expect(after.totalMinutes, before.totalMinutes);
    expect(after.totalCalories, before.totalCalories);
    expect(after.dailyMinutes, before.dailyMinutes);
  });

  test('보호한 날에 직접 추가·수정·루틴 완료로 기록이 생기면 보호권이 돌아온다', () async {
    expect(book.exchange().statusCode, 201);
    // 기록 여부와 상관없이 되돌리기만 재려고 어제를 보호해 둔다.
    expect(book.use(_yesterday, hasRecordOn: (_) => false).statusCode, 200);
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
    expect(book.use(_yesterday, hasRecordOn: (_) => false).statusCode, 200);
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
    expect(book.use(_yesterday, hasRecordOn: (_) => false).statusCode, 200);
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

  test('식단만 남긴 날도 기록한 날이라 보호하지 않는다', () async {
    expect(book.exchange().statusCode, 201);
    final MockStreakShieldRepository repo = repoWith(
      _FakeDiet(<DateTime>{_yesterday}),
    );

    await expectLater(repo.use(_yesterday), throwsA(isA<ServerError>()));
    final StreakShields status = await repo.fetch();
    expect(status.held, 1);
    // 창은 보유 수만 본다 — 어제에 기록이 있어도 창은 열려 있고, 그 하루가 빠질
    // 뿐이다(사용은 위에서 거절당했다).
    expect(status.protectableTo, _yesterday);
    // 어제 식단이 있어 연속은 최소 하루다.
    expect(status.recordStreakDays, greaterThanOrEqualTo(1));
  });

  test('연속이 끊긴 날 너머에 있어도 기록이 있는 날은 보호하지 않는다', () async {
    expect(book.exchange().statusCode, 201);
    // 어제는 비었고(연속이 거기서 끊긴다), 그 너머 20일 전에는 식단이 있다.
    final DateTime longAgo = DateTime(2026, 7, 31);
    expect(_today.difference(longAgo).inDays, lessThan(30));
    final MockStreakShieldRepository repo = repoWith(_FakeDiet(<DateTime>{longAgo}));

    // 끊긴 데서 멈추고 읽으면 20일 전이 "기록 없음" 으로 답해 보호권이 빠진다.
    await expectLater(repo.use(longAgo), throwsA(isA<ServerError>()));
    expect((await repo.fetch()).held, 1);
  });

  test('목업 보호권 저장소는 그날 기록이 있으면 쓰지 않고, 없으면 한 장을 쓴다', () async {
    expect(book.exchange().statusCode, 201);
    final MockStreakShieldRepository repo = repoWith(_FakeDiet());
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

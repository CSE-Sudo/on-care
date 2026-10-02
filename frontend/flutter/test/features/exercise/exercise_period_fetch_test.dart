/// `전체` 운동 그래프는 기간을 **한 번에** 받는다. (#2247, #2248)
///
/// 예전에는 주마다 `GET /exercise/weeks/current?week_start=` 를 불렀다. `전체` 가
/// 모든 기록을 그리게 되면서(#2079) 해가 바뀐 회원에게 쉰 번이 넘는 왕복이 됐다.
///
/// 이번 주만 `exerciseWeekProvider` 의 값으로 덮는다 — 방금 추가한 기록은 그
/// 캐시에만 반영돼 있어서다(#671).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/record_span.dart';

ExerciseWeek _week({double minutes = 30, double calories = 200}) => ExerciseWeek(
  sessions: const <ExerciseSession>[],
  dailyMinutes: <double>[minutes, 0, 0, 0, 0, 0, 0],
  dailyCalories: <double>[calories, 0, 0, 0, 0, 0, 0],
  cardioMinutes: <double>[minutes, 0, 0, 0, 0, 0, 0],
  strengthMinutes: const <double>[0, 0, 0, 0, 0, 0, 0],
  stretchingMinutes: const <double>[0, 0, 0, 0, 0, 0, 0],
  otherMinutes: const <double>[0, 0, 0, 0, 0, 0, 0],
  strengthSets: const <double>[0, 0, 0, 0, 0, 0, 0],
  dayLabels: const <String>['월', '화', '수', '목', '금', '토', '일'],
  totalMinutes: minutes.round(),
  totalCalories: calories.round(),
  streakDays: 1,
  aiCoachMessage: '',
);

/// 부른 횟수와 구간을 적어 두는 대역.
class _CountingRepository implements ExerciseRepository {
  int periodCalls = 0;
  int weekCalls = 0;
  ({DateTime? from, DateTime? to})? lastPeriod;

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async {
    periodCalls += 1;
    lastPeriod = (from: from, to: to);
    final DateTime first = from!;
    final DateTime last = to!;
    final List<ExercisePeriodWeek> weeks = <ExercisePeriodWeek>[];
    DateTime cursor = first;
    while (!cursor.isAfter(last)) {
      weeks.add((weekStart: cursor, week: _week()));
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 7);
    }
    return weeks;
  }

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async {
    weekCalls += 1;
    return _week();
  }

  @override
  Future<ExerciseWeek> fetchThisWeek() async {
    weekCalls += 1;
    // 이번 주만 다른 값을 준다 — 덮어쓰는지 보려고.
    return _week(minutes: 99, calories: 999);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('이 테스트가 쓰지 않는 길이다.');
}

void main() {
  setUp(useFixedKstDate);

  Future<List<ExerciseDayBar>> bars(
    _CountingRepository repo, {
    DateTime? firstRecord,
  }) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        exerciseRepositoryProvider.overrideWithValue(repo),
        testRecordSpanOverride(exercise: firstRecord),
      ],
    );
    addTearDown(container.dispose);
    return container.read(exerciseAllPeriodProvider.future);
  }

  test('기간은 한 번만 부른다 — 주마다 부르지 않는다', () async {
    final _CountingRepository repo = _CountingRepository();

    await bars(repo);

    expect(repo.periodCalls, 1);
    // 이번 주는 `exerciseWeekProvider`(fetchThisWeek) 한 번이다.
    expect(repo.weekCalls, 1);
  });

  test('첫 기록 주부터 오늘까지를 묻는다', () async {
    final _CountingRepository repo = _CountingRepository();
    final DateTime firstRecord = DateTime(2026, 8, 5); // 수요일

    await bars(repo, firstRecord: firstRecord);

    // 그 주의 월요일부터다 — 한 칸이 한 주라 주를 쪼갤 수 없다.
    expect(repo.lastPeriod!.from, DateTime(2026, 8, 3));
    expect(repo.lastPeriod!.to, isNotNull);
  });

  test('이번 주 칸은 기간 응답이 아니라 이번 주 캐시를 쓴다 (#671)', () async {
    final _CountingRepository repo = _CountingRepository();

    final List<ExerciseDayBar> result = await bars(repo);

    // 대역은 기간 응답에 30분, 이번 주 조회에 99분을 준다.
    expect(result.where((ExerciseDayBar b) => b.minutes == 99), isNotEmpty);
  });
}

/// 데모 모드의 기록 그래프 — 목업 API 의 답에 운동을 덧씌우고 연속을 다시 센다.
/// (#2075, #2076)
///
/// 데모의 기록은 두 곳에 있다(식단은 목업 API 의 drift, 운동은 목업 운동 저장소).
/// 저장소가 하는 일은 그 둘을 합치는 것뿐이라, 여기서는 **합친 결과**가 맞는지와
/// 한 해치를 읽는 데 부르는 횟수를 본다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/features/benefits/data/repositories/mock_activity_calendar_repository.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/repositories/activity_calendar_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';

/// 목요일. 어제(수)는 이번 주 안이다.
final DateTime _today = DateTime(2026, 8, 20, 9);
final DateTime _yesterday = DateTime(2026, 8, 19);

String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// 목업 API 대역 — 식단만 있는 응답을 돌려준다(운동 칸은 비어 있다).
class _FakeBase implements ActivityCalendarRepository {
  _FakeBase({
    Set<DateTime>? diet,
    Set<DateTime>? protectedDays,
    this.shieldsHeld = 0,
    this.protectableFrom,
    this.protectableTo,
  }) : _diet = <String>{for (final DateTime d in diet ?? <DateTime>{}) _key(d)},
       _protected = <String>{
         for (final DateTime d in protectedDays ?? <DateTime>{}) _key(d),
       };

  final Set<String> _diet;
  final Set<String> _protected;
  final int shieldsHeld;
  final DateTime? protectableFrom;
  final DateTime? protectableTo;

  /// 목업 API 가 들고 있는 색. 저장소는 그대로 흘려보내기만 한다.
  final GraphColorState color = GraphColorState.base;

  /// 이 대역을 부른 횟수 — 하루씩 묻지 않는지 본다.
  int calls = 0;
  String? selected;

  @override
  Future<ActivityCalendar> fetch({DateTime? from, DateTime? to}) async {
    calls += 1;
    final DateTime last = to ?? DateTime(2026, 8, 20);
    final DateTime first =
        from ?? DateTime(last.year, last.month, last.day - 370);
    return ActivityCalendar(
      days: <ActivityDay>[
        for (
          DateTime d = first;
          !d.isAfter(last);
          d = DateTime(d.year, d.month, d.day + 1)
        )
          ActivityDay(
            date: d,
            hasDiet: _diet.contains(_key(d)),
            protected: _protected.contains(_key(d)),
          ),
      ],
      // 목업 API 는 운동을 모르므로 연속도 식단만으로 센 값이다.
      recordStreakDays: 0,
      shieldsHeld: shieldsHeld,
      protectableFrom: protectableFrom,
      protectableTo: protectableTo,
      color: color,
    );
  }

  @override
  Future<GraphColorState> selectColor(String color) async {
    selected = color;
    return GraphColorState(
      current: color,
      unlocked: <String>['blue', color],
      palette: const <String>['blue', 'green', 'purple', 'orange', 'pink'],
      cost: 150,
    );
  }
}

/// 날짜별 운동 분만 아는 운동 저장소.
class _FakeExercise implements ExerciseRepository {
  _FakeExercise([Set<DateTime>? days])
    : _days = <String>{for (final DateTime d in days ?? <DateTime>{}) _key(d)};

  final Set<String> _days;

  /// 주간 응답을 부른 횟수 — 주 단위로 읽는지 본다.
  int weekCalls = 0;

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async => const <ExercisePeriodWeek>[];

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async {
    weekCalls += 1;
    final DateTime monday = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day - (weekStart.weekday - 1),
    );
    return ExerciseWeek(
      sessions: const <ExerciseSession>[],
      dailyMinutes: <double>[
        for (int i = 0; i < 7; i++)
          _days.contains(
                _key(DateTime(monday.year, monday.month, monday.day + i)),
              )
              ? 30
              : 0,
      ],
      dayLabels: const <String>['월', '화', '수', '목', '금', '토', '일'],
      totalMinutes: 0,
      totalCalories: 0,
      streakDays: 0,
      aiCoachMessage: '',
    );
  }

  @override
  Future<ExerciseWeek> fetchThisWeek() => fetchWeek(_today);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late DemoStreakShieldBook shields;

  setUp(() {
    shields = DemoStreakShieldBook(
      ledger: DemoPointsLedger(openingBalance: 1000),
      now: () => _today,
    );
  });

  MockActivityCalendarRepository repoWith(
    _FakeBase base, [
    _FakeExercise? exercise,
  ]) => MockActivityCalendarRepository(
    base: base,
    shields: shields,
    exercise: exercise ?? _FakeExercise(),
    now: () => _today,
  );

  ActivityDay dayOf(ActivityCalendar c, DateTime day) => c.days.firstWhere(
    (ActivityDay d) =>
        d.date.year == day.year &&
        d.date.month == day.month &&
        d.date.day == day.day,
  );

  test('칸은 식단·운동을 합쳐 세 단계로 갈린다', () async {
    final DateTime dietOnly = DateTime(2026, 8, 17);
    final DateTime exerciseOnly = DateTime(2026, 8, 18);
    final DateTime both = DateTime(2026, 8, 16);

    final ActivityCalendar calendar = await repoWith(
      _FakeBase(diet: <DateTime>{dietOnly, both}),
      _FakeExercise(<DateTime>{exerciseOnly, both}),
    ).fetch();

    expect(dayOf(calendar, dietOnly).level, RecordLevel.partial);
    expect(dayOf(calendar, exerciseOnly).level, RecordLevel.partial);
    expect(dayOf(calendar, both).level, RecordLevel.full);
    expect(dayOf(calendar, _yesterday).level, RecordLevel.none);
  });

  test('한 해치를 읽어도 식단은 한 번, 운동은 주마다 한 번이다', () async {
    final _FakeBase base = _FakeBase();
    final _FakeExercise exercise = _FakeExercise();

    final ActivityCalendar calendar = await repoWith(base, exercise).fetch();

    expect(calendar.days.length, 371);
    // 날마다 물으면 371번이 된다 — 목업 API 한 번이 구간 전체를 준다.
    expect(base.calls, 1);
    expect(exercise.weekCalls, lessThanOrEqualTo(54));
  });

  test('연속은 운동을 포함해 다시 센다', () async {
    // 목업 API 는 식단만 알아 연속을 0 으로 주지만, 운동을 합치면 이어진다.
    final Set<DateTime> workouts = <DateTime>{
      for (int i = 0; i < 5; i++)
        DateTime(_today.year, _today.month, _today.day - i),
    };

    final ActivityCalendar calendar = await repoWith(
      _FakeBase(),
      _FakeExercise(workouts),
    ).fetch();

    expect(calendar.recordStreakDays, 5);
  });

  test('보호한 날은 기록 없이 방패만 서고 연속에는 든다', () async {
    expect(shields.exchange().statusCode, 201);
    expect(shields.use(_yesterday, hasRecordOn: (_) => false).statusCode, 200);

    final ActivityCalendar calendar = await repoWith(
      _FakeBase(protectedDays: <DateTime>{_yesterday}),
      _FakeExercise(<DateTime>{DateTime(2026, 8, 20)}),
    ).fetch();
    final ActivityDay day = dayOf(calendar, _yesterday);

    expect(day.protected, isTrue);
    expect((day.hasDiet, day.hasExercise), (false, false));
    // 오늘(운동)·어제(보호)가 이어진다.
    expect(calendar.recordStreakDays, 2);
    expect(calendar.isProtectable(day), isFalse);
  });

  test('창 안의 빈 날이 모두 누를 수 있는 칸이다 (#2075)', () async {
    final DateTime recorded = DateTime(2026, 8, 10);

    final ActivityCalendar calendar = await repoWith(
      _FakeBase(
        diet: <DateTime>{recorded},
        shieldsHeld: 1,
        protectableFrom: DateTime(2026, 7, 21),
        protectableTo: _yesterday,
      ),
    ).fetch();

    // 어제뿐 아니라 창 안의 다른 빈 날도 누를 수 있다.
    expect(calendar.isProtectable(dayOf(calendar, _yesterday)), isTrue);
    expect(
      calendar.isProtectable(dayOf(calendar, DateTime(2026, 8, 5))),
      isTrue,
    );
    // 기록이 있는 날·오늘·창보다 오래된 날은 아니다.
    expect(calendar.isProtectable(dayOf(calendar, recorded)), isFalse);
    expect(
      calendar.isProtectable(dayOf(calendar, DateTime(2026, 8, 20))),
      isFalse,
    );
    expect(
      calendar.isProtectable(dayOf(calendar, DateTime(2026, 7))),
      isFalse,
    );
  });

  test('보호권이 없으면 누를 수 있는 칸이 없다', () async {
    final ActivityCalendar calendar = await repoWith(_FakeBase()).fetch();

    expect(calendar.shieldsHeld, 0);
    expect(calendar.isProtectable(dayOf(calendar, _yesterday)), isFalse);
  });

  test('색은 목업 API 가 들고 있고 고르기도 그쪽으로 간다', () async {
    final _FakeBase base = _FakeBase();
    final MockActivityCalendarRepository repo = repoWith(base);

    expect((await repo.fetch()).color.current, 'blue');

    final GraphColorState picked = await repo.selectColor('green');

    expect(base.selected, 'green');
    expect(picked.current, 'green');
  });
}

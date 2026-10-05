/// 운동 기록이 바뀐 뒤의 갱신은 한 함수가 맡는다. (#2629, #2631, #2634)
///
/// 예전에는 저장·삭제·추천 개인운동 완료·완료 취소가 비울 목록을 제각각 적어,
/// 지난 주 캐시와 AI 조언은 어디서도 비워지지 않았고 활동 달력·주간 챌린지는
/// 경로에 따라 빠졌다. 여기서는 그 함수의 **대상 목록**과, 실제 provider 가
/// 그 뒤에 새 값을 읽는지를 본다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/data/repositories/dio_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_refresh.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/shared/services/record_span_provider.dart';

import '../../helpers/demo_exercise.dart';
import '../../helpers/fixed_clock.dart';

/// 고정 금요일 — 이번 주 월요일은 2024-01-01, 지난 주 월요일은 2023-12-25.
final DateTime _friday = DateTime(2024, 1, 5);
final DateTime _thisMonday = DateTime(2024);
final DateTime _lastMonday = DateTime(2023, 12, 25);
final DateTime _lastThursday = DateTime(2023, 12, 28);

/// 조언·주 조회를 몇 번 받았는지 센다. 기록은 앱의 데모와 같은 로컬 목업
/// API(빈 메모리 drift)가 든다(#2724). 오늘은 [_friday] 로 고정한다.
class _CountingRepository extends DioExerciseRepository {
  _CountingRepository() : super(demoExerciseDio(emptyDemoDatabase()));

  int adviceCalls = 0;
  final List<DateTime> weekCalls = <DateTime>[];

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) {
    adviceCalls++;
    return super.fetchAdvice(period);
  }

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) {
    weekCalls.add(weekStart);
    return super.fetchWeek(weekStart);
  }
}

ProviderContainer _container(ExerciseRepository repo) {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[exerciseRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

Future<ExerciseSession> _add(ExerciseRepository r, DateTime date) async =>
    (await r.addSessions(<ExerciseSessionDraft>[
      ExerciseSessionDraft(
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 200,
        date: date,
        name: '지난 주 걷기',
      ),
    ])).sessions.single;

bool _has(ExerciseWeek w, String? id) =>
    w.sessions.any((ExerciseSession s) => s.id == id);

void main() {
  // 로컬 목업 API 가 오늘을 시계로 정한다 — 지난 주·이번 주가 고정 금요일 기준이다.
  setUp(() => useFixedKstDate(_friday));

  group('대상 목록', () {
    test('다섯 경로가 함께 비울 것을 모두 담는다', () {
      final List<ProviderOrFamily> seen = <ProviderOrFamily>[];
      refreshAfterExerciseChange(seen.add);

      expect(
        seen,
        containsAll(<ProviderOrFamily>[
          exerciseWeekProvider,
          exercisePastWeekProvider,
          exerciseAdviceProvider,
          activityCalendarProvider,
          myStreakShieldsProvider,
          myHealthStateProvider,
          weeklyChallengeProvider,
          recordSpanProvider,
        ]),
      );
    });

    test('지난 주와 조언은 family 통째로 비운다 — 어느 주·기간이든 빠지지 않는다', () {
      final List<ProviderOrFamily> seen = <ProviderOrFamily>[];
      refreshAfterExerciseChange(seen.add);

      // 인자 하나가 아니라 family 자체다. 수정은 옛 주와 새 주가 다를 수 있다.
      expect(seen, contains(same(exercisePastWeekProvider)));
      expect(seen, contains(same(exerciseAdviceProvider)));
    });

    test('같은 대상을 두 번 비우지 않는다', () {
      final List<ProviderOrFamily> seen = <ProviderOrFamily>[];
      refreshAfterExerciseChange(seen.add);
      expect(seen.toSet().length, seen.length);
    });
  });

  group('지난 주 캐시 (#2629)', () {
    test('지난 주 날짜로 적은 기록이 갱신 뒤 그 주 조회에 보인다', () async {
      final _CountingRepository repo = _CountingRepository();
      final ProviderContainer c = _container(repo);
      final ProviderSubscription<AsyncValue<ExerciseWeek>> sub = c.listen(
        exercisePastWeekProvider(_lastMonday),
        (_, _) {},
      );
      addTearDown(sub.close);
      final ExerciseWeek before = await c.read(
        exercisePastWeekProvider(_lastMonday).future,
      );

      final ExerciseSession added = await _add(repo, _lastThursday);
      // 갱신 전에는 캐시가 옛 주를 들고 있다 — 이것이 버그의 모양이다.
      expect(
        _has(
          await c.read(exercisePastWeekProvider(_lastMonday).future),
          added.id,
        ),
        isFalse,
      );

      refreshAfterExerciseChange(c.invalidate);
      final ExerciseWeek after = await c.read(
        exercisePastWeekProvider(_lastMonday).future,
      );
      expect(_has(after, added.id), isTrue);
      expect(after.sessions.length, before.sessions.length + 1);
    });

    test('기록을 다른 주로 옮기면 옛 주와 새 주가 모두 새로 읽힌다', () async {
      final _CountingRepository repo = _CountingRepository();
      final ProviderContainer c = _container(repo);
      final DateTime twoWeeksMonday = DateTime(2023, 12, 18);
      for (final DateTime monday in <DateTime>[_lastMonday, twoWeeksMonday]) {
        final ProviderSubscription<AsyncValue<ExerciseWeek>> sub = c.listen(
          exercisePastWeekProvider(monday),
          (_, _) {},
        );
        addTearDown(sub.close);
      }
      final ExerciseSession added = await _add(repo, _lastThursday);
      refreshAfterExerciseChange(c.invalidate);
      expect(
        _has(
          await c.read(exercisePastWeekProvider(_lastMonday).future),
          added.id,
        ),
        isTrue,
      );

      await repo.updateSession(
        id: added.id!,
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 200,
        date: DateTime(2023, 12, 20),
        name: '지난 주 걷기',
      );
      refreshAfterExerciseChange(c.invalidate);

      expect(
        _has(
          await c.read(exercisePastWeekProvider(_lastMonday).future),
          added.id,
        ),
        isFalse,
        reason: '옛 주에서 빠져야 한다',
      );
      expect(
        _has(
          await c.read(exercisePastWeekProvider(twoWeeksMonday).future),
          added.id,
        ),
        isTrue,
        reason: '새 주에 들어와야 한다',
      );
    });

    test('이번 주로 옮긴 기록은 이번 주에 보이고 지난 주에서 빠진다', () async {
      final _CountingRepository repo = _CountingRepository();
      final ProviderContainer c = _container(repo);
      final ProviderSubscription<AsyncValue<ExerciseWeek>> past = c.listen(
        exercisePastWeekProvider(_lastMonday),
        (_, _) {},
      );
      addTearDown(past.close);
      final ProviderSubscription<AsyncValue<ExerciseWeek>> current = c.listen(
        exerciseWeekProvider,
        (_, _) {},
      );
      addTearDown(current.close);
      final ExerciseSession added = await _add(repo, _lastThursday);
      await repo.updateSession(
        id: added.id!,
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 200,
        date: _thisMonday,
        name: '지난 주 걷기',
      );

      refreshAfterExerciseChange(c.invalidate);

      expect(_has(await c.read(exerciseWeekProvider.future), added.id), isTrue);
      expect(
        _has(
          await c.read(exercisePastWeekProvider(_lastMonday).future),
          added.id,
        ),
        isFalse,
      );
    });

    test('보고 있지 않은 주는 갱신 때 바로 요청하지 않는다', () async {
      final _CountingRepository repo = _CountingRepository();
      final ProviderContainer c = _container(repo);
      final ProviderSubscription<AsyncValue<ExerciseWeek>> sub = c.listen(
        exercisePastWeekProvider(_lastMonday),
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(exercisePastWeekProvider(_lastMonday).future);
      final int before = repo.weekCalls.length;

      refreshAfterExerciseChange(c.invalidate);
      await c.read(exercisePastWeekProvider(_lastMonday).future);

      // 보고 있던 한 주만 다시 읽는다.
      expect(repo.weekCalls.length, before + 1);
      expect(repo.weekCalls.last, _lastMonday);
    });
  });

  group('AI 맞춤 조언 (#2631)', () {
    test('갱신하면 보고 있던 기간의 조언을 다시 받는다', () async {
      final _CountingRepository repo = _CountingRepository();
      final ProviderContainer c = _container(repo);
      final ProviderSubscription<AsyncValue<ExerciseAdvice>> sub = c.listen(
        exerciseAdviceProvider('today'),
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(exerciseAdviceProvider('today').future);
      expect(repo.adviceCalls, 1);

      refreshAfterExerciseChange(c.invalidate);
      await c.read(exerciseAdviceProvider('today').future);

      expect(repo.adviceCalls, 2);
    });

    test('오늘 운동을 적고 갱신하면 오늘 조언 문장이 바뀐다', () async {
      final _CountingRepository repo = _CountingRepository();
      final ProviderContainer c = _container(repo);
      final ProviderSubscription<AsyncValue<ExerciseAdvice>> sub = c.listen(
        exerciseAdviceProvider('today'),
        (_, _) {},
      );
      addTearDown(sub.close);
      final String before = (await c.read(
        exerciseAdviceProvider('today').future,
      )).message;

      await _add(repo, _friday);
      refreshAfterExerciseChange(c.invalidate);

      final String after = (await c.read(
        exerciseAdviceProvider('today').future,
      )).message;
      expect(after, isNot(before));
    });

    test('기간마다 선 조언이 모두 비워진다', () async {
      final _CountingRepository repo = _CountingRepository();
      final ProviderContainer c = _container(repo);
      for (final String period in <String>['today', 'week', 'all']) {
        final ProviderSubscription<AsyncValue<ExerciseAdvice>> sub = c.listen(
          exerciseAdviceProvider(period),
          (_, _) {},
        );
        addTearDown(sub.close);
        await c.read(exerciseAdviceProvider(period).future);
      }
      expect(repo.adviceCalls, 3);

      refreshAfterExerciseChange(c.invalidate);
      for (final String period in <String>['today', 'week', 'all']) {
        await c.read(exerciseAdviceProvider(period).future);
      }

      expect(repo.adviceCalls, 6);
    });
  });
}

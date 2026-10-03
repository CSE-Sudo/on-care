import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/day_fetch_failed_line.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/pump_app.dart';

/// 펼친 날의 끼니·운동 조회가 실패하면 빈 날과 갈라 말하고 다시 읽게 한다. (#2892)
///
/// 예전에는 실패가 빈 결과와 같은 모양이라(합계만 남거나 빈 자리), 트레이너가
/// "이날은 끼니가 없다", "시간만 있고 운동이 없다" 로 읽었다.

Finder _byKeyPrefix(String prefix) => find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

void _useTallSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 2400);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _LoadFailed implements Exception {
  const _LoadFailed();
}

const ClientDietEntry _breakfast = ClientDietEntry(
  id: 'retry-breakfast',
  meal: '아침',
  items: '오트밀',
  calories: 300,
  sodiumMg: 10,
  carbsG: 50,
  proteinG: 10,
  fatG: 5,
);

/// 이력이 있는 오늘 + 처음 [failures] 번은 실패하는 날짜별 운동 조회.
class _FlakyExercisesRepository extends DriftClientRepository {
  _FlakyExercisesRepository(
    super.db, {
    required this.failures,
    required this.withHistory,
  });

  int failures;
  final bool withHistory;
  int calls = 0;

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) =>
      Stream<List<RoutineHistoryEntry>>.value(<RoutineHistoryEntry>[
        if (withHistory)
          RoutineHistoryEntry(
            id: 'flaky-hist-today',
            dateLabel: '',
            completedAt: nowKst(),
            label: 'PT 세션 · 트레이너 지도',
            completionRate: 100,
            exercises: const <ClientExerciseItem>[
              ClientExerciseItem(
                name: '데드리프트',
                type: 'strength',
                sets: 4,
                reps: 8,
              ),
            ],
            clientFeedback: '',
            trainerNote: '',
          ),
      ]);

  @override
  Future<List<ClientExerciseItem>> fetchExercisesOn(
    String clientId,
    DateTime date,
  ) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw const _LoadFailed();
    }
    return const <ClientExerciseItem>[
      ClientExerciseItem(
        name: '러닝',
        type: 'cardio',
        minutes: 30,
        source: 'member',
      ),
    ];
  }
}

/// 오늘 운동 30분이 있는 하루 — 이력이 없는 날에도 펼친 자리가 선다.
Override _todayWorkedOut() => clientExercisePeriodProvider.overrideWith(
  (ref, key) async => ClientExercisePeriod(
    range: (from: todayKst(), to: todayKst()),
    days: <ClientExerciseDay>[
      ClientExerciseDay(date: todayKst(), minutes: 30, calories: 200),
    ],
  ),
);

void main() {
  group('식단 — 펼친 날의 끼니', () {
    Future<void> openFirstDay(
      WidgetTester tester, {
      required Future<List<ClientDietEntry>> Function() load,
    }) async {
      _useTallSurface(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
        extraOverrides: <Override>[
          clientDietOnProvider.overrideWith((ref, key) => load()),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('client-period-toggle')),
          matching: find.text('이번 주'),
        ),
      );
      await tester.pumpAndSettle();
      final Finder records = find.byKey(
        const ValueKey<String>('diet-daily-records'),
      );
      await tester.ensureVisible(records);
      await tester.pumpAndSettle();
      final Finder openable = find.descendant(
        of: records,
        matching: find.byIcon(AppIcons.expandMore),
      );
      await tester.tap(
        find.ancestor(of: openable.first, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('실패하면 합계 줄 아래 실패 안내와 다시 시도가 선다', (tester) async {
      await openFirstDay(tester, load: () async => throw const _LoadFailed());

      final Finder failed = _byKeyPrefix('client-diet-day-failed-');
      expect(_byKeyPrefix('client-diet-day-total-'), findsOneWidget);
      expect(failed, findsOneWidget);
      expect(
        find.descendant(of: failed, matching: find.text('끼니 기록을 불러오지 못했어요')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: failed, matching: find.text('다시 시도')),
        findsOneWidget,
      );
      // 합계 줄이 위, 실패 줄이 아래다.
      expect(
        tester.getTopLeft(failed).dy,
        greaterThan(
          tester.getTopLeft(_byKeyPrefix('client-diet-day-total-')).dy,
        ),
      );
    });

    testWidgets('다시 시도하면 그날 끼니가 그려진다', (tester) async {
      var calls = 0;
      await openFirstDay(
        tester,
        load: () async {
          calls++;
          if (calls == 1) throw const _LoadFailed();
          return const <ClientDietEntry>[_breakfast];
        },
      );
      final Finder failed = _byKeyPrefix('client-diet-day-failed-');
      expect(failed, findsOneWidget);

      await tester.tap(
        find.descendant(of: failed, matching: find.text('다시 시도')),
      );
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(_byKeyPrefix('client-diet-day-failed-'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('diet-day-meal-retry-breakfast')),
        findsOneWidget,
      );
    });

    testWidgets('끼니가 정말 없는 날은 아무 안내도 없다', (tester) async {
      await openFirstDay(tester, load: () async => const <ClientDietEntry>[]);

      expect(_byKeyPrefix('client-diet-day-total-'), findsOneWidget);
      expect(_byKeyPrefix('client-diet-day-failed-'), findsNothing);
      expect(find.byType(DayFetchFailedLine), findsNothing);
    });

    testWidgets('정상 경로는 그대로 끼니를 그린다', (tester) async {
      await openFirstDay(
        tester,
        load: () async => const <ClientDietEntry>[_breakfast],
      );

      expect(
        find.byKey(const ValueKey<String>('diet-day-meal-retry-breakfast')),
        findsOneWidget,
      );
      expect(find.byType(DayFetchFailedLine), findsNothing);
    });
  });

  group('운동 — 펼친 날의 운동', () {
    Future<_FlakyExercisesRepository> openToday(
      WidgetTester tester, {
      required int failures,
      required bool withHistory,
    }) async {
      _useTallSurface(tester);
      late _FlakyExercisesRepository repository;
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith(
            (ref) => repository = _FlakyExercisesRepository(
              ref.watch(appDatabaseProvider),
              failures: failures,
              withHistory: withHistory,
            ),
          ),
          if (!withHistory) _todayWorkedOut(),
        ],
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('이력 있는 날 — 이력 카드는 남고 실패 안내가 선다', (tester) async {
      await openToday(tester, failures: 1 << 20, withHistory: true);
      final String today = ymd(todayKst());

      expect(
        find.byKey(
          const ValueKey<String>('workout-exercise-line-flaky-hist-today-0'),
        ),
        findsOneWidget,
      );
      final Finder failed = find.byKey(
        ValueKey<String>('workout-day-failed-$today'),
      );
      expect(failed, findsOneWidget);
      expect(
        find.descendant(of: failed, matching: find.text('운동 기록을 불러오지 못했어요')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('workout-member-log-$today')),
        findsNothing,
      );
    });

    testWidgets('이력 있는 날 — 다시 시도하면 직접 기록이 선다', (tester) async {
      final repository = await openToday(
        tester,
        failures: 1,
        withHistory: true,
      );
      final String today = ymd(todayKst());
      final Finder failed = find.byKey(
        ValueKey<String>('workout-day-failed-$today'),
      );
      expect(failed, findsOneWidget);

      await tester.tap(
        find.descendant(of: failed, matching: find.text('다시 시도')),
      );
      await tester.pumpAndSettle();

      expect(repository.calls, greaterThanOrEqualTo(2));
      expect(failed, findsNothing);
      expect(
        find.byKey(ValueKey<String>('workout-member-log-$today')),
        findsOneWidget,
      );
    });

    testWidgets('이력 없는 날 — 빈 자리 대신 실패 안내가 선다', (tester) async {
      await openToday(tester, failures: 1 << 20, withHistory: false);
      final String today = ymd(todayKst());

      expect(
        find.byKey(ValueKey<String>('workout-day-failed-$today')),
        findsOneWidget,
      );
      expect(_byKeyPrefix('workout-exercise-line-$today'), findsNothing);
    });

    testWidgets('이력 없는 날 — 다시 시도하면 운동 이름이 그려진다', (tester) async {
      await openToday(tester, failures: 1, withHistory: false);
      final String today = ymd(todayKst());
      final Finder failed = find.byKey(
        ValueKey<String>('workout-day-failed-$today'),
      );
      expect(failed, findsOneWidget);

      await tester.tap(
        find.descendant(of: failed, matching: find.text('다시 시도')),
      );
      await tester.pumpAndSettle();

      expect(failed, findsNothing);
      expect(
        find.byKey(ValueKey<String>('workout-exercise-line-$today-0')),
        findsOneWidget,
      );
    });

    testWidgets('조회가 성공하면 실패 안내 없이 직접 기록이 선다', (tester) async {
      await openToday(tester, failures: 0, withHistory: true);

      expect(find.byType(DayFetchFailedLine), findsNothing);
      expect(
        find.byKey(ValueKey<String>('workout-member-log-${ymd(todayKst())}')),
        findsOneWidget,
      );
    });
  });
}

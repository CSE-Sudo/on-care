/// 대시보드 `오늘 일정` 이 시계를 따라 갱신된다. (#2865)
///
/// - 남은 시간은 분이 지날 때마다 다시 그려진다.
/// - 끝난 `예정` 수업은 배너에서 물러나고 다음 수업이 나온다.
/// - 자정을 넘기면 새 날짜의 일정을 다시 구독한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/kst_clock_provider.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

ScheduleSession _session(
  String id,
  String time, {
  String date = '2026-08-20',
  String name = '회원',
}) => ScheduleSession(
  id: id,
  date: date,
  time: time,
  clientName: name,
  type: SessionType.personalTraining,
  durationMinutes: 50,
  status: ScheduleStatus.upcoming,
  note: '',
  program: const <ProgramItem>[],
);

void main() {
  group('todayScheduleProvider', () {
    late StreamController<DateTime> clock;
    late _MockScheduleRepository repo;
    late ProviderContainer container;

    setUp(() {
      clock = StreamController<DateTime>.broadcast();
      repo = _MockScheduleRepository();
      when(() => repo.watchDate(any())).thenAnswer((Invocation inv) {
        final String date = inv.positionalArguments.single as String;
        return Stream<List<ScheduleSession>>.value(<ScheduleSession>[
          _session('s-$date', '10:00', date: date),
        ]);
      });
      container = ProviderContainer(
        overrides: <Override>[
          kstClockProvider.overrideWith((ref) => clock.stream),
          scheduleRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(clock.close);
    });

    test('자정을 넘기면 새 날짜의 일정을 구독한다', () async {
      useFixedKstDate(DateTime(2026, 8, 20, 23, 59));
      container.listen(todayScheduleProvider, (_, _) {});
      clock.add(DateTime(2026, 8, 20, 23, 59));
      final List<ScheduleSession> before = await container.read(
        todayScheduleProvider.future,
      );
      expect(before.single.date, '2026-08-20');

      clock.add(DateTime(2026, 8, 21));
      await Future<void>.delayed(Duration.zero);
      final List<ScheduleSession> after = await container.read(
        todayScheduleProvider.future,
      );

      expect(after.single.date, '2026-08-21');
      verify(() => repo.watchDate('2026-08-21')).called(1);
    });

    test('같은 날 안에서 분이 지나도 다시 구독하지 않는다', () async {
      useFixedKstDate(DateTime(2026, 8, 20, 13));
      container.listen(todayScheduleProvider, (_, _) {});
      clock.add(DateTime(2026, 8, 20, 13));
      await container.read(todayScheduleProvider.future);
      clock.add(DateTime(2026, 8, 20, 13, 1));
      clock.add(DateTime(2026, 8, 20, 13, 2));
      await Future<void>.delayed(Duration.zero);

      verify(() => repo.watchDate('2026-08-20')).called(1);
    });
  });

  group('TodayTimelineCard', () {
    late StreamController<DateTime> clock;

    setUp(() {
      clock = StreamController<DateTime>.broadcast();
      addTearDown(clock.close);
    });

    Future<void> openDashboard(
      WidgetTester tester, {
      required Stream<List<ScheduleSession>> Function(String date) sessionsOn,
    }) async {
      useFixedKstDate(DateTime(2026, 8, 20, 13));
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.dashboard,
        kstClock: clock.stream,
        extraOverrides: <Override>[
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(const <TrainerClient>[]),
          ),
          todayScheduleProvider.overrideWith(
            (ref) => sessionsOn(ref.watch(kstTodayProvider)),
          ),
        ],
      );
      await settle(tester);
    }

    Future<void> tick(WidgetTester tester, DateTime at) async {
      clock.add(at);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('분이 지나면 남은 시간이 다시 그려진다', (tester) async {
      await openDashboard(
        tester,
        sessionsOn: (date) => Stream<List<ScheduleSession>>.value(
          <ScheduleSession>[_session('pt', '15:00', date: date)],
        ),
      );
      await tick(tester, DateTime(2026, 8, 20, 13));
      expect(find.textContaining('120분 뒤'), findsOneWidget);

      await tick(tester, DateTime(2026, 8, 20, 13, 1));
      expect(find.textContaining('119분 뒤'), findsOneWidget);
      expect(find.textContaining('지금 13:01'), findsOneWidget);
    });

    testWidgets('끝난 예정 수업 대신 다음 수업을 가리킨다', (tester) async {
      await openDashboard(
        tester,
        sessionsOn: (date) =>
            Stream<List<ScheduleSession>>.value(<ScheduleSession>[
              _session('morning', '10:00', date: date, name: '오전회원'),
              _session('evening', '17:00', date: date, name: '저녁회원'),
            ]),
      );
      await tick(tester, DateTime(2026, 8, 20, 13));

      expect(find.textContaining('다음 일정 17:00 · 저녁회원'), findsOneWidget);
      expect(find.textContaining('10:00 · 오전회원'), findsNothing);
    });

    testWidgets('진행 중인 수업은 진행 중과 끝까지 남은 분으로 적는다', (tester) async {
      await openDashboard(
        tester,
        sessionsOn: (date) => Stream<List<ScheduleSession>>.value(
          <ScheduleSession>[_session('now', '12:30', date: date, name: '수업회원')],
        ),
      );
      await tick(tester, DateTime(2026, 8, 20, 13));

      expect(find.textContaining('진행 중 12:30 · 수업회원'), findsOneWidget);
      expect(find.textContaining('20분 남음'), findsOneWidget);
    });

    testWidgets('수업이 끝나는 분이 오면 배너가 물러난다', (tester) async {
      await openDashboard(
        tester,
        sessionsOn: (date) => Stream<List<ScheduleSession>>.value(
          <ScheduleSession>[_session('last', '12:30', date: date)],
        ),
      );
      await tick(tester, DateTime(2026, 8, 20, 13, 19));
      expect(
        find.byKey(const ValueKey<String>('dashboard-next-session-cta')),
        findsOneWidget,
      );

      await tick(tester, DateTime(2026, 8, 20, 13, 20));
      expect(
        find.byKey(const ValueKey<String>('dashboard-next-session-cta')),
        findsNothing,
      );
      // 목록 줄은 그대로 남는다 — 완료 처리는 스케줄에서 한다.
      expect(
        find.byKey(const ValueKey<String>('dashboard-schedule-last')),
        findsOneWidget,
      );
    });

    testWidgets('자정을 넘기면 새 날짜의 일정으로 바뀐다', (tester) async {
      final List<String> asked = <String>[];
      await openDashboard(
        tester,
        sessionsOn: (date) {
          asked.add(date);
          return Stream<List<ScheduleSession>>.value(<ScheduleSession>[
            _session('s-$date', '10:00', date: date),
          ]);
        },
      );
      await tick(tester, DateTime(2026, 8, 20, 23, 59));
      expect(
        find.byKey(const ValueKey<String>('dashboard-schedule-s-2026-08-20')),
        findsOneWidget,
      );

      await tick(tester, DateTime(2026, 8, 21));
      await settle(tester);

      expect(asked.last, '2026-08-21');
      expect(
        find.byKey(const ValueKey<String>('dashboard-schedule-s-2026-08-21')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('dashboard-schedule-s-2026-08-20')),
        findsNothing,
      );
    });
  });
}

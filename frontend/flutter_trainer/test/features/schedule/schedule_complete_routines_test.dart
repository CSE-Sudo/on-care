// PT 완료·취소 때의 개인운동 (#2224).
//
// 완료는 개인운동이 회원에게 가는 **유일한 순간**이다. 붙은 것이 없으면
// 완료를 막고 프로그램 탭에서 짜도록 돌려보낸다 — 그대로 완료하면 그 PT 의
// 개인운동은 영영 가지 않는다.
//
// 취소·노쇼로 끝난 PT 의 개인운동은 저절로 가지 않는다. 아파서 쉬는 회원에게
// 운동이 자동으로 가면 안 되기 때문이고, 트레이너가 `개인운동 미전송` 에서
// 고쳐 보내거나 보내지 않기로 정리한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 데모 저장소 위에 개인운동만 얹는다 — 나머지 동작은 그대로 쓴다.
class _RoutineAwareRepository extends DriftScheduleRepository {
  _RoutineAwareRepository(super.db, {required this.attached});

  final List<RoutineExercise> attached;
  List<RoutineExercise> sentItems = const <RoutineExercise>[];
  int sends = 0;
  int dismissals = 0;
  bool _cleared = false;

  @override
  Future<List<RoutineExercise>> fetchScheduledRoutines(String id) async =>
      _cleared ? const <RoutineExercise>[] : attached;

  @override
  Future<void> sendScheduledRoutines(
    String id, {
    List<RoutineExercise>? items,
  }) async {
    sends++;
    sentItems = items ?? attached;
    _cleared = true;
  }

  @override
  Future<void> dismissScheduledRoutines(String id) async {
    dismissals++;
    _cleared = true;
  }
}

void main() {
  group('PT 완료와 개인운동 (#2224)', () {
    late _RoutineAwareRepository repo;

    Future<void> openSchedule(
      WidgetTester tester, {
      required List<RoutineExercise> attached,
    }) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        seedClock: kMidWeekKst,
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith((ref) {
            repo = _RoutineAwareRepository(
              ref.watch(appDatabaseProvider),
              attached: attached,
            );
            return repo;
          }),
        ],
      );
    }

    Future<void> openSession(WidgetTester tester, String name) async {
      final block = find
          .descendant(
            of: find.byType(ScheduleWeekTimetable),
            matching: find.textContaining(name),
          )
          .first;
      await tester.ensureVisible(block);
      await tester.pump();
      await tester.tap(block);
      await settle(tester);
    }

    Future<void> revealInPanel(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('week-detail')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
    }

    const walking = RoutineExercise(
      name: '저강도 걷기',
      minutes: 30,
      type: '유산소',
    );

    testWidgets('완료 확인창이 함께 갈 개인운동을 보여 준다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      await openSession(tester, '박성호');

      final complete = find.byKey(
        const ValueKey<String>('session-complete-chip'),
      );
      await revealInPanel(tester, complete);
      await tester.tap(complete);
      await settle(tester);

      // 무엇이 함께 가는지 보고 누른다 — 완료가 유일한 전송 순간이다.
      expect(find.text('함께 보낼 개인운동'), findsOneWidget);
      expect(find.textContaining('저강도 걷기'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('session-complete-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('붙은 개인운동이 없으면 완료를 막고 프로그램 탭으로 보낸다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[]);
      await openSession(tester, '박성호');

      final complete = find.byKey(
        const ValueKey<String>('session-complete-chip'),
      );
      await revealInPanel(tester, complete);
      await tester.tap(complete);
      await settle(tester);

      // 완료 버튼이 선 확인창이 아니라 "먼저 짜라" 는 안내가 뜬다.
      expect(
        find.byKey(const ValueKey<String>('session-complete-needs-routines')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-complete-confirm')),
        findsNothing,
      );
      expect(find.textContaining('프로그램 탭'), findsOneWidget);
    });

    testWidgets('마무리된 PT 는 개인운동 미전송을 남기고 거기서 보낸다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      await openSession(tester, '이지수');

      final unsent = find.byKey(
        const ValueKey<String>('session-unsent-routines'),
      );
      await revealInPanel(tester, unsent);
      expect(find.text('개인운동 미전송'), findsOneWidget);

      final send = find.byKey(const ValueKey<String>('session-routines-send'));
      await revealInPanel(tester, send);
      await tester.tap(send);
      await settle(tester);

      // 보내기 전에 구성을 고칠 수 있다 — PT 가 열리지 않아 전제가 깨졌다.
      expect(
        find.byKey(const ValueKey<String>('session-routines-send-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await settle(tester);

      expect(repo.sends, 1);
      expect(repo.sentItems.single.name, '저강도 걷기');
      // 보내고 나면 표시가 사라진다.
      expect(unsent, findsNothing);
    });

    testWidgets('보내지 않음을 누르면 표시가 사라진다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      await openSession(tester, '이지수');

      final skip = find.byKey(const ValueKey<String>('session-routines-skip'));
      await revealInPanel(tester, skip);
      await tester.tap(skip);
      await settle(tester);

      expect(repo.dismissals, 1);
      expect(repo.sends, 0);
      expect(
        find.byKey(const ValueKey<String>('session-unsent-routines')),
        findsNothing,
      );
    });
  });
}

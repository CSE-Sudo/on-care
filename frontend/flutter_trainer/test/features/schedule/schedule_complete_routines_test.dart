// 일정 상세의 개인운동 (#2224).
//
// 상세 카드는 `PT 프로그램` 과 `개인운동` 을 갈라 보여 준다. 개인운동은 PT
// 프로그램을 보낼 때 **함께** 나가므로 보내는 버튼을 따로 두지 않는다 —
// 취소·노쇼로 끝나 보낼 프로그램이 없을 때만 그 자리가 `개인운동 보내기` 가
// 된다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_ui/oncare_ui.dart';

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

    /// 예정 PT 를 취소 처리해 "보낼 프로그램이 없는" 상태로 만든다.
    Future<void> cancelSession(WidgetTester tester) async {
      final chip = find.byKey(const ValueKey<String>('session-cancel-chip'));
      await revealInPanel(tester, chip);
      await tester.tap(chip);
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('cancel-source-member')),
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-cancel-confirm')),
      );
      await settle(tester);
    }

    const walking = RoutineExercise(
      name: '저강도 걷기',
      minutes: 30,
      type: '유산소',
    );

    testWidgets('상세 카드가 PT 프로그램과 개인운동을 갈라 보여 준다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      await openSession(tester, '박성호');

      // 한 카드 안에서 "여기서 할 것" 과 "혼자 할 것" 이 갈린다.
      expect(find.text('PT 프로그램'), findsOneWidget);
      expect(find.text('개인운동'), findsOneWidget);
      expect(find.textContaining('저강도 걷기'), findsWidgets);
      // 예정인 PT 는 보낼 것이 없다 — 프로그램을 보낼 때 함께 나간다.
      expect(find.textContaining('프로그램을 보낼 때'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('session-routines-send')),
        findsNothing,
      );

      // 완료는 기록만 남긴다 — 확인창이 개인운동을 늘어놓지 않는다.
      final complete = find.byKey(
        const ValueKey<String>('session-complete-chip'),
      );
      await revealInPanel(tester, complete);
      await tester.tap(complete);
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('session-complete-confirm')),
        findsOneWidget,
      );
      // 뒤에 선 카드에는 그대로 있고, **확인창 안**에는 없다.
      expect(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.textContaining('저강도 걷기'),
        ),
        findsNothing,
      );
    });

    testWidgets('취소·노쇼는 그 자리가 개인운동 보내기가 된다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      await openSession(tester, '박성호');
      await cancelSession(tester);

      final unsent = find.byKey(
        const ValueKey<String>('session-personal-routines'),
      );
      await revealInPanel(tester, unsent);
      // 아직 남아 있다는 사실은 버튼이 말한다 — 따로 태그를 두지 않는다.
      expect(find.text('개인운동'), findsOneWidget);

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
      await openSession(tester, '박성호');
      await cancelSession(tester);

      final skip = find.byKey(const ValueKey<String>('session-routines-skip'));
      await revealInPanel(tester, skip);
      await tester.tap(skip);
      await settle(tester);

      expect(repo.dismissals, 1);
      expect(repo.sends, 0);
      expect(
        find.byKey(const ValueKey<String>('session-personal-routines')),
        findsNothing,
      );
    });
  });
}

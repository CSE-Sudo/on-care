// 개인운동이 없는 PT 를 일정 상세에서 구제한다 (#2280).
//
// `직접 만들기`·저장한 프로그램 적용으로 짠 PT 는 개인운동 단계를 지나지 않아
// 개인운동 없이 스케줄에 선다. 일정 상세가 `개인운동 없음` 을 보여 주고 연필
// 메뉴의 `개인운동 추가` 로 처음 붙이게 한다. 보내기 직전에도 한 번 붙잡는다 —
// 보낸 뒤에는 그 PT 에 개인운동을 붙일 수 없다.
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

/// 데모 저장소 위에 **비어 있는** 개인운동을 얹는다 — 붙이면 그대로 읽힌다.
class _NoRoutineRepository extends DriftScheduleRepository {
  _NoRoutineRepository(super.db);

  List<RoutineExercise> attached = const <RoutineExercise>[];
  final List<String> calls = <String>[];
  bool _sent = false;

  @override
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id) async =>
      <SessionRoutine>[
        for (final RoutineExercise e in attached)
          SessionRoutine(exercise: e, sent: _sent),
      ];

  @override
  Future<void> updateScheduledRoutines(
    String id,
    List<RoutineExercise> items,
  ) async {
    calls.add('update');
    attached = items;
  }

  @override
  Future<void> sendProgram(String id, {String? clientRequestId}) async {
    calls.add('send');
    await super.sendProgram(id, clientRequestId: clientRequestId);
    _sent = true;
  }
}

void main() {
  group('개인운동 없는 PT 구제 (#2280)', () {
    late _NoRoutineRepository repo;

    Future<void> openSchedule(WidgetTester tester) async {
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
            repo = _NoRoutineRepository(ref.watch(appDatabaseProvider));
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

    Future<void> openPencil(WidgetTester tester) async {
      final pencil = find.byKey(const ValueKey<String>('session-edit-menu'));
      await revealInPanel(tester, pencil);
      await tester.tap(pencil);
      await settle(tester);
    }

    /// 처음 붙이는 창에 운동 이름 하나를 적고 저장한다.
    Future<void> fillFirstRoutine(WidgetTester tester, String name) async {
      // 빈 줄 하나로 시작한다 — 붙은 것이 없는데 빈 창을 열면 무엇을 해야
      // 하는지부터 찾아야 한다.
      expect(find.text('개인운동 추가'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-routine-name-0')),
        name,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await settle(tester);
    }

    Future<void> completeSession(WidgetTester tester) async {
      final complete = find.byKey(
        const ValueKey<String>('session-complete-chip'),
      );
      await revealInPanel(tester, complete);
      await tester.tap(complete);
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-complete-confirm')),
      );
      await settle(tester);
    }

    Future<void> tapSendProgram(WidgetTester tester) async {
      final send = find.byKey(const ValueKey<String>('schedule-send-program'));
      await revealInPanel(tester, send);
      await tester.tap(send);
      await settle(tester);
    }

    testWidgets('개인운동이 없으면 개인운동 없음을 보여 주고 연필 메뉴에서 처음 붙인다', (tester) async {
      await openSchedule(tester);
      // 데모 씨앗의 예정 PT — 프로그램은 있지만 개인운동이 없다.
      await openSession(tester, '박성호');

      final empty = find.byKey(
        const ValueKey<String>('session-no-personal-routines'),
      );
      await revealInPanel(tester, empty);
      expect(empty, findsOneWidget);
      expect(find.text('개인운동 없음'), findsOneWidget);

      await openPencil(tester);
      // 붙은 것이 없는데 `수정` 이라고 부르지 않는다.
      expect(
        find.byKey(const ValueKey<String>('session-edit-routines-chip')),
        findsNothing,
      );
      final add = find.byKey(
        const ValueKey<String>('session-add-routines-chip'),
      );
      expect(add, findsOneWidget);
      await tester.tap(add);
      await settle(tester);

      await fillFirstRoutine(tester, '실내 자전거');

      expect(repo.calls, <String>['update']);
      expect(repo.attached.single.name, '실내 자전거');
      // 일정 상세에서 적은 것은 트레이너 것이다.
      expect(repo.attached.single.source, 'trainer');

      // 붙인 뒤에는 갈래가 서고, 같은 자리가 `개인운동 수정` 이 된다.
      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-personal-routines')),
      );
      expect(empty, findsNothing);
      expect(find.textContaining('실내 자전거'), findsOneWidget);
      await openPencil(tester);
      expect(
        find.byKey(const ValueKey<String>('session-edit-routines-chip')),
        findsOneWidget,
      );
      expect(add, findsNothing);
    });

    testWidgets('개인운동 없이 보내려 하면 한 번 묻고, 없이 전송을 골라야 보낸다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await completeSession(tester);

      await tapSendProgram(tester);
      expect(
        find.byKey(const ValueKey<String>('no-personal-routine-dialog')),
        findsOneWidget,
      );
      expect(find.text('개인운동 없이 보낼까요?'), findsOneWidget);
      // 창을 여는 것만으로는 보내지 않는다.
      expect(repo.calls, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('no-personal-routine-skip')),
      );
      await settle(tester);
      expect(repo.calls, <String>['send']);

      // 보낸 PT 에는 붙일 자리가 서지 않는다 — 보낸 뒤에 붙으면 회원이 받은
      // 목록이 말없이 달라진다.
      expect(
        find.byKey(const ValueKey<String>('session-no-personal-routines')),
        findsNothing,
      );
      await openPencil(tester);
      expect(
        find.byKey(const ValueKey<String>('session-add-routines-chip')),
        findsNothing,
      );
    });

    testWidgets('보내기 직전에 개인운동 추가를 고르면 붙인 뒤 이어서 보낸다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await completeSession(tester);

      await tapSendProgram(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('no-personal-routine-add')),
      );
      await settle(tester);
      await fillFirstRoutine(tester, '저강도 걷기');

      // 붙이고 나서 보낸다 — 개인운동이 그 전송에 실려 간다.
      expect(repo.calls, <String>['update', 'send']);
      expect(repo.attached.single.name, '저강도 걷기');
    });

    testWidgets('개인운동 추가 창을 닫으면 보내지 않는다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await completeSession(tester);

      await tapSendProgram(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('no-personal-routine-add')),
      );
      await settle(tester);
      // 붙이려던 트레이너의 PT 가 개인운동 없이 나가면 안 된다.
      await tester.tap(find.text('취소').last);
      await settle(tester);

      expect(repo.calls, isEmpty);
    });
  });
}

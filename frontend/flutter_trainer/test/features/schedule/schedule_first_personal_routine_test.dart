// 개인운동이 없는 PT 를 일정 상세에서 구제한다 (#2280).
//
// `직접 만들기`·저장한 프로그램 적용으로 짠 PT 는 개인운동 단계를 지나지 않아
// 개인운동 없이 스케줄에 선다. 일정 상세가 `개인운동 없음` 을 보여 주고, 그
// 박스의 추가 버튼이 코칭 탭의 개인운동 단계(AI 제안)로 보낸다 — 스케줄에서
// 빈 창으로 짜지 않는다. 보내기 직전에도 한 번 붙잡는다.
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

/// 데모 저장소 위에 **비어 있는** 개인운동을 얹는다.
class _NoRoutineRepository extends DriftScheduleRepository {
  _NoRoutineRepository(super.db);

  final List<String> calls = <String>[];

  @override
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id) async =>
      const <SessionRoutine>[];

  @override
  Future<void> updateScheduledRoutines(
    String id,
    List<RoutineExercise> items,
  ) async {
    calls.add('update');
  }

  @override
  Future<void> sendProgram(String id, {String? clientRequestId}) async {
    calls.add('send');
    await super.sendProgram(id, clientRequestId: clientRequestId);
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
        // 오늘 수업이 모두 시작한 뒤 — 완료·노쇼가 열린다(#2760).
        seedClock: kMidWeekEveningKst,
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

    /// 코칭 탭의 **붙이기 흐름**으로 왔는가 — 어느 회원의 어느 PT 인지까지.
    void expectAttachRoute(WidgetTester tester) {
      final Uri location = Uri.parse(currentLocation(tester));
      expect(location.path, AppRoutes.coaching);
      expect(location.queryParameters['client'], isNotEmpty);
      expect(location.queryParameters['attach'], isNotEmpty);
      expect(location.queryParameters['d'], isNotEmpty);
      // 누를 때마다 새 요청이다 — 같은 PT 를 다시 눌러도 흐름이 다시 열린다.
      expect(location.queryParameters['r'], isNotEmpty);
    }

    testWidgets('개인운동 없음 박스의 추가 버튼이 코칭 탭의 개인운동 단계로 보낸다', (tester) async {
      await openSchedule(tester);
      // 데모 씨앗의 예정 PT — 프로그램은 있지만 개인운동이 없다.
      await openSession(tester, '박성호');

      final empty = find.byKey(
        const ValueKey<String>('session-no-personal-routines'),
      );
      await revealInPanel(tester, empty);
      expect(find.text('개인운동 없음'), findsOneWidget);

      // 붙이는 버튼은 연필 메뉴가 아니라 이 박스 안에 있다.
      final pencil = find.byKey(const ValueKey<String>('session-edit-menu'));
      await revealInPanel(tester, pencil);
      await tester.tap(pencil);
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('session-edit-routines-chip')),
        findsNothing,
      );
      // 연필을 다시 눌러 메뉴를 닫는다.
      await tester.tap(pencil);
      await settle(tester);

      final add = find.byKey(const ValueKey<String>('session-add-routines'));
      await revealInPanel(tester, add);
      await tester.tap(add);
      await settle(tester);

      // 스케줄에서 빈 창을 열지 않는다 — AI 제안이 있는 코칭 탭으로 간다.
      expectAttachRoute(tester);
      expect(repo.calls, isEmpty);
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
    });

    testWidgets('보내기 직전에 개인운동 추가를 고르면 보내지 않고 코칭 탭으로 간다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await completeSession(tester);

      await tapSendProgram(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('no-personal-routine-add')),
      );
      await settle(tester);

      // 붙이기만 하러 간다 — 회원 전송은 돌아와서 트레이너가 다시 누른다.
      expectAttachRoute(tester);
      expect(repo.calls, isEmpty);
    });
  });
}

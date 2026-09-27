// 일정 상세의 개인운동 (#2224).
//
// 상세 카드는 `PT 프로그램` 과 `개인운동` 을 갈라 보여 준다. 개인운동은 PT
// 프로그램을 보낼 때 **함께** 나가므로 보내는 버튼을 따로 두지 않는다 —
// 취소·노쇼로 끝나 보낼 프로그램이 없을 때만 그 자리가 `개인운동 보내기` 가
// 된다.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 데모 저장소 위에 개인운동만 얹는다 — 나머지 동작은 그대로 쓴다.
class _RoutineAwareRepository extends DriftScheduleRepository {
  _RoutineAwareRepository(super.db, {required this.attached});

  final List<RoutineExercise> attached;
  List<RoutineExercise> sentItems = const <RoutineExercise>[];
  List<RoutineExercise> editedItems = const <RoutineExercise>[];
  int edits = 0;
  int sends = 0;
  int dismissals = 0;
  bool _sent = false;
  bool _dismissed = false;

  // 보낸 뒤에도 목록에는 남는다 — `sent` 로만 바뀐다(#2224). 보내지 않기로
  // 하면 그때는 아예 빠진다.
  @override
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id) async =>
      _dismissed
      ? const <SessionRoutine>[]
      : <SessionRoutine>[
          for (final RoutineExercise e in attached)
            SessionRoutine(exercise: e, sent: _sent),
        ];

  @override
  Future<void> sendScheduledRoutines(
    String id, {
    List<RoutineExercise>? items,
  }) async {
    sends++;
    sentItems = items ?? attached;
    _sent = true;
  }

  // 개인운동은 PT 프로그램 전송에 함께 실린다(#2224) — 데모 저장소가 그때
  // `programSent` 를 세우는 것과 같은 자리다.
  @override
  Future<void> sendProgram(String id, {String? clientRequestId}) async {
    await super.sendProgram(id, clientRequestId: clientRequestId);
    _sent = true;
  }

  @override
  Future<void> updateScheduledRoutines(
    String id,
    List<RoutineExercise> items,
  ) async {
    edits++;
    editedItems = items;
  }

  @override
  Future<void> dismissScheduledRoutines(String id) async {
    dismissals++;
    _dismissed = true;
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

    testWidgets('프로그램을 보내면 개인운동도 보낸 것이 된다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      // 데모 씨앗에서 이미 완료된, 프로그램이 붙은 PT.
      await openSession(tester, '박성호');
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

      final send = find.byKey(const ValueKey<String>('schedule-send-program'));
      await revealInPanel(tester, send);
      expect(find.textContaining('아직 회원에게'), findsOneWidget);
      await tester.tap(send);
      await settle(tester);

      // 개인운동도 이 전송에 실려 갔다 — 갈래가 그 사실을 말해야 한다.
      final routines = find.byKey(
        const ValueKey<String>('session-personal-routines'),
      );
      await revealInPanel(tester, routines);
      expect(find.text('전송됨'), findsOneWidget);
      expect(find.textContaining('아직 회원에게'), findsNothing);
    });

    testWidgets('연필 메뉴에서 개인운동을 바로 고친다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      await openSession(tester, '박성호');

      final pencil = find.byKey(const ValueKey<String>('session-edit-menu'));
      await revealInPanel(tester, pencil);
      await tester.tap(pencil);
      await settle(tester);

      final edit = find.byKey(
        const ValueKey<String>('session-edit-routines-chip'),
      );
      expect(edit, findsOneWidget);
      await tester.tap(edit);
      await settle(tester);

      // 보내는 창이 아니라 고치는 창이다 — 저장만 한다.
      expect(find.text('개인운동 수정'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-routine-name-0')),
        '실내 자전거',
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await settle(tester);

      expect(repo.edits, 1);
      expect(repo.sends, 0, reason: '고치기만 한다 — 회원에게 가지 않는다');
      expect(repo.editedItems.single.name, '실내 자전거');
    });

    testWidgets('수정 창에서 개인운동을 더할 수 있다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      await openSession(tester, '박성호');

      final pencil = find.byKey(const ValueKey<String>('session-edit-menu'));
      await revealInPanel(tester, pencil);
      await tester.tap(pencil);
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-edit-routines-chip')),
      );
      await settle(tester);

      final confirm = find.byKey(
        const ValueKey<String>('session-routines-send-confirm'),
      );
      await tester.tap(find.byKey(const ValueKey<String>('session-routine-add')));
      await settle(tester);

      // 이름이 빈 줄이 남아 있으면 저장할 수 없다 — 회원이 이름 없는 운동을
      // 받으면 안 된다.
      expect(tester.widget<AppButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey<String>('session-routine-name-1')),
        '실내 자전거',
      );
      await settle(tester);
      await tester.tap(confirm);
      await settle(tester);

      expect(repo.edits, 1);
      expect(
        repo.editedItems.map((e) => e.name).toList(),
        <String>['저강도 걷기', '실내 자전거'],
      );
    });

    testWidgets('이미 보낸 개인운동은 고칠 수 없다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      await openSession(tester, '박성호');
      await cancelSession(tester);

      final send = find.byKey(const ValueKey<String>('session-routines-send'));
      await revealInPanel(tester, send);
      await tester.tap(send);
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await settle(tester);

      final pencil = find.byKey(const ValueKey<String>('session-edit-menu'));
      await revealInPanel(tester, pencil);
      await tester.tap(pencil);
      await settle(tester);
      // 보낸 뒤에 바뀌면 회원이 어제 본 목록과 오늘 본 목록이 달라진다.
      expect(
        find.byKey(const ValueKey<String>('session-edit-routines-chip')),
        findsNothing,
      );
    });

    testWidgets('프로그램 없이 완료된 PT 도 개인운동을 보낼 수 있다', (tester) async {
      await openSchedule(tester, attached: const <RoutineExercise>[walking]);
      // 시드의 `완료 + 프로그램 없음` 인 PT — 스케줄에서 바로 잡아 프로그램
      // 없이 마친 경우다.
      await openSession(tester, '신유나');

      // 보낼 프로그램이 없으니 그 자리가 `개인운동 보내기` 가 된다 —
      // 예전에는 어느 조건에도 걸리지 않아 보낼 길이 아예 막혔다.
      final send = find.byKey(const ValueKey<String>('session-routines-send'));
      await revealInPanel(tester, send);
      expect(send, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('schedule-send-program')),
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
      // 보내고 나면 보내는 자리는 닫히지만 **목록은 남는다** — 무엇을 보냈는지
      // 나중에 볼 데가 여기뿐이다.
      await revealInPanel(tester, unsent);
      expect(unsent, findsOneWidget);
      expect(find.textContaining('저강도 걷기'), findsWidgets);
      expect(find.text('전송됨'), findsOneWidget);
      expect(send, findsNothing);
      expect(find.textContaining('프로그램을 보낼 때'), findsNothing);
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

  // 데모 저장소가 서버와 같은 규칙으로 가르는지 — 완료된 PT 는 프로그램과 함께
  // 개인운동도 나간 뒤이므로 **보낸 것으로** 남아야 한다(#2224).
  group('데모 저장소의 개인운동 (#2224)', () {
    late AppDatabase db;
    late DriftScheduleRepository repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
      repo = DriftScheduleRepository(db);
    });
    tearDown(() => db.close());

    /// 프로그램이 붙은 시드 일정 하나를 골라 전송 여부만 맞춰 둔다.
    ///
    /// 시드에는 이미 보낸 일정이 없다 — 보낸 상태는 여기서 만든다.
    Future<String> sessionId({required bool sent}) async {
      final rows = await db.select(db.trainerScheduleEntries).get();
      final String id = rows.firstWhere((r) => r.programJson.isNotEmpty).id;
      await (db.update(db.trainerScheduleEntries)
            ..where((t) => t.id.equals(id)))
          .write(TrainerScheduleEntriesCompanion(programSent: Value(sent)));
      return id;
    }

    test('프로그램을 보낸 PT 는 개인운동도 보낸 것으로 남는다', () async {
      final rows = await repo.fetchScheduledRoutines(
        await sessionId(sent: true),
      );
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r.sent), isTrue);
    });

    test('프로그램 탭에서 짠 개인운동이 그 PT 에 그대로 붙는다', () async {
      // 데모가 개인운동을 버리던 동안에는 스케줄 카드가 짠 것 대신 늘 같은
      // 데모 두 개를 보여 줘, 데모로 흐름을 확인할 수 없었다(#2224).
      const composed = <RoutineExercise>[
        RoutineExercise(name: '실내 자전거', minutes: 20, type: '유산소'),
      ];
      await repo.registerProgramSchedule(
        date: '2026-08-25',
        clientId: 'seed-client-1',
        clientName: '김민수',
        time: '11:00',
        durationMinutes: 50,
        assignment: const <String, Object?>{},
        program: const <ProgramItem>[ProgramItem(name: '스쿼트')],
        personalRoutines: composed,
      );
      final rows = await db.select(db.trainerScheduleEntries).get();
      final made = rows.firstWhere((r) => r.date == '2026-08-25');
      final attached = await repo.fetchScheduledRoutines(made.id);
      expect(attached.map((r) => r.exercise.name).toList(), <String>[
        '실내 자전거',
      ]);
      expect(attached.every((r) => r.sent), isFalse);
    });

    test('아직 보내지 않은 PT 는 개인운동도 보낼 것으로 남는다', () async {
      final rows = await repo.fetchScheduledRoutines(
        await sessionId(sent: false),
      );
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r.sent), isFalse);
    });
  });
}

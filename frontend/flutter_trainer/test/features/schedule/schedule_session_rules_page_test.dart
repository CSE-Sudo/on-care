/// 스케줄 화면의 세션 규칙 — 시작 전 PT 의 완료·노쇼(#2760)와 서버가 거절한
/// 사유 표시(#2754, #2756).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

const String _deleteReason = '예약으로 생성된 일정은 일반 일정 화면에서 삭제할 수 없습니다.';
const String _saveReason = '완료·취소·노쇼로 마무리된 PT는 피드백·프로그램만 수정할 수 있습니다.';

/// 서버처럼 사유를 담아 거절하는 저장소.
class _RejectingScheduleRepository extends DriftScheduleRepository {
  const _RejectingScheduleRepository(super.db);

  @override
  Future<void> deleteSession(String id) async =>
      throw const ServerError(statusCode: 409, message: _deleteReason);

  @override
  Future<void> updateProgram(
    String id, {
    required List<ProgramItem> program,
    required String note,
  }) async => throw const ServerError(statusCode: 409, message: _saveReason);
}

/// `updateSession` 에 무엇이 실렸는지 남기는 저장소. 실제 쓰기는 그대로 한다.
class _RecordingScheduleRepository extends DriftScheduleRepository {
  _RecordingScheduleRepository(super.db);

  final List<Map<String, Object?>> updates = <Map<String, Object?>>[];

  @override
  Future<void> updateSession(
    String id, {
    String? date,
    String? clientName,
    String? clientId,
    String? time,
    String? type,
    int? durationMinutes,
    String? note,
  }) {
    updates.add(<String, Object?>{
      'date': date,
      'clientName': clientName,
      'clientId': clientId,
      'time': time,
      'type': type,
      'durationMinutes': durationMinutes,
      'note': note,
    });
    return super.updateSession(
      id,
      date: date,
      clientName: clientName,
      clientId: clientId,
      time: time,
      type: type,
      durationMinutes: durationMinutes,
      note: note,
    );
  }
}

void main() {
  _RecordingScheduleRepository? recorder;

  Future<void> openSchedule(
    WidgetTester tester, {
    DateTime? clock,
    bool rejecting = false,
    bool recording = false,
  }) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.schedule,
      seedClock: clock ?? kMidWeekKst,
      extraOverrides: <Override>[
        if (rejecting)
          scheduleRepositoryProvider.overrideWith(
            (ref) =>
                _RejectingScheduleRepository(ref.watch(appDatabaseProvider)),
          ),
        if (recording)
          scheduleRepositoryProvider.overrideWith((ref) {
            final repo = _RecordingScheduleRepository(
              ref.watch(appDatabaseProvider),
            );
            recorder = repo;
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

  Future<void> openEditMenu(WidgetTester tester) async {
    final Finder trigger = find.byKey(
      const ValueKey<String>('session-edit-menu'),
    );
    await tester.ensureVisible(trigger);
    await tester.pump();
    await tester.tap(trigger);
    await settle(tester);
  }

  group('시작 전 오늘 PT (#2760)', () {
    testWidgets('시작 전이면 완료 버튼이 없고 취소 창에 노쇼도 없다', (tester) async {
      // 목요일 13:00 — 박성호 PT 는 오늘 16:00 이다.
      await openSchedule(tester);
      await openSession(tester, '박성호');

      expect(
        find.byKey(const ValueKey<String>('session-complete-chip')),
        findsNothing,
      );
      final cancel = find.byKey(const ValueKey<String>('session-cancel-chip'));
      await revealInPanel(tester, cancel);
      await tester.tap(cancel);
      await settle(tester);

      // 취소는 앞으로의 약속에도 열려 있다.
      expect(
        find.byKey(const ValueKey<String>('cancel-source-member')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('cancel-source-no-show')),
        findsNothing,
      );
    });

    testWidgets('시작 시각이 지나면 완료와 노쇼가 열린다', (tester) async {
      await openSchedule(tester, clock: kMidWeekEveningKst);
      await openSession(tester, '박성호');

      final complete = find.byKey(
        const ValueKey<String>('session-complete-chip'),
      );
      await revealInPanel(tester, complete);
      expect(complete, findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('session-cancel-chip')),
      );
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('cancel-source-no-show')),
        findsOneWidget,
      );
    });
  });

  group('서버가 거절한 사유 (#2754, #2756)', () {
    testWidgets('삭제 거절은 사유를 그대로 보인다', (tester) async {
      await openSchedule(tester, rejecting: true);
      await openSession(tester, '박성호');

      await openEditMenu(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-delete-chip')),
      );
      await settle(tester);
      await tester.tap(find.text('삭제').last); // 확인 창
      await settle(tester);

      expect(find.text(_deleteReason), findsOneWidget);
      expect(find.text('일정 삭제에 실패했어요. 다시 시도해 주세요'), findsNothing);
    });

    testWidgets('메모 저장 거절도 사유를 보인다', (tester) async {
      await openSchedule(tester, rejecting: true);
      await openSession(tester, '박성호');

      await openEditMenu(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-edit-note-chip')),
      );
      await settle(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey<String>('program-trainer-note')),
          matching: find.byType(EditableText),
        ),
        '폼 좋아짐',
      );
      await tester.tap(find.byKey(const ValueKey<String>('save-program')));
      await settle(tester);

      expect(find.text(_saveReason), findsOneWidget);
    });
  });

  group('일정 수정 시트는 바뀐 칸만 보낸다 (#2754)', () {
    Future<void> openEditSheet(WidgetTester tester) async {
      await openSchedule(tester, recording: true);
      await openSession(tester, '박성호');
      await openEditMenu(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
      );
      await settle(tester);
    }

    testWidgets('시각만 옮기면 시각·길이만 실린다', (tester) async {
      await openEditSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('session-time-range-field')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-time-range-start-input')),
        '21:00',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-time-range-end-input')),
        '22:00',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      final confirm = find.byKey(
        const ValueKey<String>('session-time-range-confirm'),
      );
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await settle(tester);

      await tester.tap(find.text('저장').last);
      await settle(tester);

      final update = recorder!.updates.single;
      expect(update['time'], '21:00');
      expect(update['durationMinutes'], 60);
      // 고르지 않은 칸은 '그대로' 다 — 실으면 마무리된 세션에서 거절된다.
      expect(update['clientName'], isNull);
      expect(update['clientId'], isNull);
      expect(update['type'], isNull);
      expect(update['note'], isNull);
      expect(update['date'], isNull);
    });

    testWidgets('아무것도 바꾸지 않은 저장은 요청하지 않는다', (tester) async {
      await openEditSheet(tester);

      await tester.tap(find.text('저장').last);
      await settle(tester);

      expect(recorder!.updates, isEmpty);
    });
  });
}

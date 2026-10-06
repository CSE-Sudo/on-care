/// 스케줄 화면의 요청을 보내는 창(일정·프로그램/메모)은 요청 중에 배경·뒤로
/// 가기로 닫히지 않는다(#3245). 닫히면 겹침 목록·서버 사유를 보여 줄 자리가
/// 사라진다. 기다리는 동안이 아니면 공용 기본값대로 배경을 눌러 닫는다.
/// 예약 가능 시간 창은 `reservation_slots_sheet_test.dart` 가 본다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_program_editor.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_sheet.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 저장 응답을 [gate] 가 끝날 때까지 붙잡는 저장소. 쓰지 않는 멤버는 [Fake]
/// 가 맡는다.
class _HeldScheduleRepository extends Fake implements ScheduleRepository {
  final Completer<void> gate = Completer<void>();
  final List<String> calls = <String>[];

  @override
  Future<void> addSession({
    required String date,
    required String clientName,
    String? clientId,
    required String time,
    required String type,
    required int durationMinutes,
    String note = '',
  }) async {
    calls.add('add:$clientId:$note');
    await gate.future;
  }

  @override
  Future<void> updateProgram(
    String id, {
    required List<ProgramItem> program,
    required String note,
  }) async {
    calls.add('program:$id:$note');
    await gate.future;
  }
}

ScheduleSession _session() => ScheduleSession(
  id: 'sched-1',
  date: ymd(addCalendarDays(todayKst(), 3)),
  time: '18:00',
  clientId: 'seed-client-1',
  clientName: '김민수',
  type: SessionType.personalTraining,
  durationMinutes: 50,
  status: ScheduleStatus.upcoming,
  note: '',
  program: const <ProgramItem>[],
);

Future<void> _open(
  WidgetTester tester,
  ScheduleRepository repo,
  Widget Function(BuildContext dialogContext) builder,
) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream.value(const <TrainerClient>[]),
        ),
        scheduleRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey<String>('open-dialog'),
              // 화면과 같은 길로 연다 — 공용 기본값(바깥 닫힘 허용)의 가운데 모달.
              onPressed: () =>
                  showAppDialog<void>(context: context, builder: builder),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey<String>('open-dialog')));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 창 바깥(배경)을 누른다.
Future<void> _tapOutside(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await _settle(tester);
}

Future<void> _typeNote(WidgetTester tester, String key, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(EditableText),
    ),
    text,
  );
  await tester.pump();
}

Widget _sheet(BuildContext _) => SessionSheet(
  title: '일정 추가',
  clients: const <({String id, String name})>[
    (id: 'seed-client-1', name: '김민수'),
  ],
  date: _session().date,
  existing: null,
);

Widget _noteEditor(BuildContext dialogContext) => SessionProgramEditor(
  title: '메모 수정',
  session: _session(),
  noteOnly: true,
  onSaved: () => Navigator.of(dialogContext).pop(),
  onCancel: () => Navigator.of(dialogContext).pop(),
);

void main() {
  group('일정 창', () {
    testWidgets('저장 중에는 배경을 눌러도 닫히지 않고, 끝나면 닫힌다', (tester) async {
      final _HeldScheduleRepository repo = _HeldScheduleRepository();
      await _open(tester, repo, _sheet);

      await _typeNote(tester, 'schedule-trainer-note', '하체 위주');
      await tester.tap(find.widgetWithText(AppButton, '추가'));
      await tester.pump();
      expect(repo.calls, <String>['add:seed-client-1:하체 위주']);

      await _tapOutside(tester);
      expect(find.byType(SessionSheet), findsOneWidget);

      repo.gate.complete();
      await _settle(tester);
      expect(find.byType(SessionSheet), findsNothing);
    });

    testWidgets('기다리는 요청이 없으면 배경을 눌러 닫는다', (tester) async {
      await _open(tester, _HeldScheduleRepository(), _sheet);

      await _tapOutside(tester);

      expect(find.byType(SessionSheet), findsNothing);
    });
  });

  group('메모 편집 창', () {
    testWidgets('저장 중에는 배경을 눌러도 닫히지 않고, 끝나면 닫힌다', (tester) async {
      final _HeldScheduleRepository repo = _HeldScheduleRepository();
      await _open(tester, repo, _noteEditor);

      await _typeNote(tester, 'program-trainer-note', '무릎 각도 확인');
      await tester.tap(find.byKey(const ValueKey<String>('save-program')));
      await tester.pump();
      expect(repo.calls, <String>['program:sched-1:무릎 각도 확인']);

      await _tapOutside(tester);
      expect(find.byType(SessionProgramEditor), findsOneWidget);

      repo.gate.complete();
      await _settle(tester);
      expect(find.byType(SessionProgramEditor), findsNothing);
    });

    testWidgets('기다리는 요청이 없으면 배경을 눌러 닫는다', (tester) async {
      await _open(tester, _HeldScheduleRepository(), _noteEditor);

      await _tapOutside(tester);

      expect(find.byType(SessionProgramEditor), findsNothing);
    });
  });
}

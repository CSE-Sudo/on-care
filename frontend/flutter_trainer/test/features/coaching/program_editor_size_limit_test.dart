// 편집기가 서버와 같은 프로그램 크기 상한을 지키는가. (#1583)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/action_button.dart';

ProgramEditorState _sized(int sessionCount, int exerciseCount) =>
    ProgramEditorState(
      name: '프로그램',
      sessions: <ProgramSessionDraft>[
        for (var s = 0; s < sessionCount; s++)
          ProgramSessionDraft(
            id: 'session-$s',
            name: '세션 $s',
            exercises: <ProgramExerciseDraft>[
              for (var e = 0; e < exerciseCount; e++)
                if (e % sessionCount == s)
                  ProgramExerciseDraft(id: 'exercise-$e', name: '운동 $e'),
            ],
          ),
      ],
    );

Future<void> _pump(WidgetTester tester, ProgramEditorState draft) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProgramEditorWorkspace(
            clientGoal: '체중 감량',
            aiSuggestions: const <AiRoutineItem>[],
            initialDraft: draft,
            onSend: (_) {},
            registerDate: DateTime(2026),
            onRegisterDateChanged: (_) {},
            registerStartTime: const TimeOfDay(hour: 10, minute: 0),
            registerEndTime: const TimeOfDay(hour: 11, minute: 0),
            onRegisterTimeRangeChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

VoidCallback? _onPressed(WidgetTester tester, Finder finder) =>
    tester.widget<ButtonStyleButton>(finder).onPressed;

void main() {
  final send = find.byKey(const ValueKey<String>('program-editor-send'));
  final addSession = find.byKey(
    const ValueKey<String>('program-editor-add-session'),
  );
  final addExercise = find.widgetWithText(ActionButton, '운동 추가');

  testWidgets('한도(12세션·30운동)에 닿으면 추가만 잠기고 일정 추가는 된다', (tester) async {
    await _pump(tester, _sized(12, 30));

    expect(_onPressed(tester, addSession), isNull);
    for (final button in tester.widgetList<ActionButton>(addExercise)) {
      expect(button.onPressed, isNull);
    }
    expect(tester.widget<ActionButton>(send).onPressed, isNotNull);
    expect(find.byKey(const ValueKey<String>('program-size-exceeded')), findsNothing);
  });

  testWidgets('한도를 넘으면 일정 추가가 잠기고 줄일 만큼을 안내한다', (tester) async {
    await _pump(tester, _sized(12, 31));

    expect(tester.widget<ActionButton>(send).onPressed, isNull);
    expect(
      find.text('세션 12/12개 · 운동 31/30개 — 한도를 넘은 만큼 줄여야 일정에 추가할 수 있어요'),
      findsOneWidget,
    );
  });
}

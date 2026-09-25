// `세션 추가` 가 유형 선택 메뉴로 열리는가. (#2222)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';

final Finder _addSession = find.byKey(
  const ValueKey<String>('program-editor-add-session'),
);

Future<void> _pump(WidgetTester tester) async {
  useFixedKstDate(DateTime(2026, 1, 1, 9));
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ko'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProgramEditorWorkspace(
            clientGoal: '체중 감량',
            aiSuggestions: const <AiRoutineItem>[],
            initialDraft: const ProgramEditorState(
              name: '프로그램',
              sessions: <ProgramSessionDraft>[
                ProgramSessionDraft(
                  id: 'session-1',
                  name: '세션 A',
                  exercises: <ProgramExerciseDraft>[],
                ),
              ],
            ),
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

/// `세션 추가` 를 눌러 [type] 을 고른다.
Future<void> _addSessionOfType(WidgetTester tester, String type) async {
  await tester.ensureVisible(_addSession);
  await tester.tap(_addSession);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey<String>('program-editor-session-type-$type')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('세션 추가는 유형 네 가지를 펼친다', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(_addSession);
    await tester.tap(_addSession);
    await tester.pumpAndSettle();

    for (final String type in <String>['유산소', '근력', '스트레칭', '기타']) {
      expect(
        find.byKey(ValueKey<String>('program-editor-session-type-$type')),
        findsOneWidget,
        reason: '$type 이 메뉴에 있어야 한다',
      );
    }
  });

  testWidgets('고른 유형이 세션 이름이 된다', (tester) async {
    await _pump(tester);
    await _addSessionOfType(tester, '유산소');

    expect(find.text('유산소 세션'), findsOneWidget);
  });

  testWidgets('같은 유형이 또 있으면 2번부터 번호를 붙인다', (tester) async {
    await _pump(tester);
    await _addSessionOfType(tester, '근력');
    await _addSessionOfType(tester, '근력');
    await _addSessionOfType(tester, '유산소');

    // 첫 번째에는 번호가 없다 — 하나뿐일 때 `근력 세션 1` 은 군더더기다.
    expect(find.text('근력 세션'), findsOneWidget);
    expect(find.text('근력 세션 2'), findsOneWidget);
    // 유형이 다르면 번호를 나눠 센다.
    expect(find.text('유산소 세션'), findsOneWidget);
  });

  testWidgets('세션 유형이 새 운동의 기본 유형이 된다', (tester) async {
    await _pump(tester);
    await _addSessionOfType(tester, '스트레칭');

    // 새로 만든 세션(두 번째)의 `운동 추가` 를 연다.
    final Finder addExercise = find.widgetWithText(AppButton, '운동 추가');
    await tester.ensureVisible(addExercise.last);
    await tester.tap(addExercise.last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(
              const ValueKey<String>('custom-exercise-category-스트레칭'),
            ),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(const ValueKey<String>('custom-exercise-category-근력')),
          )
          .selected,
      isFalse,
    );
  });
}

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

  _aiTests();
  _moveTests();
}

/// AI 후보가 들어오는 경로만 따로 띄운다 — 저장된 초안이 있으면 후보를
/// 덧붙이지 않으므로(`initialDraft`), 여기서는 빈 편집기로 시작한다.
Future<void> _pumpAi(
  WidgetTester tester,
  List<AiRoutineItem> suggestions,
) async {
  useFixedKstDate(DateTime(2026, 1, 1, 9));
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1600);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Widget build(List<AiRoutineItem> items) => MaterialApp(
    locale: const Locale('ko'),
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ProgramEditorWorkspace(
          clientGoal: '체중 감량',
          aiSuggestions: items,
          onSend: (_) {},
          registerDate: DateTime(2026),
          onRegisterDateChanged: (_) {},
          registerStartTime: const TimeOfDay(hour: 10, minute: 0),
          registerEndTime: const TimeOfDay(hour: 11, minute: 0),
          onRegisterTimeRangeChanged: (_) {},
        ),
      ),
    ),
  );
  // 후보는 `didUpdateWidget` 에서 붙는다 — 빈 목록으로 한 번 띄운 뒤 바꾼다.
  await tester.pumpWidget(build(const <AiRoutineItem>[]));
  await tester.pump();
  await tester.pumpWidget(build(suggestions));
  await tester.pumpAndSettle();
}

AiRoutineItem _ai(String id, String name, String type) =>
    AiRoutineItem(id: id, name: name, minutes: 10, type: type, reason: '');

void _aiTests() {
  testWidgets('AI 후보는 유형별 세션으로 나뉘고, 빈 첫 세션을 대신 쓴다', (tester) async {
    await _pumpAi(tester, <AiRoutineItem>[
      _ai('a', '저강도 걷기', '걷기'),
      _ai('b', '스쿼트', '근력'),
      _ai('c', '실내 사이클', '유산소'),
    ]);

    // `걷기` 는 옛 계약값이라 `유산소` 로 접힌다 — 떨어져 나온 `실내 사이클`
    // 과 한 세션으로 모인다.
    expect(find.text('유산소 세션'), findsOneWidget);
    expect(find.text('근력 세션'), findsOneWidget);
    // 비어 있던 첫 세션은 남지 않는다.
    expect(find.text('세션 A'), findsNothing);
  });

  testWidgets('유형이 하나뿐이면 세션도 하나다', (tester) async {
    await _pumpAi(tester, <AiRoutineItem>[
      _ai('a', '저강도 걷기', '유산소'),
      _ai('b', '실내 사이클', '유산소'),
    ]);

    expect(find.text('유산소 세션'), findsOneWidget);
    expect(find.text('유산소 세션 2'), findsNothing);
    expect(find.text('근력 세션'), findsNothing);
  });
}

void _moveTests() {
  testWidgets('운동을 다른 세션으로 옮긴다', (tester) async {
    await _pumpAi(tester, <AiRoutineItem>[
      _ai('a', '저강도 걷기', '유산소'),
      _ai('b', '스쿼트', '근력'),
    ]);

    // 유산소 세션의 `저강도 걷기` 를 근력 세션으로 옮긴다.
    final Finder menu = find
        .byKey(const ValueKey<String>('exercise-edit-exercise-2'))
        .first;
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '다른 세션으로'));
    await tester.pumpAndSettle();

    // 자기 세션은 고를 수 없다 — 목록에 근력 세션만 뜬다.
    expect(find.text('어느 세션으로 옮길까요?'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '유산소 세션'), findsNothing);
    await tester.tap(find.widgetWithText(AppButton, '근력 세션'));
    await tester.pumpAndSettle();

    // 옮긴 뒤 유산소 세션은 비고, 근력 세션이 두 운동을 갖는다.
    final Finder cardio = find.text('유산소 세션');
    final Finder strength = find.text('근력 세션');
    expect(cardio, findsOneWidget);
    expect(strength, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('저강도 걷기')).dy,
      greaterThan(tester.getTopLeft(strength).dy),
      reason: '옮긴 운동은 근력 세션 아래에 있어야 한다',
    );
  });

  testWidgets('세션이 하나뿐이면 옮기기 항목이 없다', (tester) async {
    await _pumpAi(tester, <AiRoutineItem>[_ai('a', '저강도 걷기', '유산소')]);

    final Finder menu = find
        .byKey(const ValueKey<String>('exercise-edit-exercise-2'))
        .first;
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, '다른 세션으로'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, '삭제'), findsOneWidget);
  });
}

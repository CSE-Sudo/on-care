// AI 마법사를 다시 반영할 때 앞서 넣은 AI 운동을 새 안으로 바꾸는가. (#2875)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

import '../../helpers/fixed_clock.dart';

AiRoutineItem _ai(String id, String name, String type) =>
    AiRoutineItem(id: id, name: name, minutes: 10, type: type, reason: '');

/// A안(회복) — 유산소 하나, 근력 하나.
final List<AiRoutineItem> _planA = <AiRoutineItem>[
  _ai('a1', '저강도 걷기', '유산소'),
  _ai('a2', '맨몸 스쿼트', '근력'),
];

/// B안(강화) — 같은 두 유형의 다른 운동.
final List<AiRoutineItem> _planB = <AiRoutineItem>[
  _ai('b1', '인터벌 러닝', '유산소'),
  _ai('b2', '바벨 런지', '근력'),
];

/// 운동 카드 제목 — 수정 칸(EditableText)의 같은 글자는 세지 않는다.
Finder _cardTitle(String name) =>
    find.byWidgetPredicate((Widget w) => w is Text && w.data == name);

final Finder _dialog = find.byKey(const ValueKey<String>('ai-reapply-dialog'));

ProgramEditorState? _sent;

Widget _app(List<AiRoutineItem> suggestions) => MaterialApp(
  locale: const Locale('ko'),
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: ProgramEditorWorkspace(
        clientGoal: '체중 감량',
        aiSuggestions: suggestions,
        onSend: (draft) => _sent = draft,
        registerDate: DateTime(2026),
        onRegisterDateChanged: (_) {},
        registerStartTime: const TimeOfDay(hour: 10, minute: 0),
        registerEndTime: const TimeOfDay(hour: 11, minute: 0),
        onRegisterTimeRangeChanged: (_) {},
      ),
    ),
  ),
);

/// 빈 편집기로 연 뒤 A안을 반영한다.
Future<void> _openWithPlanA(WidgetTester tester) async {
  useFixedKstDate(DateTime(2026, 1, 1, 9));
  _sent = null;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(const <AiRoutineItem>[]));
  await tester.pump();
  await tester.pumpWidget(_app(List<AiRoutineItem>.of(_planA)));
  await tester.pumpAndSettle();
}

/// 위저드로 돌아가 B안을 반영한다 — 새 목록이 넘어온다.
Future<void> _reapplyPlanB(WidgetTester tester) async {
  await tester.pumpWidget(_app(List<AiRoutineItem>.of(_planB)));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey<String>(key)));
  await tester.pumpAndSettle();
}

/// 운동 카드의 ⋯ 메뉴에서 `수정` 을 연다.
Future<void> _openEdit(WidgetTester tester, String exerciseId) async {
  final Finder trigger = find.byKey(
    ValueKey<String>('exercise-edit-$exerciseId'),
  );
  await tester.ensureVisible(trigger);
  await tester.pump();
  await tester.tap(trigger);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, '수정'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('처음 반영할 때는 묻지 않고 붙인다', (tester) async {
    await _openWithPlanA(tester);

    expect(_dialog, findsNothing);
    expect(find.text('저강도 걷기'), findsOneWidget);
    expect(find.text('맨몸 스쿼트'), findsOneWidget);
  });

  testWidgets('다시 반영하면 먼저 묻고, 바꾸면 A안 AI 운동이 B안으로 바뀐다', (tester) async {
    await _openWithPlanA(tester);
    await _reapplyPlanB(tester);

    expect(_dialog, findsOneWidget);
    expect(find.text('AI 운동을 새 안으로 바꿀까요?'), findsOneWidget);
    expect(find.textContaining('AI 운동 2개를 새 안으로'), findsOneWidget);

    await _choose(tester, 'ai-reapply-replace');

    expect(find.text('저강도 걷기'), findsNothing);
    expect(find.text('맨몸 스쿼트'), findsNothing);
    expect(find.text('인터벌 러닝'), findsOneWidget);
    expect(find.text('바벨 런지'), findsOneWidget);
    // 빈 세션은 새 유형에 내주고, 번호도 처음 반영할 때와 같다(#2474).
    expect(find.text('유산소 세션'), findsOneWidget);
    expect(find.text('근력 세션'), findsOneWidget);
    expect(find.text('유산소 세션 2'), findsNothing);
    expect(find.text('근력 세션 2'), findsNothing);
  });

  testWidgets('바꾼 뒤 보내면 두 안이 섞이지 않는다', (tester) async {
    await _openWithPlanA(tester);
    await _reapplyPlanB(tester);
    await _choose(tester, 'ai-reapply-replace');

    final Finder send = find.byKey(
      const ValueKey<String>('program-editor-send'),
    );
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();

    final List<String> names = <String>[
      for (final ProgramSessionDraft session in _sent!.sessions)
        for (final ProgramExerciseDraft exercise in session.exercises)
          exercise.name,
    ];
    expect(names, unorderedEquals(<String>['인터벌 러닝', '바벨 런지']));
  });

  testWidgets('뒤에 추가를 고르면 예전처럼 덧붙인다', (tester) async {
    await _openWithPlanA(tester);
    await _reapplyPlanB(tester);

    await _choose(tester, 'ai-reapply-append');

    for (final String name in <String>['저강도 걷기', '맨몸 스쿼트', '인터벌 러닝', '바벨 런지']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('취소하면 편집기는 그대로다', (tester) async {
    await _openWithPlanA(tester);
    await _reapplyPlanB(tester);

    await _choose(tester, 'ai-reapply-cancel');

    expect(_dialog, findsNothing);
    expect(find.text('저강도 걷기'), findsOneWidget);
    expect(find.text('맨몸 스쿼트'), findsOneWidget);
    expect(find.text('인터벌 러닝'), findsNothing);
    expect(find.text('바벨 런지'), findsNothing);
  });

  testWidgets('트레이너가 고친 AI 운동은 바꾸지 않고 남긴다', (tester) async {
    await _openWithPlanA(tester);

    // 첫 운동(`저강도 걷기`, exercise-2)의 유형을 스트레칭으로 고친다.
    await _openEdit(tester, 'exercise-2');
    final Finder stretch = find.byKey(
      const ValueKey<String>('exercise-2-type-스트레칭'),
    );
    await tester.ensureVisible(stretch);
    await tester.tap(stretch);
    await tester.pumpAndSettle();

    await _reapplyPlanB(tester);
    // 바꿀 것은 고치지 않은 하나뿐이다.
    expect(find.textContaining('AI 운동 1개를 새 안으로'), findsOneWidget);
    await _choose(tester, 'ai-reapply-replace');

    // 고친 카드는 수정 칸이 열린 채라 이름이 입력 칸에도 보인다 — 카드
    // 제목(Text)만 센다.
    expect(_cardTitle('저강도 걷기'), findsOneWidget);
    expect(find.text('맨몸 스쿼트'), findsNothing);
    expect(find.text('인터벌 러닝'), findsOneWidget);
    expect(find.text('바벨 런지'), findsOneWidget);
  });

  testWidgets('같은 값으로 다시 확정한 것은 고친 것이 아니다', (tester) async {
    await _openWithPlanA(tester);

    // 유형 칩을 지금 값 그대로 다시 누른다.
    await _openEdit(tester, 'exercise-2');
    final Finder same = find.byKey(
      const ValueKey<String>('exercise-2-type-유산소'),
    );
    await tester.ensureVisible(same);
    await tester.tap(same);
    await tester.pumpAndSettle();

    await _reapplyPlanB(tester);
    expect(find.textContaining('AI 운동 2개를 새 안으로'), findsOneWidget);
  });

  testWidgets('넘어온 후보가 비어 있으면 묻지 않는다', (tester) async {
    await _openWithPlanA(tester);

    await tester.pumpWidget(_app(<AiRoutineItem>[]));
    await tester.pumpAndSettle();

    expect(_dialog, findsNothing);
    expect(find.text('저강도 걷기'), findsOneWidget);
  });
}

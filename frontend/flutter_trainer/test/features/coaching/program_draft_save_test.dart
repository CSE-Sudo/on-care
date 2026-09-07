// 프로그램 탭의 `저장` — 편집기 구성을 프로그램 템플릿으로 저장한다. (#1028)
//
// 별도의 "저장한 프로그램" 보관함은 없다 — 저장은 곧장 회원 리스트 아래
// `프로그램 템플릿` 목록에 쓰고, 버튼은 몇 번을 눌러도 항상 `저장`이다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';

import '../../helpers/pump_app.dart';

/// In-memory stand-in for the template store.
class _FakeTemplateRepository implements TrainerProgramTemplateRepository {
  _FakeTemplateRepository({this.failWrites = false});

  final List<ProgramTemplate> saved = <ProgramTemplate>[];
  bool failWrites;
  int createCalls = 0;

  @override
  bool get supportsEditing => true;

  @override
  Future<List<ProgramTemplate>> list() async =>
      List<ProgramTemplate>.of(saved.reversed);

  @override
  Future<ProgramTemplate> create({
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async {
    createCalls++;
    if (failWrites) throw const NetworkError();
    final template = ProgramTemplate(
      id: 'tpl-${saved.length + 1}',
      name: name,
      goal: goal,
      exercises: exercises,
    );
    saved.add(template);
    return template;
  }

  @override
  Future<ProgramTemplate> update(
    String id, {
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async => throw UnsupportedError('저장 버튼은 항상 새로 만든다 (#1028)');

  @override
  Future<void> delete(String id) async {
    saved.removeWhere((t) => t.id == id);
  }
}

Finder get _saveButton =>
    find.byKey(const ValueKey<String>('program-editor-save'));

/// The save button is an icon-only bookmark now — outline before a
/// successful save, filled after. Reading the icon (not a text label) is
/// how these tests check that state.
IconData? _saveButtonIcon(WidgetTester tester) =>
    (tester.widget<IconButton>(_saveButton).icon as Icon).icon;

Future<void> _openCoaching(
  WidgetTester tester,
  TrainerProgramTemplateRepository repository,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.coaching,
    extraOverrides: <Override>[
      trainerProgramTemplateRepositoryProvider.overrideWithValue(repository),
    ],
  );
  final manual = find.byKey(const ValueKey<String>('ai-manual-create'));
  await tester.ensureVisible(manual);
  await tester.pump();
  await tester.tap(manual);
  await tester.pumpAndSettle();
}

/// 편집기는 빈 상태로 시작한다(#1028 후속) — 저장하려면 운동을 하나 넣어야
/// 한다.
Future<void> _addExercise(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(
    find.text('운동 추가'),
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text('운동 추가'));
  await tester.pump();
  await tester.tap(find.text('운동 추가'));
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey<String>('custom-exercise-name')),
    name,
  );
  await tester.ensureVisible(find.text('추가'));
  await tester.pump();
  await tester.tap(find.text('추가'));
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _saveButton,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(_saveButton);
  await tester.pump();
  await tester.tap(_saveButton);
}

void main() {
  testWidgets('저장하면 프로그램 템플릿 목록에 곧장 나타난다', (tester) async {
    final repository = _FakeTemplateRepository();
    await _openCoaching(tester, repository);
    await _addExercise(tester, '레그프레스 4세트');

    await _tapSave(tester);
    await settle(tester);

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.exercises.single.name, '레그프레스 4세트');
    expect(find.text('프로그램을 저장했어요'), findsOneWidget);

    // 별도의 "저장한 프로그램" 보관함은 없다.
    expect(
      find.byKey(const ValueKey<String>('saved-programs-card')),
      findsNothing,
    );

    // 왼쪽 사이드바의 `프로그램 템플릿` 카드에 방금 저장한 이름이 보인다.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('program-template-sidebar')),
      -150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('program-template-sidebar')),
        matching: find.text(repository.saved.single.name),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    '북마크는 저장 전 outline, 성공 후 filled — 다시 눌러도 덮어쓰지 않고 새로 만든다',
    (tester) async {
      final repository = _FakeTemplateRepository();
      await _openCoaching(tester, repository);
      await _addExercise(tester, '스쿼트 3세트');

      expect(_saveButtonIcon(tester), Icons.bookmark_border);

      await _tapSave(tester);
      await settle(tester);

      expect(repository.saved, hasLength(1));
      // 저장에 성공한 뒤에는 아이콘이 채워진다.
      await tester.scrollUntilVisible(
        _saveButton,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_saveButtonIcon(tester), Icons.bookmark);

      // 다시 눌러도 새 템플릿이 하나 더 만들어질 뿐, 덮어쓰지 않는다.
      await _addExercise(tester, '런지 3세트');
      await _tapSave(tester);
      await settle(tester);
      expect(repository.saved, hasLength(2));
      expect(repository.createCalls, 2);
      expect(_saveButtonIcon(tester), Icons.bookmark);
    },
  );

  testWidgets('운동이 하나도 없으면 저장하지 않는다', (tester) async {
    final repository = _FakeTemplateRepository();
    await _openCoaching(tester, repository);

    await _tapSave(tester);
    await settle(tester);

    expect(repository.saved, isEmpty);
    expect(repository.createCalls, 0);
  });

  testWidgets('저장에 실패해도 작성 중인 내용이 남고 다시 시도할 수 있다', (tester) async {
    final repository = _FakeTemplateRepository(failWrites: true);
    await _openCoaching(tester, repository);
    await _addExercise(tester, '벤치프레스 4세트');

    await _tapSave(tester);
    await settle(tester);

    expect(find.textContaining('템플릿을 저장하지 못했어요'), findsOneWidget);
    expect(repository.saved, isEmpty);
    // 버튼이 잠긴 채로 남지 않고, 실패했으니 아이콘도 채워지지 않는다.
    await tester.scrollUntilVisible(
      _saveButton,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<IconButton>(_saveButton).onPressed, isNotNull);
    expect(_saveButtonIcon(tester), Icons.bookmark_border);
    expect(find.text('벤치프레스 4세트'), findsWidgets);

    repository.failWrites = false;
    await _tapSave(tester);
    await settle(tester);
    expect(repository.saved, hasLength(1));
    expect(_saveButtonIcon(tester), Icons.bookmark);
  });
}

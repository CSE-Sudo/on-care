import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_template_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 저장된 템플릿이 없는 트레이너에게 보이는 시작 구성은 **저장된 행이 아니다**.
/// 고치면 그 트레이너의 첫 템플릿으로 새로 저장된다 — 그래야 "지웠는데 되살아
/// 난다" 가 생기지 않는다. 그 규약을 화면이 지키는지 본다. (#920)
class _FakeTemplateRepository implements TrainerProgramTemplateRepository {
  _FakeTemplateRepository();

  List<ProgramTemplate> templates = const <ProgramTemplate>[];
  final List<({String name, String goal, List<TemplateExercise> exercises})>
  created = <({String name, String goal, List<TemplateExercise> exercises})>[];
  final List<({String id, String name})> updated =
      <({String id, String name})>[];
  final List<String> deleted = <String>[];
  AppError? failure;

  @override
  bool get supportsEditing => true;

  @override
  Future<List<ProgramTemplate>> list() async => templates;

  @override
  Future<ProgramTemplate> create({
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async {
    if (failure case final AppError error) throw error;
    created.add((name: name, goal: goal, exercises: exercises));
    return ProgramTemplate(
      id: 'tpl-new',
      name: name,
      goal: goal,
      exercises: exercises,
    );
  }

  @override
  Future<ProgramTemplate> update(
    String id, {
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async {
    if (failure case final AppError error) throw error;
    updated.add((id: id, name: name));
    return ProgramTemplate(
      id: id,
      name: name,
      goal: goal,
      exercises: exercises,
    );
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

const ProgramTemplate _starter = ProgramTemplate(
  id: 'starter:0',
  name: '혈압 관리 기본',
  goal: '혈압 관리 · 초급',
  exercises: <TemplateExercise>[
    TemplateExercise(name: '저강도 걷기', minutes: 20, type: '유산소'),
  ],
);

const ProgramTemplate _mine = ProgramTemplate(
  id: 'tpl-1',
  name: '내 블록',
  goal: '체중 감량',
  exercises: <TemplateExercise>[
    TemplateExercise(name: '전신 서킷', minutes: 20, type: '근력'),
  ],
);

Future<void> _pumpDialog(
  WidgetTester tester,
  _FakeTemplateRepository repository, {
  ProgramTemplate? template,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        trainerProgramTemplateRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ProgramTemplateDialog(template: template)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('엔티티', () {
    test('시작 구성은 id 로 구분된다', () {
      expect(_starter.isStarter, isTrue);
      expect(_mine.isStarter, isFalse);
    });

    test('서버 응답 한 건을 읽는다', () {
      final template = ProgramTemplate.fromJson(<String, Object?>{
        'id': 'tpl-1',
        'name': '내 블록',
        'goal': '체중 감량',
        'exercises': <Object?>[
          <String, Object?>{'name': '걷기', 'minutes': 30, 'type': '걷기'},
        ],
        'updated_at': '2026-08-19T09:00:00Z',
      });

      // 초 칸이 생기기 전의 서버·템플릿은 분 × 60 으로 읽는다. (#2521)
      expect(template.exercises.single.durationSeconds, 1800);
      expect(template.totalSeconds, 1800);
    });

    test('초가 오면 초 그대로 읽고, 저장할 때도 초를 싣는다 (#2521)', () {
      final exercise = TemplateExercise.fromJson(<String, Object?>{
        'name': '버피',
        'minutes': 1,
        'duration_seconds': 45,
        'type': '유산소',
      });

      expect(exercise.durationSeconds, 45);
      expect(exercise.minutes, 1);
      expect(exercise.toJson()['duration_seconds'], 45);
      expect(exercise.toJson()['minutes'], 1);
    });
  });

  group('다이얼로그', () {
    testWidgets('초가 든 템플릿을 열었다가 저장해도 초가 그대로다 (#2521)', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpDialog(
        tester,
        repository,
        template: const ProgramTemplate(
          id: 'starter:1',
          name: '초 블록',
          goal: '',
          exercises: <TemplateExercise>[
            TemplateExercise(name: '버피', durationSeconds: 45, type: '유산소'),
            TemplateExercise(name: '걷기', durationSeconds: 5415, type: '유산소'),
          ],
        ),
      );

      // 분 한 칸이 아니라 시·분·초 세 칸으로 연다.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'template-duration-',
              ),
        ),
        findsWidgets,
      );

      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      expect(
        repository.created.single.exercises.map((e) => e.durationSeconds),
        <int>[45, 5415],
      );
    });

    testWidgets('시작 구성을 고치면 새 템플릿으로 저장된다', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpDialog(tester, repository, template: _starter);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-name')),
        '내가 고친 혈압 블록',
      );
      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      // 고치기가 아니라 만들기다 — 시작 구성에는 고칠 행이 없다.
      expect(repository.updated, isEmpty);
      expect(repository.created.single.name, '내가 고친 혈압 블록');
      expect(repository.created.single.exercises.single.name, '저강도 걷기');
    });

    testWidgets('내 템플릿을 고치면 그 행을 고친다', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpDialog(tester, repository, template: _mine);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-name')),
        '고친 이름',
      );
      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      expect(repository.created, isEmpty);
      expect(repository.updated.single, (id: 'tpl-1', name: '고친 이름'));
    });

    testWidgets('시작 구성과 내 템플릿의 편집 창은 똑같이 생겼다', (tester) async {
      // 저장하면 새로 만들어지는지/그 행을 고치는지는 데이터 계층의 차이일
      // 뿐, 편집 창 자체(제목·안내 문구·버튼 문구)는 똑같아야 한다.
      await _pumpDialog(tester, _FakeTemplateRepository(), template: _starter);
      expect(find.text('템플릿 편집'), findsOneWidget);
      expect(find.text('새 템플릿'), findsNothing);
      expect(find.text('기본 구성이에요. 고치면 내 템플릿으로 저장돼요'), findsNothing);
      expect(find.text('내 템플릿으로 저장'), findsNothing);
      expect(find.text('저장'), findsOneWidget);

      await _pumpDialog(tester, _FakeTemplateRepository(), template: _mine);
      expect(find.text('템플릿 편집'), findsOneWidget);
      expect(find.text('저장'), findsOneWidget);
    });

    testWidgets('이름이 비면 저장하지 않고 이유를 말한다', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpDialog(tester, repository);

      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      expect(find.text('템플릿 이름을 입력해 주세요'), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets('운동이 하나도 없으면 저장하지 않는다', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpDialog(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-name')),
        '빈 블록',
      );
      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      // 운동 줄은 있지만 이름이 비어 있다 — 끼워 넣어도 아무 일이 없는 블록이다.
      expect(find.text('운동을 하나 이상 넣어 주세요'), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets('서버가 거절하면 사유가 남고 다이얼로그는 닫히지 않는다', (tester) async {
      final repository = _FakeTemplateRepository()
        ..failure = const ValidationError(message: '템플릿은 최대 30개까지 저장할 수 있습니다.');
      await _pumpDialog(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-name')),
        '하나 더',
      );
      await tester.enterText(find.byType(TextField).at(2), '걷기');
      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      expect(find.text('템플릿은 최대 30개까지 저장할 수 있습니다.'), findsOneWidget);
      expect(find.byType(ProgramTemplateDialog), findsOneWidget);
    });
  });

  group('데모', () {
    test('세션 동안은 저장·수정·삭제가 된다 (#1028)', () async {
      final demo = MockTrainerProgramTemplateRepository();

      // 저장한 것이 없으면 시작 구성.
      expect(demo.supportsEditing, isTrue);
      expect(await demo.list(), MockTrainerProgramTemplateRepository.starters);

      final created = await demo.create(
        name: '내 첫 템플릿',
        goal: '체중 감량',
        exercises: const <TemplateExercise>[
          TemplateExercise(name: '스쿼트', minutes: 15, type: '근력'),
        ],
      );
      // 저장한 것이 생겨도 시작 구성은 그대로 함께 보인다.
      expect(await demo.list(), <ProgramTemplate>[
        created,
        ...MockTrainerProgramTemplateRepository.starters,
      ]);

      final updated = await demo.update(
        created.id,
        name: '고친 이름',
        goal: created.goal,
        exercises: created.exercises,
      );
      expect((await demo.list()).first.name, updated.name);

      await demo.delete(updated.id);
      // 마지막 하나를 지우면 다시 시작 구성으로 돌아간다.
      expect(await demo.list(), MockTrainerProgramTemplateRepository.starters);
    });

    test('앱을 새로 시작하면(새 인스턴스) 저장한 것이 남지 않는다', () async {
      final first = MockTrainerProgramTemplateRepository();
      await first.create(
        name: '이번 세션 템플릿',
        goal: '',
        exercises: const <TemplateExercise>[
          TemplateExercise(name: '걷기', minutes: 20, type: '유산소'),
        ],
      );

      final second = MockTrainerProgramTemplateRepository();
      expect(
        await second.list(),
        MockTrainerProgramTemplateRepository.starters,
      );
    });
  });

  // 오류 문구 하나를 세 경우가 돌려 쓰며 언제나 이름 칸에 붙던 동안에는,
  // 이름을 제대로 적어 둔 트레이너가 빨개진 이름 칸을 들여다보며 무엇이
  // 틀렸는지 찾아야 했다. 오류는 저마다 제 자리에서 말한다. (#2220)
  group('저장 창 오류 자리', () {
    testWidgets('운동이 없으면 이름 칸이 아니라 운동 쪽에서 말한다', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpDialog(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-name')),
        '이름은 멀쩡하다',
      );
      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('template-exercise-error')),
        findsOneWidget,
      );
      // 이름 칸은 건드리지 않는다 — 이름은 틀리지 않았다.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('template-name')),
          matching: find.text('운동을 하나 이상 넣어 주세요'),
        ),
        findsNothing,
      );
      // 어느 줄이 모자란지 그 줄에서 짚는다.
      expect(find.text('운동 이름을 적어 주세요'), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets('이름이 비면 이름 칸에서 말한다', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpDialog(tester, repository);

      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      expect(find.text('템플릿 이름을 입력해 주세요'), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets('저장이 막히면 창 아래에서 말한다', (tester) async {
      final repository = _FakeTemplateRepository()
        ..failure = const ValidationError(message: '서버가 거절했어요');
      await _pumpDialog(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey<String>('template-name')),
        '내 블록',
      );
      await tester.enterText(find.byType(TextField).at(2), '걷기');
      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('template-save-error')),
        findsOneWidget,
      );
    });
  });
}

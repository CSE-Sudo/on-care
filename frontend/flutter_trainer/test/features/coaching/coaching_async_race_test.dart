import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/web/leave_guard.dart';
import 'package:oncare_trainer/features/coaching/data/coaching_draft_autosaver.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 붙일 PT 조회를 붙잡고 등록 횟수를 센다.
class _HoldingScheduleRepository extends DriftScheduleRepository {
  _HoldingScheduleRepository(super.db);

  /// 다음 `fetchClientSessionsOn` 을 이 완료자가 끝낼 때까지 붙잡는다.
  Completer<void>? holdFetch;
  int registerCalls = 0;

  @override
  Future<List<ScheduleSession>> fetchClientSessionsOn(
    ScheduleClientKey client,
    String date,
  ) async {
    final Completer<void>? hold = holdFetch;
    holdFetch = null;
    if (hold != null) await hold.future;
    return super.fetchClientSessionsOn(client, date);
  }

  @override
  Future<bool> registerProgramSchedule({
    required String date,
    required String clientId,
    required String clientName,
    required String time,
    required int durationMinutes,
    required Map<String, Object?> assignment,
    required List<ProgramItem> program,
    String? sessionId,
    List<RoutineExercise> personalRoutines = const <RoutineExercise>[],
    String note = '',
  }) {
    registerCalls++;
    return super.registerProgramSchedule(
      date: date,
      clientId: clientId,
      clientName: clientName,
      time: time,
      durationMinutes: durationMinutes,
      assignment: assignment,
      program: program,
      sessionId: sessionId,
      personalRoutines: personalRoutines,
      note: note,
    );
  }
}

/// 데모 템플릿 저장소의 `create` 를 붙잡는다.
class _HoldingTemplateRepository extends MockTrainerProgramTemplateRepository {
  _HoldingTemplateRepository({super.db});

  Completer<void>? holdCreate;

  @override
  Future<ProgramTemplate> create({
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async {
    final Completer<void>? hold = holdCreate;
    holdCreate = null;
    if (hold != null) await hold.future;
    return super.create(name: name, goal: goal, exercises: exercises);
  }
}

/// 실서버처럼 없는 템플릿은 404([NotFoundError])다. [rows] 를 직접 지우면
/// 다른 탭에서 지운 것이다.
class _ServerLikeTemplateRepository
    implements TrainerProgramTemplateRepository {
  final List<ProgramTemplate> rows = <ProgramTemplate>[_mine];
  int listCalls = 0;

  @override
  bool get supportsEditing => true;

  @override
  Future<List<ProgramTemplate>> list() async {
    listCalls++;
    return List<ProgramTemplate>.of(rows);
  }

  @override
  Future<ProgramTemplate> create({
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async => throw UnimplementedError();

  @override
  Future<ProgramTemplate> update(
    String id, {
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async {
    final int index = rows.indexWhere((t) => t.id == id);
    if (index == -1) throw const NotFoundError();
    return rows[index] = ProgramTemplate(
      id: id,
      name: name,
      goal: goal,
      exercises: exercises,
    );
  }

  @override
  Future<void> delete(String id) async {
    final int index = rows.indexWhere((t) => t.id == id);
    if (index == -1) throw const NotFoundError();
    rows.removeAt(index);
  }
}

const ProgramTemplate _mine = ProgramTemplate(
  id: 'tpl-1',
  name: '내 블록',
  goal: '체중 감량',
  exercises: <TemplateExercise>[
    TemplateExercise(name: '전신 서킷', minutes: 20, type: '근력'),
  ],
);

/// 코칭 화면이 네트워크를 기다리는 사이 연타·회원 전환·다른 탭 변경 (#3101).
void main() {
  const String a = 'seed-client-1';
  const String b = 'seed-client-2';

  Future<ProviderContainer> open(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.coachingFor(a),
      seedClock: kMidWeekKst,
      extraOverrides: overrides,
    );
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
  }

  Future<void> tapCentered(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder card(String id) => find.byKey(ValueKey<String>('program-client-$id'));

  Finder templateCard(String id) =>
      find.byKey(ValueKey<String>('template-card-$id')).first;

  final String starter = MockTrainerProgramTemplateRepository.starters.first.id;
  final Finder send = find.byKey(const ValueKey<String>('program-editor-send'));
  final Finder confirmSubmit = find.byKey(
    const ValueKey<String>('program-assign-confirm-submit'),
  );

  /// 확인창 뒤에 붙잡힐 수 있는 두 창(개인운동 없음·교체)을 넘긴다.
  Future<void> passFollowUps(WidgetTester tester) async {
    final Finder noRoutines = find.byKey(
      const ValueKey<String>('no-personal-routine-dialog'),
    );
    final Finder replace = find.text('이미 개인운동이 있어요');
    for (
      var i = 0;
      i < 40 && noRoutines.evaluate().isEmpty && replace.evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (noRoutines.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('no-personal-routine-skip')),
      );
    } else if (replace.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AppDialog), matching: find.text('교체')),
      );
    }
  }

  group('(a) 일정 추가 연타', () {
    testWidgets('PT 조회를 기다리는 동안 잠겨 확인창 하나, 등록 한 번이다', (tester) async {
      late _HoldingScheduleRepository repo;
      await open(
        tester,
        overrides: <Override>[
          scheduleRepositoryProvider.overrideWith(
            (ref) => repo = _HoldingScheduleRepository(
              ref.watch(appDatabaseProvider),
            ),
          ),
        ],
      );
      await tapCentered(tester, templateCard(starter));
      await reveal(tester, send);
      expect(tester.widget<AppButton>(send).onPressed, isNotNull);

      final Completer<void> hold = Completer<void>();
      repo.holdFetch = hold;
      await tester.tap(send);
      await tester.pump();
      // 첫 누름부터 잠긴다 — 조회를 기다리는 사이 두 번째 누름이 들어오지 않는다.
      expect(tester.widget<AppButton>(send).onPressed, isNull);
      await tester.tap(send, warnIfMissed: false);
      await tester.pump();

      hold.complete();
      await tester.pumpAndSettle();
      expect(confirmSubmit, findsOneWidget);

      await tester.tap(confirmSubmit);
      await passFollowUps(tester);
      await settle(tester);

      expect(repo.registerCalls, 1);
      expect(confirmSubmit, findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
    });
  });

  group('(b) 템플릿 저장 중 회원 전환', () {
    testWidgets('옮겨 간 회원의 작성 내용·이탈 경고·자동 보관이 남는다', (tester) async {
      late _HoldingTemplateRepository templates;
      final ProviderContainer container = await open(
        tester,
        overrides: <Override>[
          trainerProgramTemplateRepositoryProvider.overrideWith(
            (ref) => templates = _HoldingTemplateRepository(
              db: ref.watch(appDatabaseProvider),
            ),
          ),
        ],
      );
      await tapCentered(tester, templateCard(starter));
      expect(leaveGuards.shouldBlock(), isTrue);

      // A 의 편집기에서 템플릿 저장을 누르고, 응답 전에 B 로 옮긴다.
      final Completer<void> hold = Completer<void>();
      templates.holdCreate = hold;
      await reveal(
        tester,
        find.byKey(const ValueKey<String>('program-editor-save')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-save')),
      );
      await tester.pump();
      await tapCentered(tester, card(b));
      await tester.tap(find.text('바꾸기').last);
      await settle(tester);
      expect(Uri.parse(currentLocation(tester)).queryParameters['client'], b);

      // B 의 편집을 시작한다.
      await tapCentered(tester, templateCard(starter));
      expect(leaveGuards.shouldBlock(), isTrue);

      hold.complete();
      await settle(tester);

      // A 의 저장이 끝나도 B 의 작성 내용 보호는 그대로다.
      expect(leaveGuards.shouldBlock(), isTrue);
      await tester.pump(kCoachingAutosaveDelay + const Duration(seconds: 1));
      await settle(tester);
      final TrainerProgramDraftRepository drafts = container.read(
        trainerProgramDraftRepositoryProvider,
      );
      expect(await drafts.list(memberId: b), isNotEmpty);
      expect(await drafts.list(memberId: a), isEmpty);
    });
  });

  group('(d) 다른 탭에서 지운 템플릿', () {
    Future<_ServerLikeTemplateRepository> openWithServerLike(
      WidgetTester tester,
    ) async {
      final _ServerLikeTemplateRepository repo =
          _ServerLikeTemplateRepository();
      await open(
        tester,
        overrides: <Override>[
          trainerProgramTemplateRepositoryProvider.overrideWithValue(repo),
        ],
      );
      expect(templateCard(_mine.id), findsOneWidget);
      return repo;
    }

    Future<void> openMenuItem(WidgetTester tester, String label) async {
      await tapCentered(
        tester,
        find.byKey(ValueKey<String>('template-menu-${_mine.id}')),
      );
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('지우면 목록을 다시 읽어 카드를 걷고 안내한다', (tester) async {
      final _ServerLikeTemplateRepository repo = await openWithServerLike(
        tester,
      );
      repo.rows.clear(); // 다른 탭에서 지웠다.
      final int listsBefore = repo.listCalls;

      await openMenuItem(tester, '삭제');
      await tester.tap(find.text('삭제').last); // 확인창
      await settle(tester);

      expect(repo.listCalls, greaterThan(listsBefore));
      expect(find.text('이미 지워진 템플릿이에요'), findsOneWidget);
      expect(find.text('템플릿을 삭제하지 못했어요. 다시 시도해 주세요'), findsNothing);
      expect(
        find.byKey(ValueKey<String>('template-card-${_mine.id}')),
        findsNothing,
      );
    });

    testWidgets('데모도 같다 — 지우면 카드를 걷고 안내한다', (tester) async {
      final ProviderContainer container = await open(tester);
      final TrainerProgramTemplateRepository demo = container.read(
        trainerProgramTemplateRepositoryProvider,
      );
      final ProgramTemplate? saved = await tester.runAsync(
        () => demo.create(
          name: _mine.name,
          goal: _mine.goal,
          exercises: _mine.exercises,
        ),
      );
      container.invalidate(programTemplatesProvider);
      await settle(tester);
      final Finder savedCard = find.byKey(
        ValueKey<String>('template-card-${saved!.id}'),
      );
      expect(savedCard, findsOneWidget);
      // 다른 탭에서 지웠다 — 이 탭의 목록은 아직 모른다.
      await tester.runAsync(() => demo.delete(saved.id));

      await tapCentered(
        tester,
        find.byKey(ValueKey<String>('template-menu-${saved.id}')),
      );
      await tester.tap(find.text('삭제').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제').last); // 확인창
      await settle(tester);

      expect(find.text('이미 지워진 템플릿이에요'), findsOneWidget);
      expect(savedCard, findsNothing);
    });

    testWidgets('고치면 창을 닫고 목록을 다시 읽어 카드를 걷는다', (tester) async {
      final _ServerLikeTemplateRepository repo = await openWithServerLike(
        tester,
      );
      repo.rows.clear(); // 다른 탭에서 지웠다.

      await openMenuItem(tester, '템플릿 수정');
      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await settle(tester);

      expect(find.byKey(const ValueKey<String>('template-save')), findsNothing);
      expect(find.text('이미 지워진 템플릿이에요'), findsOneWidget);
      expect(find.text('템플릿을 저장하지 못했어요. 다시 시도해 주세요'), findsNothing);
      expect(
        find.byKey(ValueKey<String>('template-card-${_mine.id}')),
        findsNothing,
      );
    });
  });
}

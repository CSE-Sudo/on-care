import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/web/leave_guard.dart';
import 'package:oncare_trainer/features/coaching/data/coaching_draft_autosaver.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/coaching_workspace_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/coaching_workspace_draft.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/trainer_program_draft.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 코칭 화면의 회원별 자동 보관과 `이어서 쓰기` (#2873 2단계).
///
/// 데모(브라우저 저장소) 저장소로 돈다 — 새로 고침은 코칭 화면이 처음 서는
/// 것과 같으므로, 화면을 열기 전에 저장소에 보관본을 넣어 두고 들어간다.
void main() {
  const String a = 'seed-client-1';
  const String exercise = '자동보관 레그프레스';

  Future<ProviderContainer> boot(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      seedClock: kMidWeekKst,
    );
  }

  TrainerProgramDraftRepository repoOf(ProviderContainer c) =>
      c.read(trainerProgramDraftRepositoryProvider);

  Future<List<TrainerProgramDraftSummary>> savedFor(ProviderContainer c) =>
      repoOf(c).list(memberId: a);

  /// 편집기에서 짜던 것을 보관해 둔다 — 새로 고침 전의 그 화면이다.
  Future<void> storeEditorDraft(ProviderContainer c) async {
    final Map<String, Object?> payload = coachingDraftPayload(
      const CoachingWorkspaceDraft(
        memberId: a,
        phase: CoachingWorkspacePhase.editor,
        editor: ProgramEditorState(
          name: '하체 프로그램',
          sessions: <ProgramSessionDraft>[
            ProgramSessionDraft(
              id: 'session-1',
              name: '근력 세션',
              exercises: <ProgramExerciseDraft>[
                ProgramExerciseDraft(id: 'exercise-1', name: exercise),
              ],
            ),
          ],
        ),
      ),
      fallbackName: '하체 프로그램',
    );
    await repoOf(c).create(<String, Object?>{...payload, 'member_id': a});
  }

  Future<void> tapCentered(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  final Finder resumeDialog = find.byKey(
    const ValueKey<String>('coach-draft-resume-dialog'),
  );
  final Finder editorExercise = find.text(exercise);

  Future<void> openWithStoredDraft(
    WidgetTester tester,
    ProviderContainer c,
  ) async {
    await storeEditorDraft(c);
    await goTo(tester, AppRoutes.coachingFor(a));
  }

  Future<void> resume(WidgetTester tester) async {
    expect(resumeDialog, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('coach-draft-resume')));
    await settle(tester);
  }

  testWidgets('후보를 받고 입력이 멈추면 그 회원 앞으로 자동 보관한다', (tester) async {
    final c = await boot(tester);
    await goTo(tester, AppRoutes.coachingFor(a));
    expect(await savedFor(c), isEmpty);

    await tapCentered(
      tester,
      find.byKey(const ValueKey<String>('generate-routine-options')),
    );
    await tester.pump(kCoachingAutosaveDelay + const Duration(seconds: 1));
    await tester.pump();

    final List<TrainerProgramDraftSummary> saved = await savedFor(c);
    expect(saved, hasLength(1));
    final TrainerProgramDraft draft = await repoOf(c).read(saved.single.id);
    final CoachingWorkspaceDraft? workspace = coachingWorkspaceFromDraft(
      draft,
      fallbackSessionName: '세션',
    );
    expect(workspace!.memberId, a);
    expect(workspace.phase, CoachingWorkspacePhase.wizard);
    // 받은 후보가 함께 보관된다 — 되살릴 때 다시 부르지 않는다.
    expect(workspace.wizard!.options, isNotNull);
  });

  testWidgets('보관본이 있으면 들어올 때 묻고, 이어서 쓰면 되살린다', (tester) async {
    final c = await boot(tester);
    await openWithStoredDraft(tester, c);

    expect(find.text('저장해 둔 작성 내용이 있어요'), findsOneWidget);
    expect(find.text('이어서 쓰기'), findsOneWidget);
    expect(find.text('버리기'), findsOneWidget);
    // 바깥을 눌러도 닫히지 않는다 — 고르기 전에는 보관본을 건드리지 않는다.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(resumeDialog, findsOneWidget);

    await resume(tester);

    expect(resumeDialog, findsNothing);
    expect(editorExercise, findsWidgets);
    // 되살린 것도 아직 보내지 않은 작성 내용이다.
    expect(leaveGuards.shouldBlock(), isTrue);
    expect(await savedFor(c), hasLength(1));
  });

  testWidgets('버리기를 고르면 보관본을 지우고 빈 화면으로 연다', (tester) async {
    final c = await boot(tester);
    await openWithStoredDraft(tester, c);

    await tester.tap(find.byKey(const ValueKey<String>('coach-draft-discard')));
    await settle(tester);

    expect(resumeDialog, findsNothing);
    expect(editorExercise, findsNothing);
    expect(leaveGuards.shouldBlock(), isFalse);
    expect(await savedFor(c), isEmpty);
  });

  testWidgets('템플릿으로 저장하면 보관본을 지운다', (tester) async {
    final c = await boot(tester);
    await openWithStoredDraft(tester, c);
    await resume(tester);

    await tapCentered(
      tester,
      find.byKey(const ValueKey<String>('program-editor-save')),
    );
    await settle(tester);

    expect(leaveGuards.shouldBlock(), isFalse);
    expect(await savedFor(c), isEmpty);
  });

  testWidgets('보내면 보관본을 지운다', (tester) async {
    final c = await boot(tester);
    await openWithStoredDraft(tester, c);
    await resume(tester);

    final Finder send = find.byKey(
      const ValueKey<String>('program-editor-send'),
    );
    await tapCentered(tester, send);
    await tester.tap(
      find.byKey(const ValueKey<String>('program-assign-confirm-submit')),
    );
    // 개인운동 없이 보내는지, 그 PT 의 개인운동을 바꾸는지 한 번 더 물을 수
    // 있다 — 이 테스트는 전송 뒤만 본다.
    final Finder noRoutines = find.byKey(
      const ValueKey<String>('no-personal-routine-skip'),
    );
    final Finder replace = find.descendant(
      of: find.byType(AppDialog),
      matching: find.text('교체'),
    );
    for (
      var i = 0;
      i < 60 && noRoutines.evaluate().isEmpty && replace.evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (noRoutines.evaluate().isNotEmpty) {
      await tester.tap(noRoutines);
    } else if (replace.evaluate().isNotEmpty) {
      await tester.tap(replace);
    }
    await settle(tester);

    expect(await savedFor(c), isEmpty);
    // 보낸 뒤 편집기가 새로 서도 되살아나지 않는다.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(await savedFor(c), isEmpty);
    expect(resumeDialog, findsNothing);
  });

  testWidgets('이미 이 화면에서 짜고 있으면 묻지 않는다', (tester) async {
    final c = await boot(tester);
    await goTo(tester, AppRoutes.coachingFor(a));
    await tapCentered(
      tester,
      find.byKey(const ValueKey<String>('generate-routine-options')),
    );
    await tester.pump(kCoachingAutosaveDelay + const Duration(seconds: 1));

    // 다른 탭에 다녀와도 탭 상태가 남는다 — 지금 짜던 것이 그대로다.
    await goTo(tester, AppRoutes.dashboard);
    await goTo(tester, AppRoutes.coachingFor(a));

    expect(resumeDialog, findsNothing);
    expect(await savedFor(c), hasLength(1));
  });
}

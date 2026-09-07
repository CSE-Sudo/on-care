import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';

import '../../helpers/pump_app.dart';

/// 데모가 보여 주는 시작 구성. 저장할 백엔드가 없는 빌드라 읽기 전용이고,
/// 실 API 가 '저장한 것이 없는 트레이너' 에게 주는 것과 같은 셋이다. (#920)
const List<ProgramTemplate> starterTemplates =
    MockTrainerProgramTemplateRepository.starters;

void main() {
  group('시작 구성', () {
    test('every template is usable: named, attributed, and non-empty', () {
      expect(starterTemplates, isNotEmpty);
      for (final template in starterTemplates) {
        expect(template.name, isNotEmpty);
        expect(template.goal, isNotEmpty, reason: '${template.name}에 대상이 없어요');
        expect(
          template.exercises,
          isNotEmpty,
          reason: '${template.name}에 운동이 없어요',
        );
      }
    });

    test('ids are unique so a list key cannot collide', () {
      final ids = starterTemplates.map((ProgramTemplate t) => t.id).toSet();
      expect(ids.length, starterTemplates.length);
    });

    test('totalMinutes sums the block', () {
      final template = starterTemplates.first;
      expect(
        template.totalMinutes,
        template.exercises.fold<int>(
          0,
          (int sum, TemplateExercise e) => sum + e.minutes,
        ),
      );
    });
  });

  group('AI 코칭 templates', () {
    Future<void> openCoaching(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.coaching,
      );
    }

    Future<void> revealTemplate(WidgetTester tester, String name) async {
      await tester.scrollUntilVisible(
        find.text(name),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('coaching-program-page-scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }

    testWidgets('the library lists the starter templates', (tester) async {
      await openCoaching(tester);

      await revealTemplate(tester, starterTemplates.first.name);

      expect(find.text('프로그램 템플릿'), findsOneWidget);
      expect(find.text(starterTemplates.first.name), findsOneWidget);
    });

    testWidgets('applying a template ADDS to the AI suggestions rather '
        'than replacing them', (tester) async {
      await openCoaching(tester);

      // 프로그램 정보 박스는 AI 루틴을 생성/반영하기 전까지 빈 상태로
      // 시작한다(#1028) — AI 요청 흐름(생성 → 기존 추천 선택 → 검토 완료 →
      // 템플릿에 반영)을 끝까지 밟아 이 회원의 AI 추천 루틴을 편집기에
      // 반영해 둔다. 안내 배너의 `편집기에 반영` 단축 버튼은 이제 없다
      // (#1028 후속).
      final scrollable = find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('coaching-program-page-scroll'),
            ),
            matching: find.byType(Scrollable),
          )
          .first;
      final generate = find.byKey(
        const ValueKey<String>('generate-routine-options'),
      );
      // `scrollUntilVisible` 은 대상이 트리에 붙는 순간 멈춘다 — 뷰포트
      // 가장자리에 걸칠 수 있어, 탭 전에 `ensureVisible`+`pump` 로 한 번 더
      // 자리를 잡는다(`_applyRecommendedRoutine`, `coaching_page_test.dart`
      // 와 같은 이유).
      await tester.scrollUntilVisible(generate, 150, scrollable: scrollable);
      await tester.ensureVisible(generate);
      await tester.pump();
      await tester.tap(generate);
      await tester.pumpAndSettle();
      final existing = find.byKey(
        const ValueKey<String>('routine-option-recommended'),
      );
      await tester.scrollUntilVisible(existing, 150, scrollable: scrollable);
      await tester.ensureVisible(existing);
      await tester.pump();
      await tester.tap(existing);
      await tester.pumpAndSettle();
      final complete = find.byKey(
        const ValueKey<String>('complete-routine-review'),
      );
      await tester.scrollUntilVisible(complete, 150, scrollable: scrollable);
      await tester.ensureVisible(complete);
      await tester.pump();
      await tester.tap(complete);
      await tester.pumpAndSettle();
      final apply = find.byKey(
        const ValueKey<String>('apply-routine-to-template'),
      );
      await tester.scrollUntilVisible(apply, 150, scrollable: scrollable);
      await tester.ensureVisible(apply);
      await tester.pump();
      await tester.tap(apply);
      await settle(tester);

      // A seeded AI suggestion for 김민수 that must survive the apply. AI
      // 흐름 자신의 검토 목록에도 같은 이름이 남아 있을 수 있어 편집기 안
      // 으로 범위를 좁힌다.
      final inEditor = find.descendant(
        of: find.byType(ProgramEditorWorkspace),
        matching: find.text('저강도 유산소 (걷기)'),
      );
      expect(inEditor, findsOneWidget);

      final template = starterTemplates.first;
      await revealTemplate(tester, template.name);
      await tester.drag(
        find.byKey(const ValueKey<String>('coaching-program-page-scroll')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(template.name));
      await settle(tester);

      // The template's exercises joined the composed routine…
      expect(find.text(template.exercises.first.name), findsWidgets);
      // …and the AI's own suggestion is still there.
      expect(inEditor, findsOneWidget);
      // Template-added items carry the template's own name as their source
      // badge, not the generic trainer-added label (#1029).
      expect(find.text('${template.name} 템플릿 추가'), findsWidgets);
    });

    testWidgets('식단·운동 영역과 전송 이력을 각각 한 번만 보여 준다', (tester) async {
      await openCoaching(tester);
      // 회원 요약 카드는 사라지고 그 자리를 식단·운동 영역이 가져갔다(#1027).
      expect(find.text('회원 요약'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('program-client-data-switcher')),
        findsOneWidget,
      );
      expect(find.text('전송 이력'), findsOneWidget);
    });
  });
}

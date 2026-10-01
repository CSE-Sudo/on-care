import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/personal_routine_box.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 템플릿을 적용하면 앞서 짠 개인운동이 진입 경로와 무관하게 비워진다 (#2874).
///
/// 회원을 지정하지 않고(`/coaching`) 들어오면 화면은 첫 회원을 그리지만 선택
/// 상태는 비어 있어, 상태 키로 지우는 정리가 빗나갔다.
const String _routineName = '가벼운 인터벌 러닝';

class _StaticSuggestionRepository
    implements TrainerRoutineSuggestionRepository {
  @override
  Future<List<RoutineSuggestion>> pending(String memberId) async =>
      const <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'sug-1',
          name: _routineName,
          minutes: 30,
          type: '유산소',
          reason: '숨이 차면 속도를 낮추세요',
        ),
      ];

  @override
  Future<void> approve(
    String suggestionId, {
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String? reason,
  }) async {}

  @override
  Future<void> dismiss(String suggestionId) async {}
}

Future<void> _open(WidgetTester tester, String at) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: at,
    seedClock: kMidWeekKst,
    extraOverrides: [
      trainerRoutineSuggestionRepositoryProvider.overrideWithValue(
        _StaticSuggestionRepository(),
      ),
    ],
  );
}

Future<void> _tapCentered(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 위저드에서 PT 를 건너뛰고 개인운동 단계를 마친다 — 개인운동이 들어간다.
Future<void> _composePersonalRoutines(WidgetTester tester) async {
  await _tapCentered(
    tester,
    find.byKey(const ValueKey<String>('skip-pt-program')),
  );
  await _tapCentered(
    tester,
    find.byKey(const ValueKey<String>('complete-personal-routines')),
  );
}

Future<void> _applyFirstTemplate(WidgetTester tester) async {
  final String id = MockTrainerProgramTemplateRepository.starters.first.id;
  await _tapCentered(
    tester,
    find.byKey(ValueKey<String>('template-card-$id')).first,
  );
}

/// PT 편집기 아래에 붙는 개인운동 박스(개인운동만 박스가 아닌 쪽).
PersonalRoutineBox _ptPersonalBox(WidgetTester tester) =>
    tester.widget<PersonalRoutineBox>(
      find.byWidgetPredicate(
        (w) => w is PersonalRoutineBox && !w.routineOnly,
        skipOffstage: false,
      ),
    );

void main() {
  final Map<String, String> entries = <String, String>{
    '회원 미지정 진입': AppRoutes.coaching,
    '회원 지정 진입': AppRoutes.coachingFor('seed-client-1'),
    '명단에 없는 회원 진입': AppRoutes.coachingFor('no-such-client'),
  };

  for (final MapEntry<String, String> entry in entries.entries) {
    testWidgets('${entry.key}: 템플릿을 적용하면 앞서 짠 개인운동이 비워진다', (tester) async {
      await _open(tester, entry.value);
      await _composePersonalRoutines(tester);
      // 개인운동이 들어가 있다(개인운동만 박스). 박스는 이름 뒤에 유형·양을
      // 붙인 한 줄로 그리므로 이름을 포함하는 줄을 찾는다.
      expect(find.textContaining(_routineName), findsWidgets);

      await _applyFirstTemplate(tester);

      // 템플릿은 PT 프로그램이다 — 편집기가 서고, 그 아래 개인운동 박스는
      // 비어 있다. 전송 확인창은 같은 목록을 읽으므로 거기에도 실리지 않는다.
      expect(find.byType(ProgramEditorWorkspace), findsOneWidget);
      expect(_ptPersonalBox(tester).routines, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('personal-routine-box-empty')),
        findsOneWidget,
      );
      expect(find.textContaining(_routineName), findsNothing);
    });
  }
}

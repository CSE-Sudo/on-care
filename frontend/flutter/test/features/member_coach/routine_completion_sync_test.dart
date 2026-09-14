/// 추천 개인운동 체크가 운동 현황에 바로 반영되고, 다시 누르면 되묻고 되돌린다.
/// (#1131)
///
/// 실서버는 완료를 받으면 회원 운동 기록 한 건(`assigned_routine_id`)을 만들고
/// 취소하면 지운다. 데모(mock) 경로에는 그 일을 할 서버가 없어
/// [MockMemberCoachRepository] 가 운동 저장소를 통해 같은 일을 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  late MockExerciseRepository exercise;
  late MockMemberCoachRepository coach;

  setUp(() {
    exercise = MockExerciseRepository();
    coach = MockMemberCoachRepository(exercise: exercise);
  });

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'http://localhost',
              useMockApi: true,
            ),
          ),
          memberCoachRepositoryProvider.overrideWithValue(coach),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: AiCoachingCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 이번 주 총 소모 칼로리 — 운동 현황이 읽는 그 값이다.
  ///
  /// 대역이 실제 지연을 두고 답하므로 [WidgetTester.runAsync] 안에서 읽는다 —
  /// 가짜 시계 위에서 그냥 await 하면 영원히 풀리지 않는다.
  Future<int> weekCalories(WidgetTester tester) async =>
      (await tester.runAsync(() => exercise.fetchThisWeek()))!.totalCalories;

  Future<List<CoachRoutine>> routinesOf(WidgetTester tester) async =>
      (await tester.runAsync(() => coach.fetchRoutines()))!;

  testWidgets('체크하면 이번 주 기록에 바로 더해진다', (WidgetTester tester) async {
    await pumpCard(tester);
    final int before = await weekCalories(tester);

    final List<CoachRoutine> routines = await routinesOf(tester);
    final CoachRoutine target = routines.firstWhere(
      (CoachRoutine r) => !r.completed,
    );

    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRoutineCompletion')));
    await tester.pumpAndSettle();

    expect(
      await weekCalories(tester),
      greaterThan(before),
      reason: '체크했는데 이번 주 소모 칼로리가 그대로다',
    );
  });

  testWidgets('체크를 다시 누르면 되묻고, 확인하면 기록에서 빠진다', (WidgetTester tester) async {
    await pumpCard(tester);
    final int before = await weekCalories(tester);

    final List<CoachRoutine> routines = await routinesOf(tester);
    final CoachRoutine target = routines.firstWhere(
      (CoachRoutine r) => !r.completed,
    );

    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRoutineCompletion')));
    await tester.pumpAndSettle();
    expect(await weekCalories(tester), greaterThan(before));

    // 체크된 것을 다시 누르면 바로 풀리지 않고 먼저 묻는다.
    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    // 확인창은 공용 [AppDialog] 다(#1702). 확정 버튼은 그 창 안의 `완료 취소` 다.
    final AppLocalizations undoL = AppLocalizations.of(
      tester.element(find.byType(AiCoachingCard)),
    );
    final Finder confirmUndo = find.descendant(
      of: find.byType(AppDialog),
      matching: find.widgetWithText(AppButton, undoL.coachRoutineUndo),
    );
    expect(confirmUndo, findsOneWidget);

    await tester.tap(confirmUndo);
    await tester.pumpAndSettle();

    expect(
      await weekCalories(tester),
      before,
      reason: '완료를 취소했는데 기록이 남아 있다',
    );
    final CoachRoutine after = (await routinesOf(tester)).firstWhere(
      (CoachRoutine r) => r.id == target.id,
    );
    expect(after.completed, isFalse);
  });

  testWidgets('되묻는 창에서 취소하면 아무 일도 없다', (WidgetTester tester) async {
    await pumpCard(tester);

    final List<CoachRoutine> routines = await routinesOf(tester);
    final CoachRoutine target = routines.firstWhere(
      (CoachRoutine r) => !r.completed,
    );

    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRoutineCompletion')));
    await tester.pumpAndSettle();
    final int afterCheck = await weekCalories(tester);

    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(AiCoachingCard)),
    );
    await tester.tap(find.text(l.actionCancel).last);
    await tester.pumpAndSettle();

    expect(await weekCalories(tester), afterCheck);
  });
}

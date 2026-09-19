/// 건강 목표 숫자의 범위 안내 (#1888).
///
/// 목표는 회원과 트레이너가 **같은 컬럼**을 고치는 값이고, 서버는 두 경로에
/// 같은 범위를 둔다. 화면이 그 기준을 미리 말해 주지 않으면, 범위 밖 값은
/// 서버에서 422 로 되돌아와 이유를 알 수 없는 "저장에 실패했어요" 토스트만
/// 남는다 — 어느 칸이 문제인지는 화면에서만 말해 줄 수 있다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 저장이 실제로 불렸는지 세는 저장소.
class _CountingAccountRepository extends MockAccountRepository {
  _CountingAccountRepository({required super.profile});

  int saves = 0;

  @override
  Future<UserProfile> updateHealthGoals({
    String? conditions,
    String? goals,
    GoalUpdate? dailyCalories,
    GoalUpdate? dailySodiumMg,
    GoalUpdate? dailySugarG,
    GoalUpdate? dailyCarbsG,
    GoalUpdate? dailyProteinG,
    GoalUpdate? dailyFatG,
    GoalUpdate? weeklyWorkoutGoal,
    GoalUpdate? weeklyExerciseMinutesGoal,
    GoalUpdate? weeklyBurnGoal,
    GoalUpdate? dailyBurnKcal,
    GoalUpdate? weeklyCardioMinutes,
    GoalUpdate? weeklyStrengthSets,
    GoalUpdate? weeklyFlexibilityMinutes,
  }) {
    saves++;
    return super.updateHealthGoals(
      conditions: conditions,
      goals: goals,
      dailyCalories: dailyCalories,
      dailySodiumMg: dailySodiumMg,
      dailySugarG: dailySugarG,
      dailyCarbsG: dailyCarbsG,
      dailyProteinG: dailyProteinG,
      dailyFatG: dailyFatG,
      weeklyWorkoutGoal: weeklyWorkoutGoal,
      weeklyExerciseMinutesGoal: weeklyExerciseMinutesGoal,
      weeklyBurnGoal: weeklyBurnGoal,
      dailyBurnKcal: dailyBurnKcal,
      weeklyCardioMinutes: weeklyCardioMinutes,
      weeklyStrengthSets: weeklyStrengthSets,
      weeklyFlexibilityMinutes: weeklyFlexibilityMinutes,
    );
  }
}

const UserProfile _profile = UserProfile(
  id: 'user-goal-range',
  name: '범위',
  email: 'range@oncare.com',
  dailyCalories: 2000,
  dailySodiumMg: 1500,
  dailySugarG: 40,
  dailyCarbsG: 250,
  dailyProteinG: 120,
  dailyFatG: 50,
  dailyBurnKcal: 400,
  weeklyCardioMinutes: 150,
  weeklyStrengthSets: 30,
  weeklyFlexibilityMinutes: 60,
);

Future<(AppLocalizations, _CountingAccountRepository)> _openGoals(
  WidgetTester tester,
) async {
  final _CountingAccountRepository repository = _CountingAccountRepository(
    profile: _profile,
  );
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HealthGoalsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    AppLocalizations.of(tester.element(find.byType(HealthGoalsPage))),
    repository,
  );
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final Finder field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  final Finder saveButton = find.text('저장');
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

String _rangeText(AppLocalizations l, AppGoalRange range) =>
    l.myGoalRange(range.min, range.max);

void main() {
  testWidgets('상한을 넘긴 칼로리는 보내지 않고 칸 아래에 범위를 알린다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openGoals(tester);

    await _enter(tester, 'goalCaloriesField', '99999');
    await _save(tester);

    expect(
      find.text(_rangeText(l, AppGoalRanges.dailyCalories)),
      findsOneWidget,
    );
    expect(repo.saves, 0, reason: '서버에서 422 가 될 값은 보내지 않는다');
  });

  testWidgets('하한 아래 칼로리도 막는다 — 굶는 목표는 셀 수 없다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openGoals(tester);

    await _enter(tester, 'goalCaloriesField', '100');
    await _save(tester);

    expect(
      find.text(_rangeText(l, AppGoalRanges.dailyCalories)),
      findsOneWidget,
    );
    expect(repo.saves, 0);
  });

  testWidgets('한 주를 넘는 유산소 목표를 막는다', (WidgetTester tester) async {
    // 한 주는 10,080분이다 — 그보다 큰 목표는 달성률을 셀 수 없다.
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openGoals(tester);

    await _enter(tester, 'goalCardioField', '100000');
    await _save(tester);

    expect(
      find.text(_rangeText(l, AppGoalRanges.weeklyCardioMinutes)),
      findsOneWidget,
    );
    expect(repo.saves, 0);
  });

  testWidgets('경계값 바로 안은 그대로 저장된다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openGoals(tester);

    await _enter(
      tester,
      'goalCaloriesField',
      '${AppGoalRanges.dailyCalories.max}',
    );
    await _enter(
      tester,
      'goalCardioField',
      '${AppGoalRanges.weeklyCardioMinutes.max}',
    );
    await _save(tester);

    expect(
      find.text(_rangeText(l, AppGoalRanges.dailyCalories)),
      findsNothing,
    );
    expect(repo.saves, 1);
  });

  testWidgets('빈 칸은 오류가 아니다 — 목표 해제는 할 수 있는 일이다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _CountingAccountRepository repo) =
        await _openGoals(tester);

    await _enter(tester, 'goalCardioField', '');
    await _save(tester);

    expect(
      find.text(_rangeText(l, AppGoalRanges.weeklyCardioMinutes)),
      findsNothing,
    );
    expect(repo.saves, 1);
  });

  testWidgets('오류를 보인 뒤 칸을 고치면 문구가 사라진다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _openGoals(tester);

    await _enter(tester, 'goalCaloriesField', '99999');
    await _save(tester);
    expect(
      find.text(_rangeText(l, AppGoalRanges.dailyCalories)),
      findsOneWidget,
    );

    await _enter(tester, 'goalCaloriesField', '2100');
    expect(find.text(_rangeText(l, AppGoalRanges.dailyCalories)), findsNothing);
  });
}

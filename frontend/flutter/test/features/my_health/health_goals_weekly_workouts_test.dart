/// 건강 목표의 주간 운동 횟수 — 주간 운동 챌린지의 목표가 되는 칸. (#3361)
///
/// 챌린지는 참가할 때 이 값을 목표로 건다(없으면 3일). 회원 앱에 이 칸이 없어
/// 담당이 없는 회원의 챌린지는 언제나 주 3일이었다. 챌린지가 세는 것은 운동한
/// **날**이라 1~7 만 받고, 다른 목표 칸처럼 바꾼 칸만 보낸다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';
import '../benefits/fake_challenge_repository.dart';

/// 저장에 실린 주간 운동 횟수를 적어 두는 저장소.
class _RecordingAccountRepository extends MockAccountRepository {
  _RecordingAccountRepository({required super.profile});

  int saves = 0;

  /// 마지막 저장의 주간 운동 횟수. 보내지 않았으면 null 이다.
  GoalUpdate? lastWeeklyWorkoutGoal;

  /// 마지막 저장의 칼로리 — 다른 칸이 함께 나가지 않는지 본다.
  GoalUpdate? lastDailyCalories;

  @override
  Future<UserProfile> updateHealthGoals({
    String? conditions,
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
    lastWeeklyWorkoutGoal = weeklyWorkoutGoal;
    lastDailyCalories = dailyCalories;
    return super.updateHealthGoals(
      conditions: conditions,
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

/// 다른 목표는 모두 세웠고 주간 운동 횟수만 [weeklyWorkoutGoal] 인 회원.
UserProfile _profile({int? weeklyWorkoutGoal}) => UserProfile(
  id: 'user-weekly-workouts',
  name: '횟수',
  email: 'workouts@oncare.com',
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
  weeklyWorkoutGoal: weeklyWorkoutGoal,
);

Future<(_RecordingAccountRepository, FakeChallengeRepository)> _open(
  WidgetTester tester, {
  int? weeklyWorkoutGoal,
  Locale locale = const Locale('ko'),
}) async {
  final _RecordingAccountRepository repository = _RecordingAccountRepository(
    profile: _profile(weeklyWorkoutGoal: weeklyWorkoutGoal),
  );
  final FakeChallengeRepository challenges = FakeChallengeRepository();
  await tester.binding.setSurfaceSize(const Size(900, 2800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repository),
        challengeRepositoryProvider.overrideWithValue(challenges),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // 사용처의 챌린지 카드처럼 이번 주 챌린지를 보고 있는 화면이 뒤에 있다.
        home: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            ref.watch(weeklyChallengeProvider);
            return child!;
          },
          child: const HealthGoalsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, challenges);
}

Future<void> _beginEdit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('goalsEditButton')));
  await tester.pumpAndSettle();
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

Text _value(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('goalValue-workouts')));

void main() {
  testWidgets('세운 적 없으면 챌린지 기본 3일을 흐리게 적고 쓰임을 알린다', (tester) async {
    await _open(tester);

    expect(find.text('주간 운동 횟수 (일)'), findsOneWidget);
    expect(_value(tester).data, '$kDefaultWeeklyWorkoutDays');
    expect(_value(tester).style!.color, OnCareColors.textTertiary);
    expect(
      find.text(
        keepWords('주간 운동 챌린지의 목표가 돼요. 정하지 않으면 3일이고, 이미 참가한 주의 목표는 바뀌지 않아요.'),
      ),
      findsOneWidget,
    );
    // 운동 네 칸은 다 세웠다 — 이 칸이 비었다고 그 카드에 각주가 서지 않는다.
    expect(find.byKey(const Key('goalUnsetHint')), findsNothing);
  });

  testWidgets('세운 값은 또렷하게 읽힌다', (tester) async {
    await _open(tester, weeklyWorkoutGoal: 5);

    expect(_value(tester).data, '5');
    expect(_value(tester).style!.color, OnCareColors.textPrimary);
  });

  testWidgets('횟수를 정하면 그 칸만 보내고 이번 주 챌린지를 다시 읽는다', (tester) async {
    final (
      _RecordingAccountRepository repo,
      FakeChallengeRepository challenges,
    ) = await _open(
      tester,
    );
    final int before = challenges.weeklyCalls;
    await _beginEdit(tester);

    await _enter(tester, 'goalWorkoutsField', '5');
    await _save(tester);

    expect(repo.saves, 1);
    expect(repo.lastWeeklyWorkoutGoal?.value, 5);
    expect(repo.lastDailyCalories, isNull, reason: '손대지 않은 칸은 보내지 않는다');
    expect(_value(tester).data, '5');
    expect(_value(tester).style!.color, OnCareColors.textPrimary);
    // 다음에 참가할 챌린지의 목표가 바뀌었다 — 카드가 옛 횟수를 적지 않게 한다.
    expect(challenges.weeklyCalls, greaterThan(before));
  });

  testWidgets('손대지 않고 저장하면 기본값이 목표로 굳지 않는다', (tester) async {
    final (_RecordingAccountRepository repo, _) = await _open(tester);
    await _beginEdit(tester);

    await _enter(tester, 'goalCaloriesField', '2100');
    await _save(tester);

    expect(repo.saves, 1);
    expect(repo.lastDailyCalories?.value, 2100);
    expect(repo.lastWeeklyWorkoutGoal, isNull);
    expect(_value(tester).style!.color, OnCareColors.textTertiary);
  });

  testWidgets('다른 칸만 고치면 챌린지를 다시 읽지 않는다', (tester) async {
    final (_, FakeChallengeRepository challenges) = await _open(
      tester,
      weeklyWorkoutGoal: 4,
    );
    final int before = challenges.weeklyCalls;
    await _beginEdit(tester);

    await _enter(tester, 'goalCaloriesField', '2100');
    await _save(tester);

    expect(challenges.weeklyCalls, before);
  });

  testWidgets('칸을 비우면 목표 해제로 나간다 — 챌린지는 다시 3일이다', (tester) async {
    final (_RecordingAccountRepository repo, _) = await _open(
      tester,
      weeklyWorkoutGoal: 5,
    );
    await _beginEdit(tester);

    await _enter(tester, 'goalWorkoutsField', '');
    await _save(tester);

    expect(repo.saves, 1);
    expect(repo.lastWeeklyWorkoutGoal, isNotNull);
    expect(repo.lastWeeklyWorkoutGoal!.value, isNull);
    expect(_value(tester).data, '$kDefaultWeeklyWorkoutDays');
  });

  for (final String outOfRange in <String>['0', '8', '21']) {
    testWidgets('한 주에 채울 수 없는 $outOfRange일은 보내지 않고 범위를 알린다', (tester) async {
      final (_RecordingAccountRepository repo, _) = await _open(tester);
      await _beginEdit(tester);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(HealthGoalsPage)),
      );

      await _enter(tester, 'goalWorkoutsField', outOfRange);
      await _save(tester);

      expect(
        find.text(
          l.myGoalRange(
            AppGoalRanges.weeklyWorkoutDays.min,
            AppGoalRanges.weeklyWorkoutDays.max,
          ),
        ),
        findsOneWidget,
      );
      expect(repo.saves, 0);
    });
  }

  for (final int edge in <int>[1, 7]) {
    testWidgets('경계값 $edge일은 그대로 저장된다', (tester) async {
      final (_RecordingAccountRepository repo, _) = await _open(tester);
      await _beginEdit(tester);

      await _enter(tester, 'goalWorkoutsField', '$edge');
      await _save(tester);

      expect(repo.saves, 1);
      expect(repo.lastWeeklyWorkoutGoal?.value, edge);
    });
  }

  testWidgets('영어에서도 칸 이름과 안내가 번역된다', (tester) async {
    await _open(tester, locale: const Locale('en'));

    expect(find.text('Weekly workouts (days)'), findsOneWidget);
    expect(find.byKey(const Key('goalWorkoutsHint')), findsOneWidget);
    expect(
      find.textContaining(keepWords('weekly workout challenge goal')),
      findsOneWidget,
    );
  });

  test('범위는 챌린지가 세는 한 주의 날 수다', () {
    expect(AppGoalRanges.weeklyWorkoutDays.min, 1);
    expect(AppGoalRanges.weeklyWorkoutDays.max, 7);
    expect(AppGoalRanges.weeklyWorkoutDays.rejects(''), isFalse);
  });
}

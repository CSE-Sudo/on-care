import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';

import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 세우지 않은 목표는 화면을 열고 저장해도 세워지지 않는다. (PR #900 리뷰)
///
/// `null` 은 *미설정 또는 목표 해제*라는 계약이고, 서버는 키가 없으면 그대로
/// 두고 키가 `null` 로 오면 해제한다.
///
/// 칸은 이제 권장값이 **채워진 채로** 열린다 — 예전처럼 비워 두면 식단 여섯
/// 칸만 까맣게 차고 운동 네 칸은 옅은 자리표시로 남아, 같은 시트의 위아래가
/// 서로 다른 상태로 읽혔다. 대신 화면이 *회원이 손댄 칸*을 따로 기억해서, 손대지
/// 않은 칸은 여전히 `null` 로 내보낸다. 보이는 것과 저장되는 것이 다른 자리라
/// 여기서 못 박아 둔다.

/// 마지막으로 받은 인자를 잡아 두는 저장소 — 화면이 무엇을 보냈는지 본다.
class _RecordingAccountRepository extends MockAccountRepository {
  _RecordingAccountRepository({required super.profile});

  GoalUpdate? lastCarbs;
  GoalUpdate? lastProtein;
  bool called = false;

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
    called = true;
    lastCarbs = dailyCarbsG;
    lastProtein = dailyProteinG;
    return super.updateHealthGoals(
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

/// 탄수화물만 세우지 않은 프로필.
const UserProfile _carbsUnset = UserProfile(
  id: 'user-null-carbs',
  name: '목표없음',
  email: 'none@oncare.com',
  dailyCalories: 1800,
  dailySodiumMg: 1500,
  dailySugarG: 40,
  dailyProteinG: 120,
  dailyFatG: 50,
  weeklyWorkoutGoal: 3,
  weeklyExerciseMinutesGoal: 150,
  weeklyBurnGoal: 500,
);

Future<_RecordingAccountRepository> _openHealthGoals(
  WidgetTester tester,
) async {
  final repository = _RecordingAccountRepository(profile: _carbsUnset);
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
  return repository;
}

TextField _field(WidgetTester tester, String key) => tester.widget<TextField>(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
);

Future<void> _save(WidgetTester tester) async {
  final Finder saveButton = find.text('저장');
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  // 저장 알림 배너는 3초 뒤 스스로 닫힌다. 그 타이머를 흘려보내지 않으면
  // 위젯 트리가 사라진 뒤에도 타이머가 남아 테스트가 깨진다.
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('세우지 않은 목표도 권장값이 채워진 채로 열린다', (tester) async {
    await _openHealthGoals(tester);

    // 세운 적 없는 탄수화물도 빈 칸이 아니라 기본값이 적혀 있다.
    expect(
      _field(tester, 'goalCarbsField').controller!.text,
      '${UserProfile.defaultDailyCarbsG}',
    );
    // 세워 둔 목표는 저장된 값 그대로다.
    expect(_field(tester, 'goalProteinField').controller!.text, '120');
    // 운동 네 칸도 같이 찬다 — 식단만 까맣고 운동만 회색이던 자리다.
    expect(
      _field(tester, 'goalDailyBurnField').controller!.text,
      '${kDefaultExerciseLoadGoals.dailyBurnKcal.round()}',
    );
    expect(
      _field(tester, 'goalCardioField').controller!.text,
      '${kDefaultExerciseLoadGoals.weeklyCardioMinutes.round()}',
    );
  });

  testWidgets('채워진 권장값을 한 번 고치면 그때부터는 그 값이 저장된다', (tester) async {
    final repository = await _openHealthGoals(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('goalCarbsField')),
        matching: find.byType(TextField),
      ),
      '300',
    );
    await tester.pump();
    await _save(tester);

    expect(repository.lastCarbs!.value, 300);
    expect((await repository.fetchProfile()).dailyCarbsG, 300);
  });

  testWidgets('열고 그대로 저장해도 세우지 않은 목표는 null 로 남는다', (tester) async {
    final repository = await _openHealthGoals(tester);

    await _save(tester);

    expect(repository.called, isTrue);
    // 빈 칸은 '건드리지 않음'이 아니라 '값 없음'으로 나간다 — 그래야 회원이
    // 지운 목표가 되살아나지 않는다.
    expect(repository.lastCarbs, isNotNull);
    expect(repository.lastCarbs!.value, isNull);
    expect(repository.lastProtein!.value, 120);

    final UserProfile saved = await repository.fetchProfile();
    expect(saved.dailyCarbsG, isNull, reason: '기본값이 목표로 굳었다');
    expect(saved.dailyProteinG, 120);
    // 화면이 아니라 getter 가 기본값을 책임진다.
    expect(saved.effectiveDailyCarbsG, UserProfile.defaultDailyCarbsG);
  });

  testWidgets('세워 둔 목표를 지우고 저장하면 해제된다', (tester) async {
    final repository = await _openHealthGoals(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('goalProteinField')),
        matching: find.byType(TextField),
      ),
      '',
    );
    await tester.pump();
    await _save(tester);

    expect(repository.lastProtein!.value, isNull);
    expect((await repository.fetchProfile()).dailyProteinG, isNull);
  });
}

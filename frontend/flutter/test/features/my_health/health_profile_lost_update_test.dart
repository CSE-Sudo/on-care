/// 담당 트레이너가 바꾼 값을 회원 저장이 되돌리지 않는다. (#2655)
///
/// 건강 목표·신체 칸은 회원과 담당 트레이너가 함께 고친다. 예전에는 화면이
/// 들고 있던 옛 프로필로 칸을 채우고, 저장할 때 모든 칸을 보냈다 — 트레이너가
/// 칼로리를 바꾼 뒤 회원이 나트륨만 고쳐 저장하면 칼로리가 옛 값으로 돌아갔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const UserProfile _start = UserProfile(
  id: 'user-lost-update',
  name: '회원',
  email: 'member@oncare.com',
  conditions: '체중 감량, 무릎 통증 주의',
  dailyCalories: 1800,
  dailySodiumMg: 2000,
);

/// 서버 역할 — 트레이너가 끼어들어 값을 바꿀 수 있고, 회원이 보낸 인자를 남긴다.
class _Server extends MockAccountRepository {
  _Server() : super(profile: _start);

  String? sentConditions;
  GoalUpdate? sentCalories;
  GoalUpdate? sentSodium;
  int saves = 0;

  /// 트레이너가 같은 칸을 고쳤다.
  Future<void> trainerEdits({String? conditions, int? calories}) =>
      super.updateHealthGoals(
        conditions: conditions,
        dailyCalories: calories == null ? null : GoalUpdate(calories),
      );

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
    sentConditions = conditions;
    sentCalories = dailyCalories;
    sentSodium = dailySodiumMg;
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

Future<ProviderContainer> _open(WidgetTester tester, _Server server) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[accountRepositoryProvider.overrideWithValue(server)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  return container;
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('저장'));
  await tester.tap(find.text('저장'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  group('rebaseConditions', () {
    test('목표만 바꾸면 최신 주의사항 위에 목표를 얹는다', () {
      expect(
        rebaseConditions(
          base: '체중 감량, 무릎 통증 주의',
          latest: '체중 감량, 허리 디스크',
          focus: <String>{'재활'},
          notes: '무릎 통증 주의',
        ),
        '재활, 허리 디스크',
      );
    });

    test('글만 바꾸면 최신 목표 위에 글을 얹는다', () {
      expect(
        rebaseConditions(
          base: '체중 감량, 무릎 통증 주의',
          latest: '근력 향상, 무릎 통증 주의',
          focus: <String>{'체중 감량'},
          notes: '무릎 통증 주의, 러닝 자제',
        ),
        '근력 향상, 무릎 통증 주의, 러닝 자제',
      );
    });

    test('목표 순서만 달라진 것은 바꾼 것이 아니다', () {
      expect(
        conditionsEdits(
          base: '체중 감량, 재활',
          focus: <String>{'재활', '체중 감량'},
          notes: '체중 감량, 재활',
        ),
        (focus: false, notes: false),
      );
    });
  });

  testWidgets('편집을 열면 트레이너가 방금 바꾼 값이 칸에 찬다', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    await server.trainerEdits(calories: 2100);

    await tester.tap(find.byKey(const Key('goalsEditButton')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_field('goalCaloriesField')).controller!.text,
      '2100',
    );
  });

  testWidgets('나트륨만 고친 저장은 편집 중 트레이너가 바꾼 칼로리를 덮지 않는다', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    await tester.tap(find.byKey(const Key('goalsEditButton')));
    await tester.pumpAndSettle();

    // 회원이 칸을 연 뒤에 트레이너가 칼로리와 주의사항을 바꿨다.
    await server.trainerEdits(calories: 2100, conditions: '체중 감량, 허리 디스크');
    await tester.enterText(_field('goalSodiumField'), '1800');
    await _save(tester);

    expect(server.saves, 1);
    expect(server.sentSodium, const GoalUpdate(1800));
    expect(server.sentCalories, isNull, reason: '고치지 않은 칸은 보내지 않는다');
    expect(server.sentConditions, isNull);
    final UserProfile saved = await server.fetchProfile();
    expect(saved.dailyCalories, 2100);
    expect(saved.conditions, '체중 감량, 허리 디스크');
  });

  testWidgets('목표 칩을 바꿔도 트레이너가 바꾼 주의사항은 남는다', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    await tester.tap(find.byKey(const Key('goalsEditButton')));
    await tester.pumpAndSettle();

    await server.trainerEdits(conditions: '체중 감량, 허리 디스크');
    await tester.tap(find.byKey(const ValueKey<String>('goal-focus-재활')));
    await tester.pumpAndSettle();
    await _save(tester);

    expect(server.sentConditions, '체중 감량, 재활, 허리 디스크');
    expect(server.sentCalories, isNull);
  });
  testWidgets('주의사항만 고쳐도 트레이너가 바꾼 목표 칩은 남는다 (#2619)', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    await tester.tap(find.byKey(const Key('goalsEditButton')));
    await tester.pumpAndSettle();

    await server.trainerEdits(conditions: '근력 향상, 무릎 통증 주의');
    await tester.enterText(_field('goalConditionsField'), '무릎 통증 주의, 러닝 자제');
    await _save(tester);

    expect(server.sentConditions, '근력 향상, 무릎 통증 주의, 러닝 자제');
  });
}

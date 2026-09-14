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

class _FailingAccountRepository extends MockAccountRepository {
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
  }) async {
    throw StateError('save failed');
  }
}

Future<void> _openHealthGoals(
  WidgetTester tester,
  MockAccountRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 2000));
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
        initialRoute: '/goals',
        routes: <String, WidgetBuilder>{
          '/': (_) => const Scaffold(body: Text('MY 화면')),
          '/goals': (_) => const HealthGoalsPage(),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  final Finder saveButton = find.text('저장');
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // 건강 목표 저장 알림은 시트를 닫은 **뒤에** 도착한다. 예전에는 이 자리만
  // 위쪽 배너로 떠서 닫기 버튼을 눌러야 사라졌다(#1259). 지금은 다른 화면과
  // 같은 토스트로 알린다.
  testWidgets('저장 성공 알림은 이전 화면에서 토스트로 뜬다', (tester) async {
    await _openHealthGoals(tester, MockAccountRepository());

    await _tapSave(tester);

    expect(find.text('건강 목표가 저장되었어요'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    // 위쪽에 뜬다 — 아래로 되돌아가면 시트·하단 바에 가리므로 여기서 걸린다.
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.text('건강 목표가 저장되었어요')).center.dy,
      lessThan(screen.height / 4),
    );
    expect(find.text('식단 목표'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('저장 실패 알림도 현재 화면에서 토스트로 뜬다', (tester) async {
    await _openHealthGoals(tester, _FailingAccountRepository());

    await _tapSave(tester);

    expect(find.text('저장에 실패했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('식단 목표'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}

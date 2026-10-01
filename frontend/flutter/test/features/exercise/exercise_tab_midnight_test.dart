/// 운동 탭도 연 채 자정을 넘기면 새 오늘로 옮긴다 — 식단 탭과 같은 규칙. (#2882)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const ExerciseWeek _week = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[60, 45, 70, 30, 55, 40, 65],
  dailyCalories: <double>[300, 220, 350, 150, 270, 200, 320],
  cardioMinutes: <double>[30, 20, 35, 15, 25, 20, 30],
  strengthMinutes: <double>[20, 15, 25, 10, 20, 12, 25],
  stretchingMinutes: <double>[10, 10, 10, 5, 10, 8, 10],
  dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
  totalMinutes: 365,
  totalCalories: 1810,
  streakDays: 7,
  aiCoachMessage: '꾸준히 운동해 보세요.',
);

Future<void Function(DateTime)> _pump(WidgetTester tester) async {
  // 2026-08-19(수) 23:50 KST 에 연다.
  DateTime now = DateTime(2026, 8, 19, 23, 50);
  debugNowKstOverride = () => now;
  addTearDown(() => debugNowKstOverride = null);
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://example.test',
            useMockApi: true,
          ),
        ),
        accountRepositoryProvider.overrideWithValue(
          MockAccountRepository(
            profile: const UserProfile(
              id: 'member',
              name: '테스트',
              email: 'member@example.com',
            ),
          ),
        ),
        exerciseWeekProvider.overrideWith((ref) async => _week),
        memberCoachRepositoryProvider.overrideWithValue(
          MockMemberCoachRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ExercisePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (DateTime next) {
    now = next;
    // 셸이 앱 복귀 때 하는 일 — 운동 주간을 다시 읽는다.
    ProviderScope.containerOf(
      tester.element(find.byType(ExercisePage)),
    ).invalidate(exerciseWeekProvider);
  };
}

void main() {
  testWidgets('오늘을 보던 중 자정을 넘기면 오늘 카드가 그대로 선다', (WidgetTester tester) async {
    final void Function(DateTime) advance = await _pump(tester);
    expect(find.byType(ExerciseDayLoadCard), findsOneWidget);

    advance(DateTime(2026, 8, 20, 0, 10));
    await tester.pumpAndSettle();

    // 어제를 고른 상태로 남으면 오늘 카드 대신 그날 기록 화면이 선다.
    expect(find.byType(ExerciseDayLoadCard), findsOneWidget);
  });

  testWidgets('지난 날짜를 고른 채면 자정 뒤에도 그 날에 머문다', (WidgetTester tester) async {
    final void Function(DateTime) advance = await _pump(tester);
    await tester.tap(find.text('18').first);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDayLoadCard), findsNothing);

    advance(DateTime(2026, 8, 20, 0, 10));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDayLoadCard), findsNothing);
  });
}

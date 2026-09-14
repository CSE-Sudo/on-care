/// 운동 기록 탭의 기본 조회 기준. (#863)
///
/// 식단 탭은 `오늘` 로 열리는데 운동 기록만 `이번 주` 로 열려, 같은 회원 기록
/// 화면인데도 첫 화면의 기준이 탭마다 달랐다. 두 탭 모두 "오늘을 보고, 필요하면
/// 주로 넓힌다" 는 흐름을 따른다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
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

void main() {
  // 요일마다 세 종류가 모두 있는 주.
  const ExerciseWeek week = ExerciseWeek(
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

  Future<void> pumpExercise(WidgetTester tester) async {
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
          exerciseWeekProvider.overrideWith((ref) async => week),
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
    await tester.pump();
    await tester.pump();
  }

  testWidgets('첫 진입은 오늘 기준이다 — 오늘 카드가 보인다', (WidgetTester tester) async {
    await pumpExercise(tester);
    await tester.pumpAndSettle();

    // 세 기간이 같은 카드 자리를 쓰므로 카드 종류로 가른다. 소모 칼로리
    // 머리말은 도넛 안으로 들어갔다 (#1127).
    expect(find.byType(ExerciseDayLoadCard), findsOneWidget);
  });

  testWidgets('이번 주를 고르면 주간 화면이 나온다', (WidgetTester tester) async {
    await pumpExercise(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('이번 주'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDayLoadCard), findsNothing);

    // 오늘 ↔ 이번 주 왕복이 상태를 망가뜨리지 않는다.
    // 기간 토글은 패키지 세그먼트라 칸마다 키가 없다 — 토글 안의 라벨로 누른다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('exercise-period-toggle')),
        matching: find.text('오늘'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseDayLoadCard), findsOneWidget);
  });
}

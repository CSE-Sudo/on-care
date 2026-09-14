/// 좁은 화면·큰 글자 배율에서 운동 탭이 넘치지 않는지 (#766).
///
/// 320px 는 아이폰 SE 1세대·구형 안드로이드의 논리 폭이고, 배율 2.0 은 접근성
/// 설정의 상한에 가깝다. 예전에는 이 조건에서 상단 탭·날짜 스트립·기간 토글·
/// 그래프 범례·PT 카드의 칩과 운동 항목이 각각 넘쳐, 글자가 잘리거나 노랑·검정
/// 줄무늬가 그려졌다.
///
/// **한국어와 영어를 모두 검증한다.** 영어는 라벨이 훨씬 길어(`This month` vs
/// `이번 달`) 기본 배율에서도 넘쳤다 — 식단 탭에서 en 만 따로 새던 일(#743)을
/// 여기서 되풀이하지 않으려고 처음부터 두 로케일을 함께 돈다.
///
/// 높이를 넉넉히 두는 이유는 `ListView` 가 보이는 자식만 만들기 때문이다 —
/// 짧은 화면에서는 아래쪽 카드가 아예 그려지지 않아 검증 대상이 사라진다.
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
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppSectionHeader;

void main() {
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

  Future<void> pumpExercise(
    WidgetTester tester, {
    required String lang,
    required Size size,
  }) async {
    await tester.binding.setSurfaceSize(size);
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
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ExercisePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('운동 탭 좁은 화면 레이아웃 (#766)', () {
    for (final String lang in <String>['ko', 'en']) {
      for (final double scale in <double>[1.0, 1.3, 1.6, 2.0]) {
        testWidgets('폭 320 · $lang · 글자 배율 $scale 에서 넘치지 않는다', (
          WidgetTester tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await pumpExercise(
            tester,
            lang: lang,
            // 높이는 카드가 모두 그려질 만큼 — 배율 2.0 에서도 아래쪽 PT 카드가
            // 화면에 들어와야 그 줄들이 검증된다.
            size: const Size(320, 6000),
          );

          // overflow 는 렌더링 예외로 보고된다. 예외 없이 그려졌다면 넘친
          // 곳이 없다는 뜻이다.
          expect(tester.takeException(), isNull);
          expect(find.byType(ExercisePage), findsOneWidget);
        });
      }
    }

    testWidgets('기간 토글은 좁아지면 접히고, 넓으면 줄 오른쪽 끝에 붙는다', (
      WidgetTester tester,
    ) async {
      // 넘침을 막으려고 토글을 `Flexible` 로 접히게 두었다. 그 과정에서 `Spacer`
      // 를 걷어냈으므로, 넓은 폭에서 토글이 오른쪽 끝을 지키는지도 함께 본다 —
      // 식단 탭에서 같은 자리가 가운데로 밀렸던 적이 있다(#761).
      await pumpExercise(tester, lang: 'ko', size: const Size(800, 3000));

      final Finder row = find.byKey(
        const ValueKey<String>('exercise-section-header'),
      );
      final Finder toggle = find.byKey(
        const ValueKey<String>('exercise-period-toggle'),
      );
      expect(toggle, findsOneWidget);

      expect(
        tester.getRect(toggle).right,
        moreOrLessEquals(tester.getRect(row).right, epsilon: 0.5),
      );
      // 제목은 여전히 줄 왼쪽에 있다 — 둘이 가운데로 몰리지 않는다. 제목
      // 왼쪽에는 이제 아이콘이 붙으므로 제목 묶음 전체로 잰다. (#1058)
      expect(
        tester.getRect(find.byType(AppSectionHeader).first).left,
        moreOrLessEquals(tester.getRect(row).left, epsilon: 0.5),
      );
    });
  });
}

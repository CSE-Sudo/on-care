import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/app_guide/domain/guide_step.dart';
import 'package:oncare/features/app_guide/presentation/pages/guide_tour_page.dart';
import 'package:oncare/features/dashboard/presentation/widgets/dashboard_content.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/member_bottom_nav.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 사용 가이드 화면(#1857) — **진짜 홈 화면**을 예시 자료로 채워 그 위에서 주요
/// 기능을 짚고, 끝나거나 건너뛰면 홈으로 보낸다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  /// 지금 말풍선이 말하는 제목. 안내 제목은 짚는 카드의 이름과 같아서, 화면
  /// 전체에서 글자를 찾으면 카드와 말풍선 둘 다 걸린다.
  String calloutTitle(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('appGuideCard'))).data!;

  Future<void> pumpTour(
    WidgetTester tester, {
    Map<String, Object> stored = const <String, Object>{},
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(stored);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.guideTour,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.guideTour,
          builder: (_, _) => const GuideTourPage(),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (_, _) => const Scaffold(body: Text('dashboard-route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          // 예시 화면은 진짜 홈이라, 가이드가 덮지 않은 값은 데모 저장소에서
          // 온다(AI 추천 식단 등).
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://dev.api.test',
              useMockApi: true,
            ),
          ),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('진짜 홈 화면 위에서 가이드가 시작된다', (WidgetTester tester) async {
    await pumpTour(tester);

    // 흉내 낸 화면이 아니라 홈이 쓰는 그 위젯이다 — 홈이 바뀌면 가이드도 같이
    // 바뀐다.
    expect(find.byType(DashboardContent), findsOneWidget);
    expect(find.byType(MemberBottomNav), findsOneWidget);
    expect(find.text(ko.homeAiAdviceTitle), findsWidgets);
    // 값만 예시다 — 가입 직후의 빈 홈이 아니라 기록이 쌓인 모습이라야 짚을 것이
    // 실제로 보인다(예시 칼로리 1,480kcal).
    expect(find.text('1,480'), findsWidgets);
    // 하단 내비도 같이 그려져 있어야 탭을 짚을 수 있다.
    expect(find.text(ko.navMyHealth), findsOneWidget);
    // 내 기록이 아니라 예시라는 것을 화면에서 밝힌다.
    expect(find.byKey(const Key('guideSampleBadge')), findsOneWidget);
    expect(find.text(ko.guideSampleBadge), findsOneWidget);

    // 가이드라는 표시와 첫 단계를 한 줄로 말한다.
    expect(
      find.text(ko.guideBadgeWithStep(1, kGuideSteps.length)),
      findsOneWidget,
    );
    expect(calloutTitle(tester), ko.guideHomeAdviceTitle);
  });

  testWidgets('단계를 넘기면 그 기능이 있는 탭으로 화면이 바뀐다', (WidgetTester tester) async {
    await pumpTour(tester);

    Future<void> next() async {
      await tester.tap(find.byKey(const Key('appGuideNext')));
      await tester.pumpAndSettle();
    }

    // 1·2단계는 홈 — AI 조언과 가운데 `+`.
    expect(find.byType(DashboardContent), findsOneWidget);
    await next();
    expect(calloutTitle(tester), ko.guideQuickAddTitle);
    expect(find.byType(DashboardContent), findsOneWidget);

    // 3단계는 식단 탭으로 옮겨 간다.
    await next();
    expect(calloutTitle(tester), ko.guideDietNutritionTitle);
    expect(find.byType(DietRecordPage), findsOneWidget);
    expect(find.byType(DashboardContent), findsNothing);

    // 4·5단계는 운동 탭 — 운동 현황과 헬스장.
    await next();
    expect(calloutTitle(tester), ko.guideExerciseStatusTitle);
    expect(find.byType(ExercisePage), findsOneWidget);
    await next();
    expect(calloutTitle(tester), ko.guideGymTitle);
    expect(find.byType(ExercisePage), findsOneWidget);

    // 6·7단계는 MY 탭 — 설정과 포인트.
    await next();
    expect(calloutTitle(tester), ko.guideMySettingsTitle);
    expect(find.byType(MyHealthPage), findsOneWidget);
    await next();
    expect(calloutTitle(tester), ko.guidePointsTitle);
    expect(find.byType(MyHealthPage), findsOneWidget);
    // 마지막 단계에서는 `다음` 대신 `완료` 다.
    expect(find.text(ko.guideDone), findsOneWidget);
  });

  testWidgets('짚는 자리는 그 탭 화면 안에 실제로 뚫린다', (WidgetTester tester) async {
    await pumpTour(tester);

    // 화면 아래에 접혀 있는 카드(MY 포인트)까지 굴려 와 짚는다 — 안 보이는
    // 자리를 짚으면 덮개만 깔리고 아무것도 밝아지지 않는다.
    for (int step = 1; step < kGuideSteps.length; step++) {
      await tester.tap(find.byKey(const Key('appGuideNext')));
      await tester.pumpAndSettle();
    }

    final AppSpotlight spotlight = tester.widget<AppSpotlight>(
      find.byType(AppSpotlight),
    );
    expect(spotlight.hole, isNotNull);
    expect(find.byKey(const Key('pointsBanner')), findsOneWidget);
  });

  testWidgets('끝까지 보면 홈으로 가고, 다시 열지 않는다', (WidgetTester tester) async {
    await pumpTour(tester);

    for (int step = 0; step < kGuideSteps.length; step++) {
      await tester.tap(find.byKey(const Key('appGuideNext')));
      await tester.pumpAndSettle();
    }

    expect(find.text('dashboard-route'), findsOneWidget);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('home_guide_done'), isTrue);
  });

  testWidgets('건너뛰면 곧바로 홈으로 간다', (WidgetTester tester) async {
    await pumpTour(tester);

    await tester.tap(find.byKey(const Key('appGuideSkip')));
    await tester.pumpAndSettle();

    expect(find.text('dashboard-route'), findsOneWidget);
    expect(find.byKey(const Key('appGuideCard')), findsNothing);
  });

  testWidgets('이미 본 회원은 예시 화면에 머물지 않고 홈으로 간다', (WidgetTester tester) async {
    await pumpTour(
      tester,
      stored: const <String, Object>{'home_guide_done': true},
    );

    expect(find.text('dashboard-route'), findsOneWidget);
    expect(find.byKey(const Key('appGuideCard')), findsNothing);
  });
}

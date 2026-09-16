import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/app_guide/domain/guide_step.dart';
import 'package:oncare/features/app_guide/presentation/pages/guide_tour_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 사용 가이드 화면(#1857) — **예시 자료로 채운 화면** 위에서 주요 기능을 짚고,
/// 끝나거나 건너뛰면 홈으로 보낸다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

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

  testWidgets('예시 자료로 채운 화면 위에서 가이드가 시작된다', (WidgetTester tester) async {
    await pumpTour(tester);

    // 내 기록이 아니라 예시라는 것을 화면에서 밝힌다.
    expect(find.byKey(const Key('guideSampleBadge')), findsOneWidget);
    expect(find.text(ko.guideSampleBadge), findsOneWidget);
    // 빈 홈이 아니라 기록이 쌓인 모습이다 — 짚을 것이 실제로 보인다.
    expect(find.text('1480'), findsOneWidget);
    expect(find.text(ko.homeDietNutritionTitle), findsOneWidget);
    // 하단 내비도 같이 그려져 있어야 탭을 짚을 수 있다.
    expect(find.text(ko.navMyHealth), findsOneWidget);

    // 가이드라는 표시와 첫 단계.
    expect(find.text(ko.guideBadge), findsOneWidget);
    expect(find.text(ko.guideStepCount(1, kGuideSteps.length)), findsOneWidget);
    expect(find.text(ko.guideHomeTitle), findsOneWidget);
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

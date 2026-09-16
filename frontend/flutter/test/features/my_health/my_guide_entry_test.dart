/// MY 탭의 `앱 사용 가이드 다시 보기`. (#1857)
///
/// 온보딩 때 건너뛰었거나 다시 보고 싶은 사람이 가이드로 돌아오는 자리다. 본
/// 기억을 지워야 가이드가 다시 뜨므로, 그 기억까지 함께 확인한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  Future<SharedPreferences> pumpMyTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 이미 가이드를 본 회원 — 다시 보기를 눌러야 하는 바로 그 상황이다.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'home_guide_done': true,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.myHealth,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.myHealth,
          builder: (_, _) => const MyHealthPage(),
        ),
        GoRoute(
          path: AppRoutes.guideTour,
          builder: (_, _) => const Scaffold(body: Text('guide-route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
          myHealthRepositoryProvider.overrideWithValue(
            const MockMyHealthRepository(),
          ),
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
    return prefs;
  }

  testWidgets('설정 목록에 가이드 다시 보기가 있다', (WidgetTester tester) async {
    await pumpMyTab(tester);

    expect(find.text(ko.myGuideTitle), findsOneWidget);
  });

  testWidgets('누르면 본 기억을 지우고 가이드로 간다', (WidgetTester tester) async {
    final SharedPreferences prefs = await pumpMyTab(tester);
    expect(prefs.getBool('home_guide_done'), isTrue);

    await tester.ensureVisible(find.text(ko.myGuideTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ko.myGuideTitle));
    await tester.pumpAndSettle();

    expect(find.text('guide-route'), findsOneWidget);
    // 기억이 남아 있으면 가이드 화면이 스스로 홈으로 빠져나간다.
    expect(prefs.getBool('home_guide_done'), isFalse);
  });
}

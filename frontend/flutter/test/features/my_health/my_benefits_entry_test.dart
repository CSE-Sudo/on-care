/// `내 혜택` 입구 — MY 에는 따로 줄을 두지 않고, 포인트 카드 → 포인트 사용처의
/// `내 혜택` 버튼으로만 들어간다. (#1787)
///
/// MY 순서(프로필 → 트레이너·헬스장 → 포인트 → 설정)는 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../benefits/fake_benefits_repository.dart';

void main() {
  Future<void> pumpMy(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.myHealth,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.myHealth,
          builder: (_, _) => const MyHealthPage(),
        ),
        GoRoute(
          path: AppRoutes.myPoints,
          builder: (_, GoRouterState state) => PointsBenefitsPage(
            points: state.extra is int ? state.extra! as int : null,
          ),
        ),
        GoRoute(
          path: AppRoutes.myBenefits,
          builder: (_, _) => const Placeholder(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
          myHealthRepositoryProvider.overrideWithValue(
            const MockMyHealthRepository(),
          ),
          benefitsRepositoryProvider.overrideWithValue(
            FakeBenefitsRepository(),
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
  }

  testWidgets('MY 에는 내 혜택 줄이 없고 포인트 카드 다음이 바로 설정이다', (tester) async {
    await pumpMy(tester);

    expect(find.byKey(const Key('myBenefitsEntry')), findsNothing);
    expect(find.text('내 혜택'), findsNothing);
    final double bannerBottom = tester
        .getBottomLeft(find.byKey(const Key('pointsBanner')))
        .dy;
    final double settingsTop = tester.getTopLeft(find.text('설정')).dy;
    expect(settingsTop - bannerBottom, OnCareSpacing.sectionGap);
  });

  testWidgets('포인트 카드 → 포인트 사용처의 내 혜택 버튼으로 내 혜택 화면에 간다', (tester) async {
    await pumpMy(tester);

    await tester.tap(find.byKey(const Key('pointsBanner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pointsBenefitsPage')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pointsShopMyBenefits')));
    await tester.pumpAndSettle();
    expect(find.byType(Placeholder), findsOneWidget);
  });
}

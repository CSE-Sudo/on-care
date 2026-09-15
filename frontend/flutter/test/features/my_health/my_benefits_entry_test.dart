/// MY 의 `내 혜택` 입구 — 포인트 카드 바로 아래, 설정 위. (#1787)
///
/// 새 구역 제목 없이 포인트 카드에 카드 간격으로 붙는다. 기존 순서(프로필 →
/// 트레이너·헬스장 → 포인트 → 설정)는 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

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

  Finder entry() => find.byKey(const Key('myBenefitsEntry'));

  testWidgets('내 혜택 줄은 포인트 카드 바로 아래, 설정 위에 선다', (tester) async {
    await pumpMy(tester);

    expect(entry(), findsOneWidget);
    expect(
      find.descendant(of: entry(), matching: find.text('내 혜택')),
      findsOneWidget,
    );
    final double bannerBottom = tester
        .getBottomLeft(find.byKey(const Key('pointsBanner')))
        .dy;
    final Finder entryCard = find.ancestor(
      of: entry(),
      matching: find.byType(AppCard),
    );
    final double entryTop = tester.getTopLeft(entryCard).dy;
    final double entryBottom = tester.getBottomLeft(entryCard).dy;
    final double settingsTop = tester.getTopLeft(find.text('설정')).dy;

    // 포인트 카드에 카드 간격으로 붙고, 설정과는 구역 간격으로 떨어진다.
    expect(entryTop - bannerBottom, OnCareSpacing.cardGap);
    expect(settingsTop - entryBottom, OnCareSpacing.sectionGap);
  });

  testWidgets('내 혜택 줄을 누르면 내 혜택 화면으로 간다', (tester) async {
    await pumpMy(tester);

    await tester.tap(entry());
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOneWidget);
  });
}

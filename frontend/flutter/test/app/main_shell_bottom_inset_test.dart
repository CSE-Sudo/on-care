/// 탭 화면은 하단 내비 높이만큼 아래 여백을 받는다(#3489).
///
/// 셸은 `extendBody` 로 페이지를 내비 뒤까지 잇고, 각 탭이 받은 아래 여백만큼
/// 스스로 띄운다. 업데이트 안내(#3023)용 여백 조정이 Scaffold 바깥 context 로
/// 여백을 읽어 내비 높이가 빠졌고, iPhone 에서 MY 탭 맨 아래 `로그아웃` 이 끝까지
/// 올려도 내비 뒤에 숨었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_prompter.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/member_bottom_nav.dart';
import 'package:oncare/shared/widgets/release_update_banner.dart';

import '../helpers/demo_exercise.dart';
import '../helpers/fake_dashboard_repository.dart';
import '../helpers/fake_diet_repository.dart';
import '../helpers/fake_release_probe.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// iPhone 15 의 논리 크기와 안전 영역.
const Size _phone = Size(393, 852);
const double _safeTop = 59;
const double _safeBottom = 34;

void main() {
  late FakeReleaseProbe probe;
  late GoRouter router;

  setUp(() => probe = FakeReleaseProbe(latest: kCurrentSha));
  tearDown(() => probe.close());

  Future<void> pumpShell(
    WidgetTester tester, {
    String route = AppRoutes.dashboard,
  }) async {
    final AppDatabase exerciseDb = await seededDemoDatabase(tester);
    final double dpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = _phone * dpr;
    tester.view.padding = FakeViewPadding(
      top: _safeTop * dpr,
      bottom: _safeBottom * dpr,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);

    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(route);

    final FakeDietRepository diet = FakeDietRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          dietRepositoryProvider.overrideWithValue(diet as DietRepository),
          ...demoExerciseOverrides(exerciseDb),
          dashboardRepositoryProvider.overrideWithValue(
            FakeDashboardRepository(diet) as DashboardRepository,
          ),
          ...releaseOverrides(probe),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  EdgeInsets tabPadding(WidgetTester tester) =>
      MediaQuery.paddingOf(tester.element(find.byType(WeeklyFeedbackPrompter)));

  Rect nav(WidgetTester tester) => tester.getRect(find.byType(MemberBottomNav));

  testWidgets('탭 화면의 아래 여백은 내비 높이(안전 영역 포함)다', (WidgetTester tester) async {
    await pumpShell(tester);
    final Rect bar = nav(tester);
    expect(bar.bottom, _phone.height);
    expect(tabPadding(tester).bottom, bar.height);
    expect(
      tabPadding(tester).bottom,
      greaterThan(_safeBottom),
      reason: '안전 영역만 받으면 마지막 항목이 내비 뒤에 숨는다',
    );
  });

  testWidgets('위 여백은 안내가 없으면 상태 표시줄 높이 그대로다', (WidgetTester tester) async {
    await pumpShell(tester);
    expect(tabPadding(tester).top, _safeTop);
  });

  testWidgets('업데이트 안내가 떠도 아래 여백은 내비 높이 그대로다', (WidgetTester tester) async {
    probe.latest = kNextSha;
    await pumpShell(tester);
    expect(find.byKey(ReleaseUpdateBanner.bannerKey), findsOneWidget);
    expect(tabPadding(tester).top, 0);
    expect(tabPadding(tester).bottom, nav(tester).height);
  });

  testWidgets('MY 탭을 끝까지 올리면 로그아웃이 내비 위에 온전히 보인다', (WidgetTester tester) async {
    await pumpShell(tester, route: AppRoutes.myHealth);
    final Finder logout = find.byKey(
      const ValueKey<String>('my-logout-button'),
    );
    final Finder list = find
        .descendant(
          of: find.byType(MyHealthPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(logout, 300, scrollable: list);
    // 보이기 시작한 데서 멈추지 않고 끝까지 올린다 — 튕겨 돌아온 자리를 본다.
    await tester.drag(list, const Offset(0, -3000));
    await tester.pumpAndSettle();

    final ScrollPosition position = tester
        .state<ScrollableState>(list)
        .position;
    expect(position.pixels, position.maxScrollExtent);
    expect(tester.getRect(logout).bottom, lessThanOrEqualTo(nav(tester).top));
  });
}

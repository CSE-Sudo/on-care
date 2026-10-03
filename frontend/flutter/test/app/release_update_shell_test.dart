/// 회원 웹에 새 배포가 올라오면 하단 탭 틀(MainShell) 맨 위에 안내가 선다(#3023).
///
/// 안내는 상태 표시줄 아래에 서고, 그 아래 탭 화면은 위쪽 안전 영역을 다시 두지
/// 않는다. 안내가 없으면 탭 화면은 원래대로 안전 영역을 받는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/main_shell.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_prompter.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
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

/// 상태 표시줄 높이로 쓰는 위쪽 안전 영역.
const double _topInset = 40;

void main() {
  late FakeReleaseProbe probe;
  late GoRouter router;

  setUp(() => probe = FakeReleaseProbe(latest: kNextSha));
  tearDown(() => probe.close());

  Future<void> pumpShell(
    WidgetTester tester, {
    String sha = kCurrentSha,
    Locale locale = const Locale('ko'),
  }) async {
    final AppDatabase exerciseDb = await seededDemoDatabase(tester);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.padding = const FakeViewPadding(top: _topInset);
    addTearDown(tester.view.resetPadding);

    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.dashboard);

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
          ...releaseOverrides(probe, sha: sha),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder banner() => find.byKey(ReleaseUpdateBanner.bannerKey);

  double tabTopInset(WidgetTester tester) => MediaQuery.paddingOf(
    tester.element(find.byType(WeeklyFeedbackPrompter)),
  ).top;

  testWidgets('새 배포가 있으면 셸 맨 위에 정보 배너가 뜬다', (WidgetTester tester) async {
    await pumpShell(tester);
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
    expect(find.byType(MainShell), findsOneWidget);
    expect(banner(), findsOneWidget);
    expect(
      find.descendant(of: banner(), matching: find.text(l.releaseUpdateTitle)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: banner(), matching: find.text(l.releaseUpdateReload)),
      findsOneWidget,
    );
  });

  testWidgets('배너는 상태 표시줄 아래에 서고 탭 화면은 위 여백을 다시 두지 않는다', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    expect(tester.getRect(banner()).top, greaterThanOrEqualTo(_topInset));
    expect(tabTopInset(tester), 0);
  });

  testWidgets('배너가 없으면 탭 화면이 원래대로 위 안전 영역을 받는다', (WidgetTester tester) async {
    probe.latest = kCurrentSha;
    await pumpShell(tester);
    expect(banner(), findsNothing);
    expect(tabTopInset(tester), _topInset);
  });

  testWidgets('읽기가 실패하면 배너가 없다', (WidgetTester tester) async {
    probe.error = StateError('offline');
    await pumpShell(tester);
    expect(banner(), findsNothing);
  });

  testWidgets('내장 SHA 가 없는 빌드는 확인하지 않는다', (WidgetTester tester) async {
    await pumpShell(tester, sha: '');
    expect(probe.fetchCount, 0);
    expect(banner(), findsNothing);
  });

  testWidgets('새로고침 버튼은 페이지를 다시 읽는다', (WidgetTester tester) async {
    await pumpShell(tester);
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
    await tester.tap(
      find.descendant(of: banner(), matching: find.text(l.releaseUpdateReload)),
    );
    await tester.pump();
    expect(probe.reloadCount, 1);
  });

  testWidgets('닫으면 사라지고 탭 화면이 위 안전 영역을 되찾는다', (WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(ReleaseUpdateBanner.dismissKey));
    await tester.pumpAndSettle();
    expect(banner(), findsNothing);
    expect(tabTopInset(tester), _topInset);

    probe.visible.add(null);
    await tester.pumpAndSettle();
    expect(banner(), findsNothing);

    probe
      ..latest = kLaterSha
      ..visible.add(null);
    await tester.pumpAndSettle();
    expect(banner(), findsOneWidget);
  });

  testWidgets('탭을 옮겨도 배너가 셸 위에 남는다', (WidgetTester tester) async {
    await pumpShell(tester);
    router.go(AppRoutes.myHealth);
    await tester.pumpAndSettle();
    expect(banner(), findsOneWidget);
  });

  testWidgets('영어 화면은 영어 문구다', (WidgetTester tester) async {
    await pumpShell(tester, locale: const Locale('en'));
    final AppLocalizations l = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l.releaseUpdateTitle), findsOneWidget);
    expect(find.byTooltip(l.releaseUpdateDismiss), findsOneWidget);
  });
}

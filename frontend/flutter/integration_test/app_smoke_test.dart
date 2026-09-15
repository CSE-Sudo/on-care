import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/app.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/main_shell.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/shared/services/locale_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// End-to-end smoke: the app boots into sign-in, demo entry reaches the main
/// shell, and every bottom-nav destination renders its branch page.
///
/// Run headless on the host:
///   flutter test integration_test/app_smoke_test.dart -d flutter-tester
/// or on a device/emulator:
///   flutter test integration_test/app_smoke_test.dart -d `<device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig(
    environment: Environment.dev,
    apiBaseUrl: 'https://dev.api.test',
    useMockApi: true,
  );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          // Production wiring — the session reset registry is what clears
          // account-specific state on sign-in/out, so the smoke test must
          // exercise the same override the app installs.
          sessionFeatureResetOverride(),
          // Pin the locale so a different host locale cannot change which
          // strings render. Assertions below go through widget types rather
          // than text, so this only keeps the run deterministic.
          localeProvider.overrideWith((ref) => const Locale('en')),
        ],
        child: const OncareApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps a bottom-nav destination by its icon so the tap does not depend on
  /// the localised label. The finder stays inside the nav bar — the same glyph
  /// (e.g. the person icon) also appears on pages.
  Future<void> tapDestination(WidgetTester tester, IconData icon) async {
    await tester.tap(
      find.ancestor(
        of: find.descendant(
          of: find.byType(AppBottomNav),
          matching: find.byIcon(icon),
        ),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('demo entry reaches the main shell and every tab renders', (
    tester,
  ) async {
    await pumpApp(tester);

    // The app starts at sign-in — not at a tab.
    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    // Enter demo mode. The button sits below the fold on the test surface,
    // and the Key keeps the finder locale-independent.
    final Finder demoButton = find.byKey(const Key('demoEnterButton'));
    await tester.ensureVisible(demoButton);
    await tester.pumpAndSettle();
    await tester.tap(demoButton);
    await tester.pumpAndSettle();

    // Home is the first branch of the shell's StatefulShellRoute.
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(DashboardPage), findsOneWidget);

    // Each destination swaps the branch page. The nav has a fifth slot (the
    // floating "+"), which is not a destination and is skipped here.
    await tapDestination(tester, AppIcons.diet);
    expect(find.byType(DietRecordPage), findsOneWidget);

    await tapDestination(tester, AppIcons.exercise);
    expect(find.byType(ExercisePage), findsOneWidget);

    await tapDestination(tester, AppIcons.my);
    expect(find.byType(MyHealthPage), findsOneWidget);

    // Back to Home — the shell keeps its branches alive, so returning must
    // still render the dashboard.
    await tapDestination(tester, AppIcons.home);
    expect(find.byType(DashboardPage), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

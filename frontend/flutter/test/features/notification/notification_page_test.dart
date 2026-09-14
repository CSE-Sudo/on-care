import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

Future<void> _pumpNotificationPage(
  WidgetTester tester,
  Brightness platformBrightness,
) async {
  tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
  addTearDown(
    tester.platformDispatcher.clearPlatformBrightnessTestValue,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[appConfigProvider.overrideWithValue(_mockConfig)],
      child: MaterialApp(
        theme: AppTheme.light(),
        // 이 파일은 한국어 문구로 화면을 찾는다. 로케일을 고정하지 않으면
        // 테스트 환경의 기본값(en)으로 떠서 찾지 못한다(#847).
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'notification page stays light in ${brightness.name} system mode',
      (WidgetTester tester) async {
        await _pumpNotificationPage(tester, brightness);

        final BuildContext pageContext = tester.element(
          find.byKey(const Key('notificationPage')),
        );
        final ThemeData theme = Theme.of(pageContext);

        expect(theme.brightness, Brightness.light);
        expect(theme.scaffoldBackgroundColor, OnCareColors.surfaceCard);
        expect(theme.colorScheme.onSurface, OnCareColors.textPrimary);
        expect(
          theme.colorScheme.surfaceContainerHigh,
          OnCareBrand.member.surface,
        );
        expect(find.text('나트륨 섭취 주의'), findsOneWidget);
        expect(find.text('서비스 점검 안내'), findsOneWidget);
        // 개발용 가상 푸시 버튼은 목/데모 빌드에도 두지 않는다(#1242).
        expect(find.text('Simulate push'), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );
  }

  testWidgets('notification actions still work inside the light theme', (
    WidgetTester tester,
  ) async {
    await _pumpNotificationPage(tester, Brightness.dark);
    final BuildContext pageContext = tester.element(
      find.byKey(const Key('notificationPage')),
    );
    final ProviderContainer container = ProviderScope.containerOf(pageContext);

    await tester.tap(find.text('모두 읽음'));
    await tester.pump();
    expect(container.read(notificationControllerProvider).unreadCount, 0);
  });
}

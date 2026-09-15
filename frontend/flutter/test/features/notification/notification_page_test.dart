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
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
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

  group('목록형 알림 줄 (#1810)', () {
    Finder rowOf(String id) =>
        find.byKey(ValueKey<String>('notification-row-$id'));

    /// 줄 바탕을 칠하는 [Material] 의 색.
    Color rowColor(WidgetTester tester, String id) => tester
        .widget<Material>(
          find.descendant(of: rowOf(id), matching: find.byType(Material)).first,
        )
        .color!;

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byKey(const Key('notificationPage'))),
        );

    testWidgets('카드 상자 없이 줄이 목록 폭을 끝까지 채운다', (WidgetTester tester) async {
      await _pumpNotificationPage(tester, Brightness.light);
      final String firstId = containerOf(
        tester,
      ).read(notificationControllerProvider).items.first.id;

      expect(find.byType(AppCard), findsNothing);
      expect(
        tester.getSize(rowOf(firstId)).width,
        tester.getSize(find.byType(ListView)).width,
      );
    });

    testWidgets('안 읽은 알림은 연한 파랑, 읽은 알림은 흰 바탕이다', (WidgetTester tester) async {
      await _pumpNotificationPage(tester, Brightness.light);
      final items = containerOf(
        tester,
      ).read(notificationControllerProvider).items;
      final unread = items.firstWhere((item) => !item.read);

      expect(rowColor(tester, unread.id), OnCareBrand.member.surface);
      for (final item in items.where((item) => item.read)) {
        expect(rowColor(tester, item.id), OnCareColors.surfaceCard);
      }
    });

    testWidgets('안 읽은 알림을 누르면 그 줄만 흰 바탕이 된다', (WidgetTester tester) async {
      await _pumpNotificationPage(tester, Brightness.light);
      final ProviderContainer container = containerOf(tester);
      final items = container.read(notificationControllerProvider).items;
      final unread = items.where((item) => !item.read).toList();
      expect(unread, isNotEmpty);

      // 이동하지 않도록 읽음 처리만 확인한다 — 이동 자체는 알림 이동 테스트가 본다.
      container
          .read(notificationControllerProvider.notifier)
          .markRead(unread.first.id);
      await tester.pump();

      expect(rowColor(tester, unread.first.id), OnCareColors.surfaceCard);
      for (final other in unread.skip(1)) {
        expect(rowColor(tester, other.id), OnCareBrand.member.surface);
      }
    });

    testWidgets('모두 읽음을 누르면 모든 줄이 흰 바탕이 된다', (WidgetTester tester) async {
      await _pumpNotificationPage(tester, Brightness.light);
      final ProviderContainer container = containerOf(tester);

      await tester.tap(find.text('모두 읽음'));
      await tester.pump();

      for (final item in container.read(notificationControllerProvider).items) {
        expect(rowColor(tester, item.id), OnCareColors.surfaceCard);
      }
    });

    testWidgets('줄마다 제목·본문·시각을 보이고 갈래는 화면 읽기 이름으로 남긴다', (
      WidgetTester tester,
    ) async {
      await _pumpNotificationPage(tester, Brightness.light);
      final item = containerOf(
        tester,
      ).read(notificationControllerProvider).items.first;

      expect(
        find.descendant(of: rowOf(item.id), matching: find.text(item.title)),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('notification-time-${item.id}')),
        findsOneWidget,
      );
      // 글자 태그는 없고 원 안의 아이콘이 갈래를 말한다.
      expect(
        find.descendant(of: rowOf(item.id), matching: find.byType(AppTag)),
        findsNothing,
      );
      expect(
        find.descendant(of: rowOf(item.id), matching: find.byType(Icon)),
        findsOneWidget,
      );
    });
  });
}

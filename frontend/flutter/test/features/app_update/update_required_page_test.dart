/// 업데이트 필요 화면(#3045).
///
/// 회원 앱 원래 모양대로 흰 바탕 가운데 안내와 버튼 하나. 뒤로 갈 수 없고, 버튼은
/// 스토어의 On-Care 페이지를 연다. 열 주소가 없으면 버튼 대신 안내 문구를 둔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/app_version/app_version_gate.dart';
import 'package:oncare/core/app_version/store_link.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/app_update/presentation/pages/update_required_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 정해 둔 상태로 시작하는 확인기. 서버에 묻지 않는다.
class _FixedGate extends AppVersionGate {
  _FixedGate(AppVersionGateState initial)
    : super(
        enabled: false,
        readCurrentVersion: () async => null,
        fetchVersionInfo: () async => null,
      ) {
    state = initial;
  }
}

const AppVersionGateState _blocked = AppVersionGateState(
  status: AppVersionStatus.updateRequired,
  currentVersion: '0.4.0',
  minVersion: '0.5.0',
);

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

Future<void> _pump(
  WidgetTester tester, {
  required TargetPlatform platform,
  Locale locale = const Locale('ko'),
  String? iosAppStoreId,
  AppVersionGateState gate = _blocked,
  List<Uri>? opened,
  bool Function(Uri)? launchResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appVersionGateProvider.overrideWith((ref) => _FixedGate(gate)),
        storeTargetPlatformProvider.overrideWithValue(platform),
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://example.test/v1',
            useMockApi: true,
            iosAppStoreId: iosAppStoreId,
          ),
        ),
        storeLauncherProvider.overrideWithValue((Uri uri) async {
          opened?.add(uri);
          return launchResult?.call(uri) ?? true;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const UpdateRequiredPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('안내·두 버전·업데이트 버튼을 보인다', (WidgetTester tester) async {
    await _pump(tester, platform: TargetPlatform.android);

    expect(find.byKey(UpdateRequiredPage.bodyKey), findsOneWidget);
    expect(find.text(_ko.updateRequiredTitle), findsOneWidget);
    expect(
      find.textContaining(_ko.updateRequiredVersions('0.4.0', '0.5.0')),
      findsOneWidget,
    );
    expect(find.byKey(UpdateRequiredPage.actionKey), findsOneWidget);
    expect(find.text(_ko.updateRequiredAction), findsOneWidget);
    expect(find.textContaining(_ko.updateRequiredStoreHint), findsNothing);
  });

  testWidgets('공용 부품과 흰 바탕을 쓴다', (WidgetTester tester) async {
    await _pump(tester, platform: TargetPlatform.android);

    expect(find.byType(AppEmptyState), findsOneWidget);
    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, OnCareColors.surfaceCard);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('뒤로 갈 수 없다', (WidgetTester tester) async {
    await _pump(tester, platform: TargetPlatform.android);

    final PopScope<dynamic> scope = tester.widget<PopScope<dynamic>>(
      find.byWidgetPredicate((Widget w) => w is PopScope),
    );
    expect(scope.canPop, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(UpdateRequiredPage.bodyKey), findsOneWidget);
  });

  testWidgets('영어로도 보인다', (WidgetTester tester) async {
    await _pump(
      tester,
      platform: TargetPlatform.android,
      locale: const Locale('en'),
    );

    expect(find.text(_en.updateRequiredTitle), findsOneWidget);
    expect(
      find.textContaining(_en.updateRequiredVersions('0.4.0', '0.5.0')),
      findsOneWidget,
    );
    expect(find.text(_en.updateRequiredAction), findsOneWidget);
  });

  group('안드로이드', () {
    testWidgets('Play 스토어 앱을 먼저 연다', (WidgetTester tester) async {
      final List<Uri> opened = <Uri>[];
      await _pump(tester, platform: TargetPlatform.android, opened: opened);

      await tester.tap(find.byKey(UpdateRequiredPage.actionKey));
      await tester.pumpAndSettle();

      expect(opened, <Uri>[
        Uri.parse('market://details?id=$kAndroidPackageName'),
      ]);
    });

    testWidgets('스토어 앱이 없으면 웹 페이지로 넘어간다', (WidgetTester tester) async {
      final List<Uri> opened = <Uri>[];
      await _pump(
        tester,
        platform: TargetPlatform.android,
        opened: opened,
        launchResult: (Uri uri) => uri.scheme != 'market',
      );

      await tester.tap(find.byKey(UpdateRequiredPage.actionKey));
      await tester.pumpAndSettle();

      expect(opened, hasLength(2));
      expect(opened.last.host, 'play.google.com');
      expect(find.text(_ko.updateRequiredOpenFailed), findsNothing);
    });

    testWidgets('모두 못 열면 알린다', (WidgetTester tester) async {
      await _pump(
        tester,
        platform: TargetPlatform.android,
        launchResult: (_) => false,
      );

      await tester.tap(find.byKey(UpdateRequiredPage.actionKey));
      await tester.pump();
      await tester.pump();

      expect(find.text(_ko.updateRequiredOpenFailed), findsOneWidget);
      await tester.pump(OnCareMotion.toastErrorVisible);
      await tester.pumpAndSettle();
    });
  });

  group('iOS', () {
    testWidgets('앱 ID 가 있으면 App Store 페이지를 연다', (WidgetTester tester) async {
      final List<Uri> opened = <Uri>[];
      await _pump(
        tester,
        platform: TargetPlatform.iOS,
        iosAppStoreId: '1234567890',
        opened: opened,
      );

      await tester.tap(find.byKey(UpdateRequiredPage.actionKey));
      await tester.pumpAndSettle();

      expect(opened, <Uri>[
        Uri.parse('https://apps.apple.com/app/id1234567890'),
      ]);
    });

    testWidgets('앱 ID 가 없으면 버튼 대신 안내 문구를 둔다', (WidgetTester tester) async {
      await _pump(tester, platform: TargetPlatform.iOS);

      expect(find.byKey(UpdateRequiredPage.actionKey), findsNothing);
      expect(find.textContaining(_ko.updateRequiredStoreHint), findsOneWidget);
    });
  });

  testWidgets('버전을 모르면 버전 줄을 빼고 안내만 둔다', (WidgetTester tester) async {
    await _pump(
      tester,
      platform: TargetPlatform.android,
      gate: const AppVersionGateState(status: AppVersionStatus.updateRequired),
    );

    expect(find.text(_ko.updateRequiredTitle), findsOneWidget);
    expect(find.textContaining('0.5.0'), findsNothing);
  });
}

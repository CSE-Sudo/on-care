/// MY → 고객 지원의 오픈소스 라이선스. (#3150)
///
/// 처리방침 아래 줄에서 라이선스 목록을 연다. 머리에는 앱 이름과 빌드 정보에서
/// 읽은 버전이 실리고, 앱에 담긴 Pretendard 글꼴의 OFL 이 목록에 들어간다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/app_version/app_version.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_core/licenses.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

Future<void> _pumpSupport(
  WidgetTester tester, {
  String? version = '0.4.0',
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.mySettingsPath('support'),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.mySettings,
        builder: (_, _) => const SupportPage(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appVersionProvider.overrideWith((ref) async => version),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<LicensePage> _openLicenses(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  expect(find.byType(LicensePage), findsOneWidget);
  return tester.widget<LicensePage>(find.byType(LicensePage));
}

void main() {
  testWidgets('고객 지원에 오픈소스 라이선스 줄이 처리방침 아래에 있다', (WidgetTester tester) async {
    await _pumpSupport(tester);

    expect(find.text(_ko.myOpenSourceLicensesTitle), findsOneWidget);
    final double privacy = tester
        .getTopLeft(find.text(_ko.myLegalPrivacyTitle))
        .dy;
    final double licenses = tester
        .getTopLeft(find.text(_ko.myOpenSourceLicensesTitle))
        .dy;
    final double withdraw = tester
        .getTopLeft(find.text(_ko.myWithdrawTitle))
        .dy;
    expect(privacy, lessThan(licenses));
    expect(licenses, lessThan(withdraw));
  });

  testWidgets('누르면 앱 이름·버전·로고를 실은 라이선스 목록이 열린다', (WidgetTester tester) async {
    await _pumpSupport(tester);

    final LicensePage page = await _openLicenses(
      tester,
      _ko.myOpenSourceLicensesTitle,
    );
    expect(page.applicationName, _ko.myAppName);
    expect(page.applicationVersion, '0.4.0');
    expect(page.applicationIcon, isA<OnCareLicenseLogo>());
  });

  testWidgets('버전을 읽지 못하면 앱 이름만 싣는다', (WidgetTester tester) async {
    await _pumpSupport(tester, version: null);

    final LicensePage page = await _openLicenses(
      tester,
      _ko.myOpenSourceLicensesTitle,
    );
    expect(page.applicationName, _ko.myAppName);
    expect(page.applicationVersion, isNull);
  });

  testWidgets('영어로도 열린다', (WidgetTester tester) async {
    await _pumpSupport(tester, locale: const Locale('en'));

    expect(find.text(_en.myOpenSourceLicensesTitle), findsOneWidget);
    await _openLicenses(tester, _en.myOpenSourceLicensesTitle);
  });

  test('줄 이름이 두 언어로 있다', () {
    expect(_ko.myOpenSourceLicensesTitle, '오픈소스 라이선스');
    expect(_en.myOpenSourceLicensesTitle, 'Open-source licenses');
  });

  test('OFL 전문이 앱에 담기도록 자산으로 등록돼 있다', () {
    expect(File(kPretendardLicenseAsset).existsSync(), isTrue);
    expect(
      File(kPretendardLicenseAsset).readAsStringSync(),
      contains('SIL OPEN FONT LICENSE'),
    );
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- $kPretendardLicenseAsset'),
    );
  });

  test('기동할 때 글꼴 라이선스를 등록한다', () {
    final String boot = File('lib/app/bootstrap.dart').readAsStringSync();
    expect(boot, contains('registerBundledLicenses();'));
    expect(
      boot.indexOf('ensureInitialized()'),
      lessThan(boot.indexOf('registerBundledLicenses();')),
    );
  });
}

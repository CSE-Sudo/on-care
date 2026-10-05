/// 트레이너 고객 지원의 오픈소스 라이선스. (#3150)
///
/// 회원 앱과 같은 자리 — 처리방침 아래 — 에서 라이선스 목록을 연다. 머리에는
/// 트레이너 앱 이름과 빌드 정보에서 읽은 버전이 실린다.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/licenses.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/pump_app.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

const Key _row = ValueKey<String>('support-licenses');

void main() {
  testWidgets('고객 지원에 오픈소스 라이선스 줄이 처리방침 아래에 있다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.mySection('support'),
    );

    expect(find.byKey(_row), findsOneWidget);
    expect(find.text(_ko.myOpenSourceLicensesTitle), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(_row)).dy,
      greaterThan(tester.getTopLeft(find.text(_ko.myLegalPrivacyTitle)).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(_row)).dy,
      lessThan(tester.getTopLeft(find.text(_ko.myDeleteAccount)).dy),
    );
  });

  testWidgets('누르면 앱 이름·버전을 실은 라이선스 목록이 열린다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.mySection('support'),
    );

    await tester.ensureVisible(find.byKey(_row));
    await tester.tap(find.byKey(_row));
    await settle(tester);

    expect(find.byType(LicensePage), findsOneWidget);
    final LicensePage page = tester.widget<LicensePage>(
      find.byType(LicensePage),
    );
    expect(page.applicationName, _ko.myAppName);
    expect(page.applicationVersion, kTestBuildVersion);
    expect(page.applicationIcon, isA<OnCareLicenseLogo>());
  });

  test('줄 이름이 두 언어로 있다', () {
    expect(_ko.myOpenSourceLicensesTitle, '오픈소스 라이선스');
    expect(_en.myOpenSourceLicensesTitle, 'Open-source licenses');
  });

  test('OFL 전문이 앱에 담기도록 자산으로 등록돼 있다', () {
    expect(File(kPretendardLicenseAsset).existsSync(), isTrue);
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

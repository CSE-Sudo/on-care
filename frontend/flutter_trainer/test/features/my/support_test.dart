/// 트레이너 고객 지원. (#2227)
///
/// 회원 앱 설정과 같은 자리 — FAQ·1:1 문의는 운영 중인 카카오톡 채널로 보내고,
/// 약관·개인정보·탈퇴와 앱 버전을 그 아래 한 화면에 모은다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/pump_app.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

void main() {
  testWidgets('설정에 고객 지원 입구가 있고 누르면 그 화면으로 간다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.mySection('settings'),
    );

    final entry = find.byKey(const ValueKey<String>('my-support-entry'));
    expect(entry, findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await settle(tester);

    expect(currentLocation(tester), AppRoutes.mySection('support'));
    expect(find.text(_ko.mySupportFaq), findsOneWidget);
    expect(find.text(_ko.mySupportInquiry), findsOneWidget);
  });

  testWidgets('고객 지원 한 화면에 문의·약관·탈퇴·앱 버전이 함께 있다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.mySection('support'),
    );

    expect(find.text(_ko.mySupportFaq), findsOneWidget);
    expect(find.text(_ko.mySupportInquiry), findsOneWidget);
    expect(find.text(_ko.myLegalTermsTitle), findsOneWidget);
    expect(find.text(_ko.myLegalPrivacyTitle), findsOneWidget);
    expect(find.text(_ko.myDeleteAccount), findsOneWidget);
    expect(find.text(_ko.myAppVersion), findsOneWidget);
    // 앱 밖으로 나가는 줄은 그렇다고 미리 말해 준다.
    expect(find.text(_ko.mySupportExternalHint), findsNWidgets(2));
  });

  testWidgets('뒤로 누르면 설정으로 돌아온다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.mySection('support'),
    );

    await tester.tap(find.byTooltip('뒤로'));
    await settle(tester);

    expect(currentLocation(tester), AppRoutes.mySection('settings'));
  });
}

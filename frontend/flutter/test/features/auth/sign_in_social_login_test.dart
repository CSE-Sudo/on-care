/// 로그인 화면의 소셜 로그인 버튼 노출 — #1553.
///
/// 버튼은 고정 데모 토큰을 보내므로 목업이 받아 주는 설정에서만 보여야 한다.
/// 실서버로 나가는 설정에서는 버튼과 "또는" 구분선이 함께 사라지고, 이메일
/// 로그인·회원가입은 그대로 남는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

Future<void> _pumpSignIn(WidgetTester tester, AppConfig config) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[appConfigProvider.overrideWithValue(config)],
      child: const MaterialApp(
        locale: Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SignInPage(),
      ),
    ),
  );
  await tester.pump();
}

void _expectSocialButtons(Matcher matcher) {
  expect(find.text('카카오로 시작하기'), matcher);
  expect(find.text('구글로 시작하기'), matcher);
  expect(find.text('또는'), matcher);
}

void main() {
  testWidgets('목업 데모 설정에서는 소셜 로그인 버튼이 보인다', (WidgetTester tester) async {
    await _pumpSignIn(
      tester,
      const AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: true,
      ),
    );

    _expectSocialButtons(findsOneWidget);
  });

  for (final (String name, AppConfig config) in <(String, AppConfig)>[
    (
      'USE_MOCK_API=false',
      const AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: false,
      ),
    ),
    (
      'REAL_API=auth',
      const AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: true,
        realApiFeatures: <String>{'auth'},
      ),
    ),
    (
      'ENV=prod',
      const AppConfig(
        environment: Environment.prod,
        apiBaseUrl: 'https://api.test',
        useMockApi: false,
      ),
    ),
  ]) {
    testWidgets('$name 에서는 고정 토큰을 보내는 소셜 버튼을 감춘다', (
      WidgetTester tester,
    ) async {
      await _pumpSignIn(tester, config);

      _expectSocialButtons(findsNothing);
      // 감춘 것은 소셜 버튼뿐이다 — 이메일 로그인과 회원가입은 그대로다.
      expect(
        find.byKey(const ValueKey<String>('member-login-submit')),
        findsOneWidget,
      );
      expect(find.text('회원가입'), findsWidgets);
    });
  }
}

/// 로그인 화면의 "로그인 없이 데모 둘러보기" 진입 노출 — #1526.
///
/// 진입은 화면에서 내렸다. 다만 되돌릴 여지를 남겨야 해서 코드를 지우거나 주석
/// 처리하지 않고 [AppConfig.showDemoEntry] 로 감췄다. 그래서 이 테스트는 두
/// 가지를 함께 지킨다 — 기본 빌드에서는 보이지 않고, 플래그를 켜면 그대로
/// 돌아온다(감춘 뒤 코드가 조용히 썩는 것을 막는다).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _hidden = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const AppConfig _shown = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
  showDemoEntry: true,
);

Future<void> _pumpSignIn(WidgetTester tester, {required bool showDemo}) async {
  final AppConfig config = showDemo ? _shown : _hidden;
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[appConfigProvider.overrideWithValue(config)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SignInPage(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('기본 빌드에는 데모 진입이 없다', (WidgetTester tester) async {
    await _pumpSignIn(tester, showDemo: false);

    expect(find.byKey(const Key('demoEnterButton')), findsNothing);
    expect(find.text('로그인 없이 데모 둘러보기'), findsNothing);
    // 감춘 것은 이 버튼뿐이다 — 로그인 화면 자체는 그대로다.
    expect(find.text('회원가입'), findsWidgets);
  });

  testWidgets('SHOW_DEMO_ENTRY 를 켜면 데모 진입이 돌아온다', (
    WidgetTester tester,
  ) async {
    await _pumpSignIn(tester, showDemo: true);

    expect(find.byKey(const Key('demoEnterButton')), findsOneWidget);
    expect(find.text('로그인 없이 데모 둘러보기'), findsOneWidget);
  });
}

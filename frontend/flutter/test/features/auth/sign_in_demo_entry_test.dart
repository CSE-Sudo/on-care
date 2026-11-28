/// 로그인 화면의 "체험하기" 진입 노출 — #1526, #3423, #3432.
///
/// 진입은 화면에서 내렸다. 다만 되돌릴 여지를 남겨야 해서 코드를 지우거나 주석
/// 처리하지 않고 [AppConfig.showDemoEntry] 로 감췄다. 그래서 이 테스트는 두
/// 가지를 함께 지킨다 — 기본 빌드에서는 보이지 않고, 플래그를 켜면 그대로
/// 돌아온다(감춘 뒤 코드가 조용히 썩는 것을 막는다).
///
/// 운영 웹 빌드는 `DEMO_SITE_URL` 을 받아 같은 버튼이 앱 안 데모 대신 데모 사이트로
/// 옮긴다(#3437) — 운영 서버에는 데모 폴백이 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/auth/presentation/demo_site_entry.dart';
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

/// 운영 웹 빌드처럼 데모 진입(`SHOW_DEMO_ENTRY`)은 닫혀 있고 데모 사이트 주소만 있다
/// (#3437). 화면 밖 실서버 배선을 피하려고 나머지는 목업 설정 그대로 둔다.
const AppConfig _production = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
  demoSiteUrl: 'https://cse-sudo.github.io/on-care/member/',
);

Future<void> _pumpSignIn(
  WidgetTester tester, {
  bool showDemo = false,
  AppConfig? config,
  List<Override> overrides = const <Override>[],
}) async {
  final AppConfig resolved = config ?? (showDemo ? _shown : _hidden);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(resolved),
        ...overrides,
      ],
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
    await _pumpSignIn(tester);

    expect(find.byKey(const Key('demoEnterButton')), findsNothing);
    expect(find.text('체험하기'), findsNothing);
    expect(find.byKey(const Key('demoEntryNote')), findsNothing);
    // 감춘 것은 이 버튼뿐이다 — 로그인 화면 자체는 그대로다.
    expect(find.text('회원가입'), findsWidgets);
  });

  testWidgets('SHOW_DEMO_ENTRY 를 켜면 데모 진입이 돌아온다', (WidgetTester tester) async {
    await _pumpSignIn(tester, showDemo: true);

    expect(find.byKey(const Key('demoEnterButton')), findsOneWidget);
    expect(find.text('체험하기'), findsOneWidget);
    // 두 앱의 기록이 이어지지 않는다는 안내가 함께 뜬다(#3423).
    expect(find.byKey(const Key('demoEntryNote')), findsOneWidget);
  });

  // 로그인이 이 화면의 주 동작이라 체험하기는 로그인 버튼보다 아래, 맨 아래에
  // 둔다(#3432).
  testWidgets('데모 진입은 로그인 버튼보다 아래에 있다', (WidgetTester tester) async {
    await _pumpSignIn(tester, showDemo: true);

    final double entry = tester
        .getTopLeft(find.byKey(const Key('demoEnterButton')))
        .dy;
    final double submit = tester
        .getTopLeft(find.byKey(const ValueKey<String>('member-login-submit')))
        .dy;
    expect(entry, greaterThan(submit));
  });

  testWidgets('데모 사이트 주소가 있으면 데모 진입이 닫혀 있어도 체험하기를 띄운다', (
    WidgetTester tester,
  ) async {
    await _pumpSignIn(tester, config: _production);

    expect(find.byKey(const Key('demoEnterButton')), findsOneWidget);
    expect(find.text('체험하기'), findsOneWidget);
    expect(find.byKey(const Key('demoEntryNote')), findsOneWidget);
  });

  testWidgets('데모 사이트 주소가 있으면 체험하기는 그 사이트를 진입 표시와 함께 연다', (
    WidgetTester tester,
  ) async {
    final List<Uri> opened = <Uri>[];
    await _pumpSignIn(
      tester,
      config: _production,
      overrides: <Override>[
        demoSiteLauncherProvider.overrideWithValue((Uri target) async {
          opened.add(target);
          return true;
        }),
      ],
    );

    final Finder demoButton = find.byKey(const Key('demoEnterButton'));
    await tester.ensureVisible(demoButton);
    await tester.pump();
    // 앱 안 데모로 들어가면 대시보드로 `go` 한다 — 이 화면에는 라우터가 없어
    // 그 길로 가면 실패한다. 데모 사이트로만 옮겨야 한다.
    await tester.tap(demoButton);
    await tester.pump();

    expect(opened, <Uri>[
      Uri.parse('https://cse-sudo.github.io/on-care/member/?demo=1'),
    ]);
  });

  testWidgets('https 가 아닌 데모 사이트 주소는 버리고 버튼도 띄우지 않는다', (
    WidgetTester tester,
  ) async {
    const AppConfig insecure = AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'https://dev.api.test',
      useMockApi: true,
      demoSiteUrl: 'http://cse-sudo.github.io/on-care/member/',
    );
    await _pumpSignIn(tester, config: insecure);

    expect(find.byKey(const Key('demoEnterButton')), findsNothing);
  });

  testWidgets('안내는 상대 앱과의 연동이 로그인 후라고 알린다', (WidgetTester tester) async {
    await _pumpSignIn(tester, showDemo: true);

    expect(find.text('예시 데이터 사용 · 트레이너 연동은 로그인 후'), findsOneWidget);
  });
}

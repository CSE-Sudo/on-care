/// 로그인 화면의 `아이디 찾기` 와 아이디 찾기 화면.
///
/// 찾는 경로가 생기기 전이라 화면은 입력만 검사하고 준비 중이라고 안내한다
/// (리포지토리·네트워크를 쓰지 않는다). 입구·뒤로 가기·입력 검사·안내를 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/presentation/pages/find_email_page.dart';
import 'package:oncare/features/auth/presentation/pages/password_reset_page.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  String initialLocation = AppRoutes.signIn,
  Locale locale = const Locale('ko'),
  double width = 390,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(
        path: AppRoutes.findEmail,
        builder: (_, _) => const FindEmailPage(),
      ),
      GoRoute(
        path: AppRoutes.passwordReset,
        builder: (_, _) => const PasswordResetPage(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://api.test',
            useMockApi: true,
          ),
        ),
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
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
  return AppLocalizations.of(tester.element(find.byType(Navigator).first));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String? _errorOf(WidgetTester tester, String key) =>
    tester.widget<AppTextField>(_key(key)).errorText;

void main() {
  testWidgets('로그인 화면의 아이디 찾기가 비밀번호 찾기 옆에서 화면을 연다', (tester) async {
    final AppLocalizations l = await _pump(tester);

    expect(find.text(l.authFindEmail), findsOneWidget);
    final Rect findEmail = tester.getRect(_key('member-login-find-email'));
    final Rect forgot = tester.getRect(_key('member-login-forgot-password'));
    expect(findEmail.center.dy, forgot.center.dy);
    expect(findEmail.right, lessThanOrEqualTo(forgot.left));

    await _tap(tester, _key('member-login-find-email'));
    expect(find.byType(FindEmailPage), findsOneWidget);
    expect(find.text(l.findEmailTitle), findsWidgets);
    expect(find.text(l.findEmailSubtitle), findsOneWidget);
    // 준비 중 문구는 화면에 늘 띄워 두지 않는다 — 눌렀을 때 토스트로만 알린다.
    expect(find.text(l.findEmailComingSoon), findsNothing);
  });

  testWidgets('뒤로 가면 로그인 화면으로 돌아간다', (tester) async {
    await _pump(tester);
    await _tap(tester, _key('member-login-find-email'));
    await _tap(tester, find.byType(AppBackButton));
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('주소로 바로 열어도 뒤로 가기는 로그인 화면이다', (tester) async {
    await _pump(tester, initialLocation: AppRoutes.findEmail);
    await _tap(tester, find.byType(AppBackButton));
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('비어 있거나 형식이 틀리면 칸 아래에 오류를 띄운다', (tester) async {
    await _pump(tester, initialLocation: AppRoutes.findEmail);

    await _tap(tester, _key('findEmail-submit'));
    expect(_errorOf(tester, 'findEmail-name'), isNotNull);
    expect(_errorOf(tester, 'findEmail-phone'), isNotNull);

    await tester.enterText(_key('findEmail-name'), '김온케어');
    await tester.enterText(_key('findEmail-phone'), '0101234');
    await _tap(tester, _key('findEmail-submit'));
    expect(_errorOf(tester, 'findEmail-name'), isNull);
    expect(_errorOf(tester, 'findEmail-phone'), isNotNull);
  });

  testWidgets('맞게 넣으면 준비 중이라고 알리고 화면에 머문다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
    );

    await tester.enterText(_key('findEmail-name'), '김온케어');
    // 숫자만 쳐도 가입 화면처럼 하이픈이 들어간다.
    await tester.enterText(_key('findEmail-phone'), '01012345678');
    await tester.pump();
    expect(find.text('010-1234-5678'), findsOneWidget);

    await _tap(tester, _key('findEmail-submit'));
    expect(_errorOf(tester, 'findEmail-name'), isNull);
    expect(_errorOf(tester, 'findEmail-phone'), isNull);
    // 토스트로만 알린다.
    expect(find.text(l.findEmailComingSoon), findsOneWidget);
    expect(find.byType(FindEmailPage), findsOneWidget);
  });

  testWidgets('비밀번호도 잊었으면 재설정 화면으로 넘어간다', (tester) async {
    await _pump(tester);
    await _tap(tester, _key('member-login-find-email'));
    await _tap(tester, _key('findEmail-to-password-reset'));
    expect(find.byType(PasswordResetPage), findsOneWidget);
    // 재설정에서 뒤로 가면 아이디 찾기를 거치지 않고 로그인 화면이다.
    await _tap(tester, find.byType(AppBackButton));
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('영어·좁은 폭에서도 두 입구가 넘치지 않는다', (tester) async {
    await _pump(tester, locale: const Locale('en'), width: 320);

    expect(tester.takeException(), isNull);
    expect(_key('member-login-find-email'), findsOneWidget);
    expect(_key('member-login-forgot-password'), findsOneWidget);
  });
}

/// 로그인 화면의 `비밀번호를 잊으셨나요?` 와 비밀번호 재설정 화면(#2824).
///
/// 요청 → 코드 입력 → 완료 흐름, 메일 링크의 코드로 바로 시작하기, 서버 실패
/// 이유가 어느 칸에 붙는지, 데모가 코드를 채워 주는지를 본다.
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
import 'package:oncare/features/auth/data/repositories/mock_password_repository.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart';
import 'package:oncare/features/auth/presentation/controllers/password_providers.dart';
import 'package:oncare/features/auth/presentation/pages/password_reset_page.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

const String _code = 'ABCD-EFGH-JKMN-PQRS';
const String _newPw = 'new-pass-2';

/// 받은 요청을 적고, 정해 둔 대로 답하는 리포지토리.
class _FakeReset implements PasswordRepository {
  _FakeReset({this.requestError, this.confirmError});

  final PasswordResetError? requestError;
  PasswordResetError? confirmError;
  final List<String> requested = <String>[];
  final List<(String, String)> confirmed = <(String, String)>[];

  @override
  bool get supportsPasswordChange => true;

  @override
  Future<ReissuedTokens?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<PasswordResetRequested> requestReset({required String email}) async {
    requested.add(email);
    final PasswordResetError? e = requestError;
    if (e != null) throw e;
    return const PasswordResetRequested(expiresInMinutes: 30);
  }

  @override
  Future<void> confirmReset({
    required String code,
    required String newPassword,
  }) async {
    confirmed.add((code, newPassword));
    final PasswordResetError? e = confirmError;
    if (e != null) throw e;
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  required PasswordRepository repository,
  String initialLocation = AppRoutes.signIn,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInPage()),
      // 앱 라우터와 같은 모양 — 주소의 `token` 을 화면에 넘긴다.
      GoRoute(
        path: AppRoutes.passwordReset,
        builder: (_, GoRouterState state) =>
            PasswordResetPage(initialCode: state.uri.queryParameters['token']),
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
        passwordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: const Locale('ko'),
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

Future<void> _fillConfirm(
  WidgetTester tester, {
  String? code,
  String next = _newPw,
  String? confirm,
}) async {
  if (code != null) await tester.enterText(_key('passwordReset-code'), code);
  await tester.enterText(_key('passwordReset-next'), next);
  await tester.enterText(_key('passwordReset-confirm'), confirm ?? next);
  await tester.pump();
}

void main() {
  testWidgets('로그인 화면의 비밀번호 찾기가 재설정 화면을 연다', (tester) async {
    final AppLocalizations l = await _pump(tester, repository: _FakeReset());
    expect(find.text(l.authForgotPassword), findsOneWidget);
    await _tap(tester, _key('member-login-forgot-password'));
    expect(find.byType(PasswordResetPage), findsOneWidget);
    expect(find.byKey(const Key('passwordResetRequestStep')), findsOneWidget);
  });

  testWidgets('뒤로 가면 로그인 화면으로 돌아간다', (tester) async {
    await _pump(tester, repository: _FakeReset());
    await _tap(tester, _key('member-login-forgot-password'));
    await _tap(tester, find.byType(AppBackButton));
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('이메일 형식이 틀리면 요청하지 않는다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      initialLocation: AppRoutes.passwordReset,
    );
    await tester.enterText(_key('passwordReset-email'), 'not-an-email');
    await _tap(tester, _key('passwordReset-send'));
    expect(repo.requested, isEmpty);
    expect(find.text(l.authEmailInvalid), findsOneWidget);
  });

  testWidgets('요청하면 같은 안내와 함께 코드 입력 단계로 간다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      initialLocation: AppRoutes.passwordReset,
    );
    await tester.enterText(_key('passwordReset-email'), ' member@example.com ');
    await _tap(tester, _key('passwordReset-send'));
    expect(repo.requested, <String>['member@example.com']);
    expect(find.byKey(const Key('passwordResetConfirmStep')), findsOneWidget);
    expect(
      find.text(l.passwordResetSentBody('member@example.com', 30)),
      findsOneWidget,
    );
    // 실 서버는 코드를 알려 주지 않는다 — 칸은 비어 있다.
    expect(find.byKey(const Key('passwordResetDemoNotice')), findsNothing);
  });

  testWidgets('코드를 넣고 바꾸면 완료 단계에서 로그인하러 간다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      initialLocation: AppRoutes.passwordReset,
    );
    await _tap(tester, _key('passwordReset-have-code'));
    await _fillConfirm(tester, code: 'abcd efgh jkmn pqrs');
    await _tap(tester, _key('passwordReset-submit'));
    expect(repo.confirmed, <(String, String)>[('abcd efgh jkmn pqrs', _newPw)]);
    expect(find.byKey(const Key('passwordResetDoneStep')), findsOneWidget);
    expect(find.text(l.passwordResetDoneBody), findsOneWidget);

    await _tap(tester, _key('passwordReset-to-sign-in'));
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets('모양이 틀린 코드는 보내지 않는다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      initialLocation: AppRoutes.passwordReset,
    );
    await _tap(tester, _key('passwordReset-have-code'));
    await _fillConfirm(tester, code: 'ABCD-1234');
    await _tap(tester, _key('passwordReset-submit'));
    expect(repo.confirmed, isEmpty);
    expect(find.text(l.passwordResetCodeMalformed), findsOneWidget);
  });

  testWidgets('틀리거나 만료된 코드는 코드 칸에 알리고 다시 받게 한다', (tester) async {
    final _FakeReset repo = _FakeReset(
      confirmError: const PasswordResetError(PasswordResetFailure.invalidCode),
    );
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      initialLocation: AppRoutes.passwordReset,
    );
    await _tap(tester, _key('passwordReset-have-code'));
    await _fillConfirm(tester, code: _code);
    await _tap(tester, _key('passwordReset-submit'));
    expect(find.text(l.passwordResetCodeInvalid), findsOneWidget);
    expect(find.byKey(const Key('passwordResetConfirmStep')), findsOneWidget);

    await _tap(tester, _key('passwordReset-resend'));
    expect(find.byKey(const Key('passwordResetRequestStep')), findsOneWidget);
  });

  testWidgets('새 비밀번호는 가입과 같은 규칙으로 본다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      initialLocation: AppRoutes.passwordReset,
    );
    await _tap(tester, _key('passwordReset-have-code'));
    await _fillConfirm(tester, code: _code, next: '12345678');
    await _tap(tester, _key('passwordReset-submit'));
    expect(repo.confirmed, isEmpty);
    expect(find.text(l.signUpPasswordWeak), findsOneWidget);
  });

  testWidgets('메일 링크의 코드로 들어오면 코드 칸이 채워진 채 시작한다', (tester) async {
    await _pump(
      tester,
      repository: _FakeReset(),
      initialLocation: '${AppRoutes.passwordReset}?token=abcdefghjkmnpqrs',
    );
    expect(find.byKey(const Key('passwordResetConfirmStep')), findsOneWidget);
    expect(find.text(_code), findsOneWidget);
  });

  testWidgets('발송 수단이 없는 서버면 알리고 요청 단계에 머문다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      repository: _FakeReset(
        requestError: const PasswordResetError(
          PasswordResetFailure.unavailable,
        ),
      ),
      initialLocation: AppRoutes.passwordReset,
    );
    await tester.enterText(_key('passwordReset-email'), 'member@example.com');
    await _tap(tester, _key('passwordReset-send'));
    expect(find.text(l.passwordResetUnavailable), findsOneWidget);
    expect(find.byKey(const Key('passwordResetRequestStep')), findsOneWidget);
  });

  testWidgets('데모는 메일 대신 코드 칸을 채워 끝까지 갈 수 있게 한다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      repository: const MockPasswordRepository(),
      initialLocation: AppRoutes.passwordReset,
    );
    await tester.enterText(_key('passwordReset-email'), 'demo@example.com');
    await _tap(tester, _key('passwordReset-send'));
    expect(find.text(l.passwordResetDemoNote), findsOneWidget);
    expect(find.text(MockPasswordRepository.demoCode), findsOneWidget);

    await _fillConfirm(tester);
    await _tap(tester, _key('passwordReset-submit'));
    expect(find.byKey(const Key('passwordResetDoneStep')), findsOneWidget);
  });
}

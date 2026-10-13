/// 로그인 화면의 `아이디 찾기` 와 아이디 찾기 화면.
///
/// 입구·뒤로 가기·입력 검사와, 찾은 결과(찾음·소셜 가입·없음)·실패 안내·결과에서
/// 로그인·비밀번호 재설정으로 가는 길을 본다(#3337). 요청은 대역 저장소가 받는다.
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
import 'package:oncare/features/auth/domain/find_email.dart';
import 'package:oncare/features/auth/presentation/controllers/find_email_providers.dart';
import 'package:oncare/features/auth/presentation/pages/find_email_page.dart';
import 'package:oncare/features/auth/presentation/pages/password_reset_page.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// 정해 둔 결과를 돌려주고 받은 요청을 적어 두는 대역.
class _FakeFindEmail implements FindEmailRepository {
  _FakeFindEmail({this.accounts = const <FoundEmailAccount>[], this.error});

  final List<FoundEmailAccount> accounts;
  final Object? error;
  final List<(String, String)> calls = <(String, String)>[];

  @override
  Future<List<FoundEmailAccount>> find({
    required String name,
    required String phone,
  }) async {
    calls.add((name, phone));
    final Object? e = error;
    if (e != null) throw e;
    return accounts;
  }
}

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  FindEmailRepository? repository,
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
        findEmailRepositoryProvider.overrideWithValue(
          repository ?? _FakeFindEmail(),
        ),
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

/// 이름·번호를 맞게 넣고 찾기를 누른다.
Future<void> _submit(WidgetTester tester) async {
  await tester.enterText(_key('findEmail-name'), ' 김온케어 ');
  await tester.enterText(_key('findEmail-phone'), '01012345678');
  await tester.pump();
  await _tap(tester, _key('findEmail-submit'));
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
    // 찾기 전에는 결과가 없다.
    expect(find.byKey(const Key('findEmailFormStep')), findsOneWidget);
    expect(find.byKey(const Key('findEmailFoundStep')), findsNothing);
    expect(find.byKey(const Key('findEmailNotFoundStep')), findsNothing);
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

  testWidgets('비어 있거나 형식이 틀리면 칸 아래에 오류를 띄우고 요청하지 않는다', (tester) async {
    final _FakeFindEmail repo = _FakeFindEmail();
    await _pump(tester, initialLocation: AppRoutes.findEmail, repository: repo);

    await _tap(tester, _key('findEmail-submit'));
    expect(_errorOf(tester, 'findEmail-name'), isNotNull);
    expect(_errorOf(tester, 'findEmail-phone'), isNotNull);

    await tester.enterText(_key('findEmail-name'), '김온케어');
    await tester.enterText(_key('findEmail-phone'), '0101234');
    await _tap(tester, _key('findEmail-submit'));
    expect(_errorOf(tester, 'findEmail-name'), isNull);
    expect(_errorOf(tester, 'findEmail-phone'), isNotNull);
    expect(repo.calls, isEmpty);
  });

  testWidgets('맞으면 가려진 이메일을 보여 준다', (tester) async {
    final _FakeFindEmail repo = _FakeFindEmail(
      accounts: const <FoundEmailAccount>[
        FoundEmailAccount(maskedEmail: 'on***@oncare.com'),
      ],
    );
    final AppLocalizations l = await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
      repository: repo,
    );

    await tester.enterText(_key('findEmail-name'), ' 김온케어 ');
    // 숫자만 쳐도 가입 화면처럼 하이픈이 들어간다.
    await tester.enterText(_key('findEmail-phone'), '01012345678');
    await tester.pump();
    expect(find.text('010-1234-5678'), findsOneWidget);
    await _tap(tester, _key('findEmail-submit'));

    // 앞뒤 공백을 자른 이름과 하이픈이 든 번호를 보낸다.
    expect(repo.calls, <(String, String)>[('김온케어', '010-1234-5678')]);
    expect(find.byKey(const Key('findEmailFoundStep')), findsOneWidget);
    expect(find.byKey(const Key('findEmailFormStep')), findsNothing);
    expect(find.text('on***@oncare.com'), findsOneWidget);
    expect(find.text(l.findEmailMaskedNote), findsOneWidget);
    expect(find.text(l.findEmailFoundSubtitle), findsOneWidget);
    expect(find.byType(FindEmailPage), findsOneWidget);
  });

  testWidgets('같은 번호의 계정이 여럿이면 모두 보여 준다', (tester) async {
    await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(maskedEmail: 'al***@oncare.com'),
          FoundEmailAccount(maskedEmail: 'br***@example.com'),
        ],
      ),
    );
    await _submit(tester);

    expect(find.text('al***@oncare.com'), findsOneWidget);
    expect(find.text('br***@example.com'), findsOneWidget);
    expect(_key('findEmail-account-0'), findsOneWidget);
    expect(_key('findEmail-account-1'), findsOneWidget);
  });

  testWidgets('소셜 가입 계정은 이메일 대신 가입 수단을 안내한다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(providers: <String>['kakao']),
        ],
      ),
    );
    await _submit(tester);

    expect(_key('findEmail-social-0'), findsOneWidget);
    expect(
      find.text(l.findEmailSocialTitle(l.findEmailProviderKakao)),
      findsOneWidget,
    );
    expect(find.text(l.findEmailSocialBody), findsOneWidget);
    // 재설정할 비밀번호가 없는 계정뿐이면 재설정으로 보내지 않는다.
    expect(_key('findEmail-result-password-reset'), findsNothing);
    expect(_key('findEmail-to-sign-in'), findsOneWidget);
  });

  testWidgets('모르는 가입 수단은 원문 키를 그리지 않고 뭉뚱그려 말한다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(providers: <String>['naver', 'google']),
        ],
      ),
    );
    await _submit(tester);

    expect(find.textContaining('naver'), findsNothing);
    expect(
      find.text(
        l.findEmailSocialTitle(
          '${l.findEmailProviderOther} · ${l.findEmailProviderGoogle}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('맞는 계정이 없으면 오류가 아니라 찾지 못했다고 안내한다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
    );
    await _submit(tester);

    expect(find.byKey(const Key('findEmailNotFoundStep')), findsOneWidget);
    expect(find.text(l.findEmailNotFoundTitle), findsOneWidget);
    expect(find.text(l.findEmailNotFoundBody), findsOneWidget);
    expect(find.text(l.passwordTemporaryFailure), findsNothing);
    expect(_key('findEmail-result-password-reset'), findsNothing);
  });

  testWidgets('다시 찾기를 누르면 넣었던 값이 남은 입력 단계로 돌아간다', (tester) async {
    await _pump(tester, initialLocation: AppRoutes.findEmail);
    await _submit(tester);
    await _tap(tester, _key('findEmail-retry'));

    expect(find.byKey(const Key('findEmailFormStep')), findsOneWidget);
    expect(find.text('010-1234-5678'), findsOneWidget);
  });

  testWidgets('결과에서 로그인 화면으로 간다', (tester) async {
    await _pump(
      tester,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(maskedEmail: 'on***@oncare.com'),
        ],
      ),
    );
    await _tap(tester, _key('member-login-find-email'));
    await _submit(tester);
    await _tap(tester, _key('findEmail-to-sign-in'));
    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.byType(FindEmailPage), findsNothing);
  });

  testWidgets('이메일로 가입한 계정을 찾았으면 결과에서 비밀번호 재설정으로 간다', (tester) async {
    await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(maskedEmail: 'on***@oncare.com'),
        ],
      ),
    );
    await _submit(tester);
    await _tap(tester, _key('findEmail-result-password-reset'));
    expect(find.byType(PasswordResetPage), findsOneWidget);
  });

  testWidgets('연속 시도로 막히면 그 안내를 띄우고 입력 단계에 머문다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        error: const FindEmailError(FindEmailFailure.tooMany),
      ),
    );
    await _submit(tester);

    expect(find.text(l.passwordTooManyAttempts), findsOneWidget);
    expect(find.byKey(const Key('findEmailFormStep')), findsOneWidget);
    expect(find.byKey(const Key('findEmailNotFoundStep')), findsNothing);
  });

  testWidgets('연결 실패는 찾지 못함이 아니라 다시 시도 안내다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      initialLocation: AppRoutes.findEmail,
      repository: _FakeFindEmail(error: StateError('offline')),
    );
    await _submit(tester);

    expect(find.text(l.passwordTemporaryFailure), findsOneWidget);
    expect(find.text(l.findEmailNotFoundTitle), findsNothing);
    expect(find.byKey(const Key('findEmailFormStep')), findsOneWidget);
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
}

/// 로그인·가입 칸의 자동완성 힌트와 비밀번호 저장 시점 — #2295.
///
/// 기기·브라우저의 비밀번호 관리자가 칸을 알아보려면 칸마다 힌트가 있어야
/// 하고, 한 화면의 칸이 한 [AutofillGroup] 에 묶여 있어야 한다. 저장은 서버가
/// 받아 준 뒤에만 한다 — 틀린 비밀번호나 쓰다 만 가입을 저장하라고 권하면 안
/// 된다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/features/auth/presentation/pages/sign_up_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';
import '../../helpers/signup_email_code.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 경로별로 정해 둔 상태 코드로 답하는 서버 흉내. 200·201 이면 토큰을 준다.
/// 상태 코드 대신 `null` 이면 연결 시간 초과로 끊는다.
class _FakeServer {
  _FakeServer({this.login = 200, this.register = 201, this.loginAfter});

  /// `/auth/login` 의 상태 코드. [loginAfter] 가 있으면 첫 요청에만 쓴다.
  final int? login;

  /// 두 번째 로그인부터의 상태 코드(재시도 흐름).
  final int? loginAfter;

  /// `/auth/register` 의 상태 코드.
  final int? register;

  final List<RequestOptions> requests = <RequestOptions>[];

  late final Dio dio = Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          // 가입 인증 코드 요청(#3038)은 늘 받아 준다.
          if (options.path == signupCodePath) {
            handler.resolve(signupCodeAccepted(options));
            return;
          }
          final int? status = switch (options.path) {
            '/auth/login'
                when loginAfter != null && to('/auth/login').length > 1 =>
              loginAfter,
            '/auth/login' => login,
            '/auth/register' => register,
            _ => 404,
          };
          if (status == null) {
            handler.reject(
              DioException.connectionTimeout(
                timeout: const Duration(seconds: 1),
                requestOptions: options,
              ),
            );
            return;
          }
          final Response<Object?> response = Response<Object?>(
            requestOptions: options,
            statusCode: status,
            data: const <String, Object?>{
              'access_token': 'access',
              'refresh_token': 'refresh',
            },
          );
          if (status >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: response,
                type: DioExceptionType.badResponse,
              ),
            );
          } else {
            handler.resolve(response);
          }
        },
      ),
    );

  List<RequestOptions> to(String path) =>
      requests.where((RequestOptions r) => r.path == path).toList();
}

/// 로그인·가입·첫 설정 세 자리만 둔 라우터로 [start] 화면을 띄운다.
Future<(_FakeServer, ProviderContainer)> _pump(
  WidgetTester tester, {
  required String start,
  _FakeServer? server,
  Locale locale = const Locale('ko'),
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final _FakeServer backend = server ?? _FakeServer();
  addTearDown(backend.dio.close);
  final GoRouter router = GoRouter(
    initialLocation: start,
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(path: AppRoutes.signUp, builder: (_, _) => const SignUpPage()),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const Scaffold(body: Text('첫 설정')),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, _) => const Scaffold(body: Text('홈')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config),
      dioProvider.overrideWithValue(backend.dio),
      accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  tester.testTextInput.log.clear();
  return (backend, container);
}

/// 지금까지 플랫폼에 보낸 `finishAutofillContext` 의 `shouldSave` 값들.
List<bool?> _finishCalls(WidgetTester tester) => <bool?>[
  for (final MethodCall call in tester.testTextInput.log)
    if (call.method == 'TextInput.finishAutofillContext')
      call.arguments as bool?,
];

/// 저장하라고(`shouldSave: true`) 알린 횟수.
int _saves(WidgetTester tester) =>
    _finishCalls(tester).where((bool? save) => save == true).length;

Finder _input(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_input(key));

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_input(key), text);
  await tester.pump();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder button = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// [key] 칸을 감싼 [AutofillGroup].
Finder _groupAround(String key) =>
    find.ancestor(of: _input(key), matching: find.byType(AutofillGroup));

void main() {
  group('로그인 화면', () {
    const String email = 'member-login-email';
    const String password = 'member-login-password';
    const String submit = 'member-login-submit';

    Future<(_FakeServer, ProviderContainer)> pumpSignIn(
      WidgetTester tester, {
      _FakeServer? server,
      Locale locale = const Locale('ko'),
    }) =>
        _pump(tester, start: AppRoutes.signIn, server: server, locale: locale);

    Future<void> signIn(WidgetTester tester, {String pw = 'pw'}) async {
      await _type(tester, email, 'minsu@oncare.com');
      await _type(tester, password, pw);
      await _tapKey(tester, submit);
    }

    testWidgets('이메일 칸은 username·email, 비밀번호 칸은 password 힌트다', (tester) async {
      await pumpSignIn(tester);

      expect(find.byType(SignInPage), findsOneWidget);
      expect(_field(tester, email).autofillHints, <String>[
        AutofillHints.username,
        AutofillHints.email,
      ]);
      expect(_field(tester, password).autofillHints, <String>[
        AutofillHints.password,
      ]);
      // 힌트를 붙여도 원래 입력 설정은 그대로다.
      expect(_field(tester, email).keyboardType, TextInputType.emailAddress);
      expect(_field(tester, password).obscureText, isTrue);
    });

    testWidgets('이메일 칸은 자동 대문자·자동 고침이 꺼져 있다(#2816)', (tester) async {
      await pumpSignIn(tester);

      final TextField field = _field(tester, email);
      expect(field.textCapitalization, TextCapitalization.none);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('두 칸이 같은 AutofillGroup 하나에 묶이고, 떠날 때는 취소한다', (tester) async {
      await pumpSignIn(tester);

      expect(
        find.descendant(
          of: find.byType(SignInPage),
          matching: find.byType(AutofillGroup),
        ),
        findsOneWidget,
      );
      final AutofillGroup group = tester.widget<AutofillGroup>(
        _groupAround(email),
      );
      expect(tester.widget(_groupAround(password)), same(group));
      expect(group.onDisposeAction, AutofillContextAction.cancel);
    });

    testWidgets('묶음이 화면 모양을 바꾸지 않는다 — 인증 틀 안에 칸이 그대로다', (tester) async {
      await pumpSignIn(tester);

      // 묶음은 틀과 칸 사이에만 끼어 있다.
      expect(
        find.descendant(
          of: find.byType(AppAuthLayout),
          matching: find.byType(AutofillGroup),
        ),
        findsOneWidget,
      );
      expect(find.byType(AppPasswordToggle), findsOneWidget);
      expect(find.byType(AppSocialLoginRow), findsOneWidget);
    });

    testWidgets('로그인에 성공하면 한 번 저장을 알린다', (tester) async {
      final (_FakeServer server, ProviderContainer container) =
          await pumpSignIn(tester);

      await signIn(tester);

      expect(server.to('/auth/login'), hasLength(1));
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(_saves(tester), 1);
      expect(_finishCalls(tester).first, isTrue);
    });

    for (final int? status in <int?>[401, 500, null]) {
      testWidgets('로그인이 실패하면(${status ?? '시간 초과'}) 저장하지 않는다', (tester) async {
        final (_FakeServer server, ProviderContainer container) =
            await pumpSignIn(tester, server: _FakeServer(login: status));

        await signIn(tester, pw: 'wrong-password');

        expect(server.to('/auth/login'), hasLength(1));
        expect(
          container.read(sessionControllerProvider).status,
          isNot(SessionStatus.authenticated),
        );
        expect(_finishCalls(tester), isEmpty);
        expect(find.byType(SignInPage), findsOneWidget);
      });
    }

    testWidgets('형식이 틀려 요청을 보내지 않으면 저장하지 않는다', (tester) async {
      final (_FakeServer server, _) = await pumpSignIn(tester);

      await _type(tester, email, 'not-an-email');
      await _tapKey(tester, submit);

      expect(server.requests, isEmpty);
      expect(_finishCalls(tester), isEmpty);
    });

    testWidgets('실패한 뒤 다시 맞게 로그인하면 그때 한 번 저장한다', (tester) async {
      final (_FakeServer server, _) = await pumpSignIn(
        tester,
        server: _FakeServer(login: 401, loginAfter: 200),
      );

      await signIn(tester, pw: 'wrong');
      expect(_saves(tester), 0);

      await _type(tester, password, 'right');
      await _tapKey(tester, submit);

      expect(server.to('/auth/login'), hasLength(2));
      expect(_saves(tester), 1);
    });

    testWidgets('실패한 채 화면이 사라지면 저장이 아니라 취소를 알린다', (tester) async {
      await pumpSignIn(tester, server: _FakeServer(login: 401));

      await signIn(tester, pw: 'wrong-password');
      await tester.pumpWidget(const SizedBox.shrink());

      expect(_finishCalls(tester), <bool?>[false]);
    });

    testWidgets('소셜 로그인은 입력한 칸과 무관해 저장하지 않는다', (tester) async {
      final (_FakeServer server, _) = await pumpSignIn(tester);

      await _tapKey(tester, 'member-login-kakao');

      expect(server.requests, isNotEmpty);
      expect(_saves(tester), 0);
    });

    testWidgets('영어 화면에서도 힌트와 묶음이 같다', (tester) async {
      await pumpSignIn(tester, locale: const Locale('en'));

      expect(find.text('Sign in'), findsWidgets);
      expect(_field(tester, email).autofillHints, <String>[
        AutofillHints.username,
        AutofillHints.email,
      ]);
      expect(_field(tester, password).autofillHints, <String>[
        AutofillHints.password,
      ]);
      expect(_groupAround(password), findsOneWidget);
    });
  });

  group('가입 화면', () {
    const String name = 'member-signup-name';
    const String email = 'member-signup-email';
    const String phone = 'member-signup-phone';
    const String password = 'member-signup-password';
    const String confirm = 'member-signup-password-confirm';
    const String submit = 'member-signup-submit';

    Future<(_FakeServer, ProviderContainer)> pumpSignUp(
      WidgetTester tester, {
      _FakeServer? server,
      Locale locale = const Locale('ko'),
    }) =>
        _pump(tester, start: AppRoutes.signUp, server: server, locale: locale);

    Future<void> fill(WidgetTester tester, {String? confirmValue}) async {
      await _type(tester, name, '김민수');
      await _type(tester, email, 'new@oncare.com');
      await _type(tester, phone, '01012345678');
      await _type(tester, password, 'signup-pw-1234');
      await _type(tester, confirm, confirmValue ?? 'signup-pw-1234');
      // 인증 코드 여섯 자리와(#3038) 필수 동의 없이는(#2819) 가입 버튼이 꺼져 있다.
      await passSignupCode(tester);
      await _tapKey(tester, 'consent-all');
    }

    testWidgets('칸마다 name·username/email·국내 전화·newPassword 힌트다', (
      tester,
    ) async {
      await pumpSignUp(tester);

      expect(find.byType(SignUpPage), findsOneWidget);
      expect(_field(tester, name).autofillHints, <String>[AutofillHints.name]);
      expect(_field(tester, email).autofillHints, <String>[
        AutofillHints.username,
        AutofillHints.email,
      ]);
      // `+82` 가 붙지 않는 국내 번호로 채워져야 010 형식 검사를 지난다.
      expect(_field(tester, phone).autofillHints, <String>[
        AutofillHints.telephoneNumberNational,
      ]);
      // 가입은 저장된 비밀번호가 아니라 새 비밀번호를 받는 자리다.
      expect(_field(tester, password).autofillHints, <String>[
        AutofillHints.newPassword,
      ]);
      expect(_field(tester, confirm).autofillHints, <String>[
        AutofillHints.newPassword,
      ]);
    });

    testWidgets('전화번호 칸은 힌트를 달아도 하이픈 넣기가 그대로다', (tester) async {
      await pumpSignUp(tester);

      expect(
        _field(tester, phone).inputFormatters,
        contains(isA<AppPhoneNumberFormatter>()),
      );
      await _type(tester, phone, '01012345678');
      expect(_field(tester, phone).controller!.text, '010-1234-5678');
    });

    testWidgets('이메일 칸은 자동 대문자·자동 고침이 꺼져 있다(#2816)', (tester) async {
      await pumpSignUp(tester);

      final TextField field = _field(tester, email);
      expect(field.textCapitalization, TextCapitalization.none);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('다섯 칸이 같은 AutofillGroup 하나에 묶이고, 떠날 때는 취소한다', (tester) async {
      await pumpSignUp(tester);

      expect(
        find.descendant(
          of: find.byType(SignUpPage),
          matching: find.byType(AutofillGroup),
        ),
        findsOneWidget,
      );
      final AutofillGroup group = tester.widget<AutofillGroup>(
        _groupAround(name),
      );
      for (final String key in <String>[email, phone, password, confirm]) {
        expect(tester.widget(_groupAround(key)), same(group), reason: key);
      }
      expect(group.onDisposeAction, AutofillContextAction.cancel);
    });

    testWidgets('가입에 성공하면 한 번 저장을 알리고 첫 설정으로 간다', (tester) async {
      final (_FakeServer server, _) = await pumpSignUp(tester);
      await fill(tester);

      await _tapKey(tester, submit);

      expect(server.to('/auth/register'), hasLength(1));
      expect(_saves(tester), 1);
      expect(_finishCalls(tester).first, isTrue);
      expect(find.text('첫 설정'), findsOneWidget);
    });

    testWidgets('계정은 만들어졌는데 로그인만 실패해도 저장한다', (tester) async {
      // 자격 증명은 이제 유효하다 — 저장해 두면 곧 볼 로그인 화면에서 채워진다.
      final (_FakeServer server, _) = await pumpSignUp(
        tester,
        server: _FakeServer(login: null),
      );
      await fill(tester);

      await _tapKey(tester, submit);

      expect(server.to('/auth/register'), hasLength(1));
      expect(server.to('/auth/login'), hasLength(1));
      expect(_saves(tester), 1);
      expect(find.byType(SignInPage), findsOneWidget);
    });

    for (final int? status in <int?>[409, 500, null]) {
      testWidgets('가입이 거절되면(${status ?? '시간 초과'}) 저장하지 않는다', (tester) async {
        final (_FakeServer server, _) = await pumpSignUp(
          tester,
          server: _FakeServer(register: status),
        );
        await fill(tester);

        await _tapKey(tester, submit);

        expect(server.to('/auth/register'), hasLength(1));
        expect(server.to('/auth/login'), isEmpty);
        expect(_finishCalls(tester), isEmpty);
        expect(find.byType(SignUpPage), findsOneWidget);
      });
    }

    testWidgets('형식이 틀려 보내지 않은 가입은 저장하지 않는다', (tester) async {
      final (_FakeServer server, _) = await pumpSignUp(tester);
      await fill(tester, confirmValue: 'different-pw1');

      await _tapKey(tester, submit);

      expect(server.to('/auth/register'), isEmpty);
      expect(_finishCalls(tester), isEmpty);
    });

    testWidgets('쓰다가 뒤로 나가면 저장이 아니라 취소를 알린다', (tester) async {
      await pumpSignUp(tester);
      await fill(tester);

      await tester.tap(find.byType(AppBackButton));
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.byType(SignUpPage), findsNothing);
      expect(_saves(tester), 0);
      expect(_finishCalls(tester), <bool?>[false]);
    });

    testWidgets('영어 화면에서도 힌트와 묶음이 같다', (tester) async {
      await pumpSignUp(tester, locale: const Locale('en'));

      expect(find.text('Sign up'), findsWidgets);
      expect(_field(tester, name).autofillHints, <String>[AutofillHints.name]);
      expect(_field(tester, confirm).autofillHints, <String>[
        AutofillHints.newPassword,
      ]);
      expect(_groupAround(phone), findsOneWidget);
    });
  });
}

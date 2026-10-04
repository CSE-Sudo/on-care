/// 회원 앱에 트레이너 계정으로 로그인하면 들어가지 않고 트레이너 웹을 안내한다.
/// (#3137)
///
/// 세션 복구는 역할을 확인했지만(#3054) 이메일·소셜 로그인은 토큰을 곧장
/// 저장했다. 서버는 트레이너 토큰에 회원 API 를 403 으로 거절하므로, 로그인
/// 직후부터 모든 회원 화면이 오류가 됐다. 지금은 저장 전에 응답의 `role` 을
/// 보고, 트레이너면 토큰을 폐기하고 로그인 화면에 안내를 남긴다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/features/auth/presentation/trainer_web_address.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppBanner;

import '../../helpers/mock_account_repository.dart';

const ValueKey<String> _noticeKey = ValueKey<String>(
  'member-login-trainer-account',
);

/// 로그인·소셜 로그인은 [loginBody] 로 답하고, 폐기는 204 로 받는다.
Dio _authDio(Map<String, Object?> loginBody, List<RequestOptions> requests) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        if (options.path == '/auth/logout') {
          handler.resolve(
            Response<void>(requestOptions: options, statusCode: 204),
          );
          return;
        }
        handler.resolve(
          Response<Map<String, Object?>>(
            requestOptions: options,
            statusCode: 200,
            data: loginBody,
          ),
        );
      },
    ),
  );
  return dio;
}

Map<String, Object?> _tokens({String? role}) => <String, Object?>{
  'access_token': 'issued-access',
  'refresh_token': 'issued-refresh',
  'token_type': 'bearer',
  'consent_required': false,
  'role': ?role,
};

Future<void> _waitSignedOut(ProviderContainer c) async {
  for (var i = 0; i < 40; i++) {
    if (c.read(sessionControllerProvider).status == SessionStatus.signedOut) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('세션이 로그아웃 상태로 정해지지 않았다');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const FlutterSecureStorage secure = FlutterSecureStorage();
  late List<RequestOptions> requests;

  setUp(() {
    requests = <RequestOptions>[];
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  Future<ProviderContainer> containerFor(Map<String, Object?> body) async {
    final Dio dio = _authDio(body, requests);
    addTearDown(dio.close);
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWithValue(dio),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(c.dispose);
    c.read(sessionControllerProvider.notifier);
    await _waitSignedOut(c);
    return c;
  }

  group('이메일 로그인', () {
    test('트레이너 계정이면 들어가지 않고 토큰을 남기지 않는다', () async {
      final ProviderContainer c = await containerFor(_tokens(role: 'trainer'));

      await expectLater(
        c
            .read(sessionControllerProvider.notifier)
            .login(email: 'trainer@oncare.com', password: 'pw'),
        throwsA(isA<TrainerAccountSignInRejected>()),
      );

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(c.read(authAccessTokenProvider), isNull);
      expect(await secure.readAll(), isEmpty);
      expect(c.read(trainerAccountNoticeProvider), isTrue);
    });

    test('받은 갱신 토큰은 서버에서 폐기한다', () async {
      final ProviderContainer c = await containerFor(_tokens(role: 'trainer'));

      await c
          .read(sessionControllerProvider.notifier)
          .login(email: 'trainer@oncare.com', password: 'pw')
          .catchError((Object _) {});

      final RequestOptions logout = requests.singleWhere(
        (RequestOptions r) => r.path == '/auth/logout',
      );
      expect(logout.data, <String, Object?>{'refresh_token': 'issued-refresh'});
    });

    test('폐기가 실패해도 안내 상태로 끝난다', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (RequestOptions o, RequestInterceptorHandler h) {
              if (o.path == '/auth/logout') {
                h.reject(DioException(requestOptions: o));
                return;
              }
              h.resolve(
                Response<Map<String, Object?>>(
                  requestOptions: o,
                  statusCode: 200,
                  data: _tokens(role: 'trainer'),
                ),
              );
            },
          ),
        );
      addTearDown(dio.close);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          dioProvider.overrideWithValue(dio),
          sessionFeatureResetOverride(),
        ],
      );
      addTearDown(c.dispose);
      c.read(sessionControllerProvider.notifier);
      await _waitSignedOut(c);

      await expectLater(
        c
            .read(sessionControllerProvider.notifier)
            .login(email: 'trainer@oncare.com', password: 'pw'),
        throwsA(isA<TrainerAccountSignInRejected>()),
      );
      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(c.read(trainerAccountNoticeProvider), isTrue);
      expect(await secure.readAll(), isEmpty);
    });

    test('회원 계정은 지금처럼 들어가고 안내를 거둔다', () async {
      final ProviderContainer c = await containerFor(_tokens(role: 'member'));
      c.read(trainerAccountNoticeProvider.notifier).state = true;

      await c
          .read(sessionControllerProvider.notifier)
          .login(email: 'member@oncare.com', password: 'pw');

      expect(
        c.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(c.read(authAccessTokenProvider), 'issued-access');
      expect(await secure.readAll(), isNotEmpty);
      expect(c.read(trainerAccountNoticeProvider), isFalse);
      expect(
        requests.where((RequestOptions r) => r.path == '/auth/logout'),
        isEmpty,
      );
    });

    test('역할이 없는 응답(배포 전 서버)은 지금처럼 들어간다', () async {
      final ProviderContainer c = await containerFor(_tokens());

      await c
          .read(sessionControllerProvider.notifier)
          .login(email: 'member@oncare.com', password: 'pw');

      expect(
        c.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
    });

    test('빈 역할도 회원으로 본다', () async {
      final ProviderContainer c = await containerFor(_tokens(role: ''));

      await c
          .read(sessionControllerProvider.notifier)
          .login(email: 'member@oncare.com', password: 'pw');

      expect(
        c.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
    });
  });

  group('소셜 로그인', () {
    test('트레이너 계정이면 들어가지 않고 토큰을 남기지 않는다', () async {
      final ProviderContainer c = await containerFor(_tokens(role: 'trainer'));

      await expectLater(
        c
            .read(sessionControllerProvider.notifier)
            .socialLogin(provider: 'kakao', token: 'provider-token'),
        throwsA(isA<TrainerAccountSignInRejected>()),
      );

      expect(c.read(sessionControllerProvider).status, SessionStatus.signedOut);
      expect(c.read(authAccessTokenProvider), isNull);
      expect(await secure.readAll(), isEmpty);
      expect(c.read(trainerAccountNoticeProvider), isTrue);
      expect(
        requests.map((RequestOptions r) => r.path),
        containsAll(<String>['/auth/social/kakao', '/auth/logout']),
      );
    });

    test('회원 계정은 지금처럼 들어간다', () async {
      final ProviderContainer c = await containerFor(_tokens(role: 'member'));

      await c
          .read(sessionControllerProvider.notifier)
          .socialLogin(provider: 'google', token: 'provider-token');

      expect(
        c.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
    });
  });

  group('트레이너 웹 주소', () {
    test('웹에서는 같은 배포의 /trainer/ 다', () {
      expect(
        trainerWebAddress(
          isWeb: true,
          page: Uri.parse('https://ewhasudo.zapto.org/frontend/#/sign-in'),
        ),
        Uri.parse('https://ewhasudo.zapto.org/trainer/'),
      );
      expect(
        trainerWebAddress(
          isWeb: true,
          page: Uri.parse('https://oncare.test/frontend/index.html?x=1'),
        ),
        Uri.parse('https://oncare.test/trainer/'),
      );
    });

    test('모바일 앱에는 주소가 없다', () {
      expect(trainerWebAddress(isWeb: false), isNull);
    });
  });

  group('로그인 화면', () {
    Future<ProviderContainer> pumpSignIn(
      WidgetTester tester,
      Map<String, Object?> body,
      Locale locale,
    ) async {
      final Dio dio = _authDio(body, requests);
      addTearDown(dio.close);
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
            dioProvider.overrideWithValue(dio),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
            sessionFeatureResetOverride(),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SignInPage(),
          ),
        ),
      );
      final ProviderContainer c = ProviderScope.containerOf(
        tester.element(find.byType(SignInPage)),
      );
      c.read(sessionControllerProvider);
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const ValueKey<String>('member-login-email')),
        'trainer@oncare.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('member-login-password')),
        'oncare123',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('member-login-submit')),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    for (final Locale locale in const <Locale>[Locale('ko'), Locale('en')]) {
      testWidgets('트레이너 계정 로그인은 트레이너 웹 안내를 보인다 (${locale.languageCode})', (
        WidgetTester tester,
      ) async {
        final ProviderContainer c = await pumpSignIn(
          tester,
          _tokens(role: 'trainer'),
          locale,
        );
        final AppLocalizations l = AppLocalizations.of(
          tester.element(find.byType(SignInPage)),
        );
        expect(find.byKey(_noticeKey), findsNothing);

        await submit(tester);

        expect(find.byKey(_noticeKey), findsOneWidget);
        expect(find.byType(AppBanner), findsOneWidget);
        expect(find.text(l.authTrainerAccountTitle), findsOneWidget);
        expect(find.text(l.authTrainerAccountMessage), findsOneWidget);
        // 모바일 앱에는 열 주소가 없다 — 문구만 보인다.
        expect(find.text(l.authTrainerAccountOpenWeb), findsNothing);
        // 실패 토스트(비밀번호·서버 탓)로 알리지 않는다.
        expect(find.text(l.authSignInFailed), findsNothing);
        expect(find.text(l.authSignInUnavailable), findsNothing);
        expect(find.byType(SignInPage), findsOneWidget);
        expect(
          c.read(sessionControllerProvider).status,
          SessionStatus.signedOut,
        );
        await tester.pumpAndSettle();
      });
    }

    testWidgets('회원 계정 로그인에는 안내가 없다', (WidgetTester tester) async {
      final ProviderContainer c = await pumpSignIn(
        tester,
        _tokens(role: 'member'),
        const Locale('ko'),
      );

      await submit(tester);

      expect(find.byKey(_noticeKey), findsNothing);
      expect(
        c.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      await tester.pumpAndSettle();
    });
  });
}

/// 카카오·구글 실연동 로그인(#330).
///
/// SDK·브라우저 팝업·구글 버튼은 가짜 경계로 바꿔 끼우고, 화면이 받은 provider 토큰을
/// 서버(`/auth/social/{provider}`)로 보내는지, 키가 없는 provider 는 꺼 두는지, 취소는
/// 조용히 넘기고 실패·팝업 차단은 알리는지를 본다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/member_social_login.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_social_login/oncare_social_login.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppSocialLoginButton;

import '../../helpers/fake_social_login.dart';
import '../../helpers/mock_account_repository.dart';

const SocialLoginConfig _allKeys = SocialLoginConfig(
  kakaoNativeAppKey: kTestKakaoKey,
  kakaoLoginRestApiKey: kTestKakaoKey,
  googleWebClientId: kTestGoogleWebClientId,
);

AppConfig _real(SocialLoginConfig social) => AppConfig(
  environment: Environment.prod,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: false,
  socialLogin: social,
);

const Key _kakao = ValueKey<String>('member-login-kakao');
const Key _google = ValueKey<String>('member-login-google');
const Key _soon = ValueKey<String>('member-login-social-soon');

class _Harness {
  _Harness(this.tester, this.container, this.requests);

  final WidgetTester tester;
  final ProviderContainer container;
  final List<RequestOptions> requests;

  Iterable<RequestOptions> get socialRequests =>
      requests.where((r) => r.path.startsWith('/auth/social'));

  SessionStatus get status => container.read(sessionControllerProvider).status;

  AppLocalizations get l =>
      AppLocalizations.of(tester.element(find.byType(SignInPage)));

  bool enabled(Key key) =>
      tester.widget<AppSocialLoginButton>(find.byKey(key)).onPressed != null;

  Future<void> tap(Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await settle();
  }

  Future<void> settle() async {
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  SocialLoginConfig social = _allKeys,
  SocialLoginPlatform platform = SocialLoginPlatform.android,
  FakeKakaoGateway? kakao,
  FakeGoogleGateway? google,
  FakeKakaoPopup? popup,
  bool failSocial = false,
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final List<RequestOptions> requests = <RequestOptions>[];
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.path == '/auth/social/kakao/code') {
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                data: <String, Object?>{'access_token': 'exchanged-kakao'},
              ),
            );
            return;
          }
          if (options.path.startsWith('/auth/social/')) {
            if (failSocial) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Object?>(
                    requestOptions: options,
                    statusCode: 401,
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                data: <String, Object?>{
                  'access_token': 'live-access',
                  'refresh_token': 'live-refresh',
                },
              ),
            );
            return;
          }
          handler.reject(DioException(requestOptions: options));
        },
      ),
    );
  addTearDown(dio.close);
  final FakeGoogleGateway googleGateway = google ?? FakeGoogleGateway();
  final FakeKakaoPopup kakaoPopup = popup ?? FakeKakaoPopup();
  addTearDown(googleGateway.dispose);
  addTearDown(kakaoPopup.dispose);
  final AppConfig config = _real(social);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        dioProvider.overrideWithValue(dio),
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
        socialLoginServiceProvider.overrideWith(
          (ref) => SocialLoginService(
            config: social,
            platform: platform,
            exchangeKakaoCode: (code, redirectUri) => exchangeKakaoCode(
              ref.read(dioProvider),
              code: code,
              redirectUri: redirectUri,
            ),
            kakaoGateway: kakao ?? FakeKakaoGateway(),
            googleGateway: googleGateway,
            kakaoPopup: kakaoPopup,
          ),
        ),
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
  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byType(SignInPage)),
  );
  container.read(sessionControllerProvider);
  await tester.pumpAndSettle();
  requests.clear();
  return _Harness(tester, container, requests);
}

void main() {
  testWidgets('모바일 카카오 — SDK 토큰으로 서버 로그인한다', (tester) async {
    final _Harness h = await _pump(tester);

    expect(h.enabled(_kakao), isTrue);
    expect(find.byKey(_soon), findsNothing);
    await h.tap(_kakao);

    final RequestOptions request = h.socialRequests.single;
    expect(request.path, '/auth/social/kakao');
    expect(request.data, <String, Object?>{'token': 'kakao-sdk-token'});
    expect(h.status, SessionStatus.authenticated);
  });

  testWidgets('모바일 구글 — ID 토큰으로 서버 로그인한다', (tester) async {
    final _Harness h = await _pump(tester);

    await h.tap(_google);

    final RequestOptions request = h.socialRequests.single;
    expect(request.path, '/auth/social/google');
    expect(request.data, <String, Object?>{'token': 'google-id-token'});
    expect(h.status, SessionStatus.authenticated);
  });

  testWidgets('키가 있는 provider 만 켜고, 하나라도 있으면 준비 중 안내는 없다', (tester) async {
    final _Harness h = await _pump(
      tester,
      social: const SocialLoginConfig(
        googleWebClientId: kTestGoogleWebClientId,
      ),
    );

    expect(h.enabled(_kakao), isFalse);
    expect(h.enabled(_google), isTrue);
    expect(find.byKey(_soon), findsNothing);
  });

  testWidgets('키가 하나도 없으면 두 버튼을 끄고 준비 중 안내를 보인다', (tester) async {
    final _Harness h = await _pump(tester, social: const SocialLoginConfig());

    expect(h.enabled(_kakao), isFalse);
    expect(h.enabled(_google), isFalse);
    expect(find.byKey(_soon), findsOneWidget);
  });

  testWidgets('창을 닫으면 아무 안내 없이 화면에 머문다', (tester) async {
    final FakeGoogleGateway google = FakeGoogleGateway()
      ..error = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
    final _Harness h = await _pump(tester, google: google);

    await h.tap(_google);

    expect(h.socialRequests, isEmpty);
    expect(find.text(h.l.authSocialSignInFailed), findsNothing);
    // 다시 누를 수 있다.
    expect(h.enabled(_google), isTrue);
    expect(h.enabled(_kakao), isTrue);
  });

  testWidgets('SDK 오류는 실패 안내', (tester) async {
    final FakeKakaoGateway kakao = FakeKakaoGateway()
      ..error = StateError('kakao down');
    final _Harness h = await _pump(tester, kakao: kakao);

    await h.tap(_kakao);

    expect(h.socialRequests, isEmpty);
    expect(find.text(h.l.authSocialSignInFailed), findsOneWidget);
    expect(h.enabled(_kakao), isTrue);
  });

  testWidgets('서버가 토큰을 거절하면 실패 안내, 로그인하지 않는다', (tester) async {
    final _Harness h = await _pump(tester, failSocial: true);

    await h.tap(_kakao);

    expect(h.socialRequests.single.path, '/auth/social/kakao');
    expect(h.status, isNot(SessionStatus.authenticated));
    expect(find.text(h.l.authSocialSignInFailed), findsOneWidget);
  });

  group('웹', () {
    testWidgets('카카오 — 팝업을 기다리는 동안 화면을 막지 않고, 코드를 서버에서 바꿔 로그인한다', (
      tester,
    ) async {
      final FakeKakaoPopup popup = FakeKakaoPopup();
      final _Harness h = await _pump(
        tester,
        platform: SocialLoginPlatform.web,
        popup: popup,
      );

      await h.tap(_kakao);

      expect(popup.opened.single.host, 'kauth.kakao.com');
      expect(popup.opened.single.queryParameters['client_id'], kTestKakaoKey);
      expect(
        popup.opened.single.queryParameters['redirect_uri'],
        'https://app.test/frontend/kakao_login_callback.html',
      );
      expect(h.socialRequests, isEmpty);
      // 기다리는 동안에도 다시 누를 수 있다.
      expect(h.enabled(_kakao), isTrue);

      popup.approve('auth-code');
      await h.settle();

      final List<RequestOptions> calls = h.socialRequests.toList();
      expect(calls.map((r) => r.path), <String>[
        '/auth/social/kakao/code',
        '/auth/social/kakao',
      ]);
      expect(calls.first.data, <String, Object?>{
        'code': 'auth-code',
        'redirect_uri': 'https://app.test/frontend/kakao_login_callback.html',
      });
      expect(calls.last.data, <String, Object?>{'token': 'exchanged-kakao'});
      expect(h.status, SessionStatus.authenticated);
    });

    testWidgets('카카오 — 팝업이 막히면 허용하라고 알린다', (tester) async {
      final _Harness h = await _pump(
        tester,
        platform: SocialLoginPlatform.web,
        popup: FakeKakaoPopup(allow: false),
      );

      await h.tap(_kakao);

      expect(find.text(h.l.authSocialPopupBlocked), findsOneWidget);
      expect(h.socialRequests, isEmpty);
    });

    testWidgets('구글 — 구글 버튼이 준 ID 토큰으로 로그인한다', (tester) async {
      final FakeGoogleGateway google = FakeGoogleGateway();
      final _Harness h = await _pump(
        tester,
        platform: SocialLoginPlatform.web,
        google: google,
      );

      // 테스트(웹 아님)에서는 구글 버튼 대신 꺼진 앱 버튼이 자리를 지킨다.
      expect(find.byKey(_google), findsOneWidget);
      expect(h.enabled(_google), isFalse);

      google.webEvents.add('gis-id-token');
      await h.settle();

      final RequestOptions request = h.socialRequests.single;
      expect(request.path, '/auth/social/google');
      expect(request.data, <String, Object?>{'token': 'gis-id-token'});
      expect(h.status, SessionStatus.authenticated);
    });

    testWidgets('구글 — 버튼에서 창을 닫은 것은 조용히 넘긴다', (tester) async {
      final FakeGoogleGateway google = FakeGoogleGateway();
      final _Harness h = await _pump(
        tester,
        platform: SocialLoginPlatform.web,
        google: google,
      );

      google.webEvents.addError(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );
      await h.settle();

      expect(h.socialRequests, isEmpty);
      expect(find.text(h.l.authSocialSignInFailed), findsNothing);
    });
  });

  group('exchangeKakaoCode', () {
    Dio dioAnswering(Object? body, List<RequestOptions> seen) =>
        Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                seen.add(options);
                handler.resolve(
                  Response<Object?>(requestOptions: options, data: body),
                );
              },
            ),
          );

    test('코드와 콜백 주소를 보내고 access_token 을 받는다', () async {
      final List<RequestOptions> seen = <RequestOptions>[];
      final String token = await exchangeKakaoCode(
        dioAnswering(<String, Object?>{'access_token': 'k'}, seen),
        code: 'c',
        redirectUri: 'https://a.test/kakao_login_callback.html',
      );
      expect(token, 'k');
      expect(seen.single.method, 'POST');
      expect(seen.single.path, '/auth/social/kakao/code');
      expect(seen.single.data, <String, Object?>{
        'code': 'c',
        'redirect_uri': 'https://a.test/kakao_login_callback.html',
      });
    });

    test('access_token 이 없으면 던진다', () async {
      for (final Object? body in <Object?>[
        <String, Object?>{},
        <String, Object?>{'access_token': ''},
        <String, Object?>{'access_token': 1},
      ]) {
        await expectLater(
          exchangeKakaoCode(
            dioAnswering(body, <RequestOptions>[]),
            code: 'c',
            redirectUri: 'r',
          ),
          throwsA(isA<FormatException>()),
          reason: '$body',
        );
      }
    });
  });

  test('목업 설정은 키가 없어도 두 provider 를 고정 토큰으로 연다', () async {
    final MemberSocialLogin social = MemberSocialLogin(
      mock: true,
      service: SocialLoginService(
        config: const SocialLoginConfig(),
        platform: SocialLoginPlatform.web,
        exchangeKakaoCode: (_, _) async => 'x',
      ),
    );
    expect(social.anyEnabled, isTrue);
    expect(social.isEnabled(SocialLoginProvider.kakao), isTrue);
    expect(social.usesGoogleWebButton, isFalse);
    expect(social.waitsInPopup(SocialLoginProvider.kakao), isFalse);
    final SocialSignInResult r = await social.signIn(
      SocialLoginProvider.google,
    );
    expect((r as SocialSignInSuccess).token, 'demo-google-token');
  });

  test('AppConfig 는 빌드 변수가 없으면 빈 소셜 설정이다', () {
    expect(AppConfig.fromEnvironment().socialLogin, const SocialLoginConfig());
  });
}

/// 트레이너 웹 카카오·구글 실연동 로그인(#330).
///
/// 브라우저 팝업·구글 버튼은 가짜 경계로 바꿔 끼우고, 화면이 받은 provider 토큰을
/// 세션(`/auth/social/{provider}`)으로 넘기는지, 키가 없는 provider 는 꺼 두는지,
/// 취소는 조용히 넘기고 실패·팝업 차단은 알리는지를 본다. 트레이너 웹은 웹 전용이라
/// 실행 환경은 웹으로 고정한다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_social_login/oncare_social_login.dart';
import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';
import 'package:oncare_trainer/features/auth/presentation/trainer_social_login.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppSocialLoginButton;

import '../../helpers/fake_social_login.dart';
import '../../helpers/pump_app.dart';

const SocialLoginConfig _webKeys = SocialLoginConfig(
  kakaoLoginRestApiKey: kTestKakaoKey,
  googleWebClientId: kTestGoogleWebClientId,
);

const Key _kakao = ValueKey<String>('trainer-login-kakao');
const Key _google = ValueKey<String>('trainer-login-google');
const Key _soon = ValueKey<String>('trainer-login-social-soon');

/// 소셜 로그인 호출을 기록하는 저장소. [fail] 이면 서버가 거절한 것처럼 던진다.
class _SocialRecordingRepository implements TrainerAuthRepository {
  _SocialRecordingRepository({this.fail = false});

  final bool fail;
  final List<({String provider, String token})> calls =
      <({String provider, String token})>[];

  static const TrainerAuthTokens _tokens = TrainerAuthTokens(
    access: 'a',
    refresh: 'r',
  );

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async {
    calls.add((provider: provider, token: token));
    if (fail) throw const AuthException(AuthFailure.invalidCredentials);
    return _tokens;
  }

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String emailCode,
    String phone = '',
    List<String>? consents,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async => _tokens;

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async =>
      const TrainerProfile(
        name: '트레이너',
        email: 'trainer@oncare.com',
        phone: '',
        specialty: '',
        careerYears: null,
        intro: '',
        certifications: <String>[],
        gym: TrainerGym(name: '', address: '', hours: '', phone: ''),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness(this.tester, this.container, this.repo, this.exchanges);

  final WidgetTester tester;
  final ProviderContainer container;
  final _SocialRecordingRepository repo;
  final List<(String, String)> exchanges;

  SessionStatus get status => container.read(sessionControllerProvider).status;

  AppLocalizations get l =>
      AppLocalizations.of(tester.element(find.byType(TrainerSignInPage)));

  bool enabled(Key key) =>
      tester.widget<AppSocialLoginButton>(find.byKey(key)).onPressed != null;

  Future<void> tap(Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await settle(tester);
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  SocialLoginConfig social = _webKeys,
  FakeGoogleGateway? google,
  FakeKakaoPopup? popup,
  bool fail = false,
}) async {
  final _SocialRecordingRepository repo = _SocialRecordingRepository(
    fail: fail,
  );
  final List<(String, String)> exchanges = <(String, String)>[];
  final FakeGoogleGateway googleGateway = google ?? FakeGoogleGateway();
  final FakeKakaoPopup kakaoPopup = popup ?? FakeKakaoPopup();
  addTearDown(googleGateway.dispose);
  addTearDown(kakaoPopup.dispose);
  final GoRouter router = GoRouter(
    initialLocation: '/login',
    routes: <RouteBase>[
      GoRoute(path: '/login', builder: (_, _) => const TrainerSignInPage()),
      GoRoute(
        path: '/dashboard',
        builder: (_, _) => const Scaffold(body: Text('로그인 완료')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final ProviderContainer container = await pumpTrainerApp(
    tester,
    seed: false,
    extraOverrides: <Override>[
      trainerAuthRepositoryProvider.overrideWithValue(repo),
      appRouterProvider.overrideWithValue(router),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'https://api.test/v1',
          useMockApi: false,
          socialLogin: social,
        ),
      ),
      socialLoginServiceProvider.overrideWithValue(
        SocialLoginService(
          config: social,
          platform: SocialLoginPlatform.web,
          exchangeKakaoCode: (code, redirectUri) async {
            exchanges.add((code, redirectUri));
            return 'exchanged-kakao';
          },
          kakaoGateway: FakeKakaoGateway(),
          googleGateway: googleGateway,
          kakaoPopup: kakaoPopup,
        ),
      ),
    ],
  );
  container.read(sessionControllerProvider);
  await settle(tester);
  return _Harness(tester, container, repo, exchanges);
}

void main() {
  testWidgets('카카오 — 팝업을 기다리는 동안 화면을 막지 않고, 코드를 서버에서 바꿔 로그인한다', (tester) async {
    final FakeKakaoPopup popup = FakeKakaoPopup();
    final _Harness h = await _pump(tester, popup: popup);

    expect(h.enabled(_kakao), isTrue);
    expect(find.byKey(_soon), findsNothing);
    await h.tap(_kakao);

    final Uri opened = popup.opened.single;
    expect(opened.host, 'kauth.kakao.com');
    expect(opened.queryParameters['client_id'], kTestKakaoKey);
    expect(
      opened.queryParameters['redirect_uri'],
      'https://app.test/trainer/kakao_login_callback.html',
    );
    expect(h.repo.calls, isEmpty);
    // 기다리는 동안에도 다시 누를 수 있다.
    expect(h.enabled(_kakao), isTrue);

    popup.approve('auth-code');
    await settle(tester);

    expect(h.exchanges.single, (
      'auth-code',
      'https://app.test/trainer/kakao_login_callback.html',
    ));
    expect(h.repo.calls.single, (provider: 'kakao', token: 'exchanged-kakao'));
    expect(h.status, SessionStatus.authenticated);
    expect(find.text('로그인 완료'), findsOneWidget);
  });

  testWidgets('카카오 — 동의 화면에서 취소하면 아무 안내 없이 머문다', (tester) async {
    final FakeKakaoPopup popup = FakeKakaoPopup();
    final _Harness h = await _pump(tester, popup: popup);

    await h.tap(_kakao);
    popup.callbacks.add(
      '{"type":"$kKakaoLoginChannel",'
      '"state":"${popup.opened.last.queryParameters['state']}",'
      '"error":"access_denied"}',
    );
    await settle(tester);

    expect(h.exchanges, isEmpty);
    expect(h.repo.calls, isEmpty);
    expect(find.text(h.l.authSocialSignInFailed), findsNothing);
    expect(find.byType(TrainerSignInPage), findsOneWidget);
  });

  testWidgets('카카오 — 팝업이 막히면 허용하라고 알린다', (tester) async {
    final _Harness h = await _pump(tester, popup: FakeKakaoPopup(allow: false));

    await h.tap(_kakao);

    expect(find.text(h.l.authSocialPopupBlocked), findsOneWidget);
    expect(h.repo.calls, isEmpty);
  });

  testWidgets('구글 — 구글 버튼이 준 ID 토큰으로 로그인한다', (tester) async {
    final FakeGoogleGateway google = FakeGoogleGateway();
    final _Harness h = await _pump(tester, google: google);

    // 테스트(웹 아님)에서는 구글 버튼 대신 꺼진 앱 버튼이 자리를 지킨다.
    expect(find.byKey(_google), findsOneWidget);
    expect(h.enabled(_google), isFalse);

    google.webEvents.add('gis-id-token');
    await settle(tester);

    expect(h.repo.calls.single, (provider: 'google', token: 'gis-id-token'));
    expect(h.status, SessionStatus.authenticated);
  });

  testWidgets('구글 — 버튼에서 창을 닫은 것은 조용히 넘긴다', (tester) async {
    final FakeGoogleGateway google = FakeGoogleGateway();
    final _Harness h = await _pump(tester, google: google);

    google.webEvents.addError(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    await settle(tester);

    expect(h.repo.calls, isEmpty);
    expect(find.text(h.l.authSocialSignInFailed), findsNothing);
  });

  testWidgets('서버가 토큰을 거절하면 실패 안내, 로그인하지 않는다', (tester) async {
    final FakeGoogleGateway google = FakeGoogleGateway();
    final _Harness h = await _pump(tester, google: google, fail: true);

    google.webEvents.add('gis-id-token');
    await settle(tester);

    expect(h.repo.calls, hasLength(1));
    expect(h.status, isNot(SessionStatus.authenticated));
    expect(find.text(h.l.authSocialSignInFailed), findsOneWidget);
    expect(find.byType(TrainerSignInPage), findsOneWidget);
  });

  testWidgets('키가 있는 provider 만 켜고, 하나라도 있으면 준비 중 안내는 없다', (tester) async {
    final _Harness h = await _pump(
      tester,
      social: const SocialLoginConfig(kakaoLoginRestApiKey: kTestKakaoKey),
    );

    expect(h.enabled(_kakao), isTrue);
    expect(h.enabled(_google), isFalse);
    expect(find.byKey(_soon), findsNothing);
  });

  testWidgets('키가 하나도 없으면 두 버튼을 끄고 준비 중 안내를 보인다', (tester) async {
    final _Harness h = await _pump(tester, social: const SocialLoginConfig());

    expect(h.enabled(_kakao), isFalse);
    expect(h.enabled(_google), isFalse);
    expect(find.byKey(_soon), findsOneWidget);
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
        redirectUri: 'https://a.test/trainer/kakao_login_callback.html',
      );
      expect(token, 'k');
      expect(seen.single.method, 'POST');
      expect(seen.single.path, '/auth/social/kakao/code');
      expect(seen.single.data, <String, Object?>{
        'code': 'c',
        'redirect_uri': 'https://a.test/trainer/kakao_login_callback.html',
      });
    });

    test('access_token 이 없으면 던진다', () async {
      for (final Object? body in <Object?>[
        <String, Object?>{},
        <String, Object?>{'access_token': ''},
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
    final TrainerSocialLogin social = TrainerSocialLogin(
      mock: true,
      service: SocialLoginService(
        config: const SocialLoginConfig(),
        platform: SocialLoginPlatform.web,
        exchangeKakaoCode: (_, _) async => 'x',
      ),
    );
    expect(social.anyEnabled, isTrue);
    expect(social.usesGoogleWebButton, isFalse);
    expect(social.waitsInPopup(SocialLoginProvider.kakao), isFalse);
    final SocialSignInResult r = await social.signIn(SocialLoginProvider.kakao);
    expect((r as SocialSignInSuccess).token, 'demo-kakao-token');
  });

  test('AppConfig 는 빌드 변수가 없으면 빈 소셜 설정이고, 목업이면 목업 로그인이다', () {
    final AppConfig config = AppConfig.fromEnvironment();
    expect(config.socialLogin, const SocialLoginConfig());
    expect(config.usesMockSocialLogin, config.useMockApi);
  });
}

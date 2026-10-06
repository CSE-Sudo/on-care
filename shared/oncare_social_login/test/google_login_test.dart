import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_social_login/oncare_social_login.dart';
import 'package:oncare_social_login/src/google_login.dart';

import 'fakes.dart';

const String _webId = '123-web.apps.googleusercontent.com';
const String _iosId = '123-ios.apps.googleusercontent.com';
const SocialLoginConfig _config = SocialLoginConfig(
  googleWebClientId: _webId,
  googleIosClientId: _iosId,
);

void main() {
  late FakeGoogleGateway fake;

  GoogleLogin login(SocialLoginPlatform platform, [SocialLoginConfig? c]) =>
      GoogleLogin(config: c ?? _config, platform: platform, gateway: fake);

  setUp(() => fake = FakeGoogleGateway());
  tearDown(() => fake.dispose());

  group('플랫폼별 초기화 값', () {
    test('Android — 웹 client_id 를 serverClientId 로', () async {
      await login(SocialLoginPlatform.android).ensureInitialized();
      expect(fake.initCalls.single, (null, _webId));
    });

    test('iOS — iOS client_id + 웹 serverClientId', () async {
      await login(SocialLoginPlatform.ios).ensureInitialized();
      expect(fake.initCalls.single, (_iosId, _webId));
    });

    test('웹 — 웹 client_id 만', () async {
      await login(SocialLoginPlatform.web).ensureInitialized();
      expect(fake.initCalls.single, (_webId, null));
    });

    test('설정이 없으면 초기화하지 않는다', () async {
      await login(
        SocialLoginPlatform.android,
        const SocialLoginConfig(),
      ).ensureInitialized();
      expect(fake.initCalls, isEmpty);
    });
  });

  group('모바일 signIn', () {
    test('ID 토큰을 돌려준다', () async {
      final SocialSignInResult r = await login(
        SocialLoginPlatform.android,
      ).signIn();
      expect((r as SocialSignInSuccess).token, 'google-id-token');
      expect(r.provider, SocialLoginProvider.google);
    });

    test('창을 닫으면 취소', () async {
      fake.authError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      expect(
        await login(SocialLoginPlatform.ios).signIn(),
        isA<SocialSignInCancelled>(),
      );
      fake.authError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.interrupted,
      );
      expect(
        await login(SocialLoginPlatform.ios).signIn(),
        isA<SocialSignInCancelled>(),
      );
    });

    test('설정 오류는 providerError', () async {
      fake.authError = const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
      );
      final SocialSignInResult r = await login(
        SocialLoginPlatform.android,
      ).signIn();
      expect(
        (r as SocialSignInFailure).reason,
        SocialSignInFailureReason.providerError,
      );
    });

    test('ID 토큰이 없으면 실패', () async {
      fake.idToken = null;
      expect(
        await login(SocialLoginPlatform.android).signIn(),
        isA<SocialSignInFailure>(),
      );
    });

    test('초기화 실패는 providerError', () async {
      fake.initError = StateError('init');
      expect(
        await login(SocialLoginPlatform.android).signIn(),
        isA<SocialSignInFailure>(),
      );
    });

    test('웹에서는 버튼을 써야 한다', () async {
      expect(
        await login(SocialLoginPlatform.web).signIn(),
        isA<SocialSignInFailure>(),
      );
    });

    test('설정이 없으면 notConfigured', () async {
      final SocialSignInResult r = await login(
        SocialLoginPlatform.ios,
        const SocialLoginConfig(googleWebClientId: _webId),
      ).signIn();
      expect(
        (r as SocialSignInFailure).reason,
        SocialSignInFailureReason.notConfigured,
      );
    });
  });

  group('웹 버튼 결과', () {
    test('로그인·취소·오류를 결과로 바꾼다', () async {
      final List<SocialSignInResult> results = <SocialSignInResult>[];
      final sub = login(
        SocialLoginPlatform.web,
      ).webResults().listen(results.add);
      await pumpEventQueue();
      fake.events
        ..add('id-1')
        ..addError(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        )
        ..addError(StateError('boom'))
        ..add(null);
      await pumpEventQueue();
      await sub.cancel();

      expect(results, hasLength(4));
      expect((results[0] as SocialSignInSuccess).token, 'id-1');
      expect(results[1], isA<SocialSignInCancelled>());
      expect(results[2], isA<SocialSignInFailure>());
      expect(results[3], isA<SocialSignInFailure>());
      expect(fake.events.hasListener, isFalse);
    });

    test('초기화 실패는 실패 결과 하나', () async {
      fake.initError = StateError('init');
      final List<SocialSignInResult> results = <SocialSignInResult>[];
      final sub = login(
        SocialLoginPlatform.web,
      ).webResults().listen(results.add);
      await pumpEventQueue();
      await sub.cancel();
      expect(results.single, isA<SocialSignInFailure>());
    });

    test('웹이 아니면 빈 스트림', () async {
      expect(
        await login(SocialLoginPlatform.android).webResults().isEmpty,
        isTrue,
      );
    });
  });
}

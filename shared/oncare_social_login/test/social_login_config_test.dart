import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_social_login/oncare_social_login.dart';

const String _kakaoKey = '0123456789abcdef0123456789abcdef';
const String _webId = '123-web.apps.googleusercontent.com';
const String _iosId = '123-ios.apps.googleusercontent.com';

void main() {
  group('SocialLoginConfig 형식', () {
    test('카카오 앱 키는 영숫자 16~64자만 받는다', () {
      expect(SocialLoginConfig.isKakaoAppKey(_kakaoKey), isTrue);
      expect(SocialLoginConfig.isKakaoAppKey(''), isFalse);
      expect(SocialLoginConfig.isKakaoAppKey('short'), isFalse);
      expect(SocialLoginConfig.isKakaoAppKey('$_kakaoKey&x=1'), isFalse);
      expect(SocialLoginConfig.isKakaoAppKey('0123456789 abcdef0123'), isFalse);
      expect(SocialLoginConfig.isKakaoAppKey('a' * 65), isFalse);
    });

    test('구글 client_id 는 googleusercontent 접미사가 있어야 한다', () {
      expect(SocialLoginConfig.isGoogleClientId(_webId), isTrue);
      expect(SocialLoginConfig.isGoogleClientId(''), isFalse);
      expect(
        SocialLoginConfig.isGoogleClientId(kGoogleClientIdSuffix),
        isFalse,
      );
      expect(SocialLoginConfig.isGoogleClientId('GOCSPX-secret'), isFalse);
      expect(SocialLoginConfig.isGoogleClientId('a $_webId'), isFalse);
      expect(
        SocialLoginConfig.isGoogleClientId('$_webId.evil.example'),
        isFalse,
      );
    });
  });

  group('SocialLoginConfig.isEnabled', () {
    test('빈 설정은 어디서도 켜지지 않는다', () {
      const SocialLoginConfig config = SocialLoginConfig();
      for (final SocialLoginProvider p in SocialLoginProvider.values) {
        for (final SocialLoginPlatform pl in SocialLoginPlatform.values) {
          expect(config.isEnabled(p, pl), isFalse, reason: '$p $pl');
        }
      }
    });

    test('카카오 — 웹은 REST 키, 모바일은 네이티브 키', () {
      const SocialLoginConfig native = SocialLoginConfig(
        kakaoNativeAppKey: _kakaoKey,
      );
      const SocialLoginConfig rest = SocialLoginConfig(
        kakaoLoginRestApiKey: _kakaoKey,
      );
      const SocialLoginProvider k = SocialLoginProvider.kakao;
      expect(native.isEnabled(k, SocialLoginPlatform.android), isTrue);
      expect(native.isEnabled(k, SocialLoginPlatform.ios), isTrue);
      expect(native.isEnabled(k, SocialLoginPlatform.web), isFalse);
      expect(rest.isEnabled(k, SocialLoginPlatform.web), isTrue);
      expect(rest.isEnabled(k, SocialLoginPlatform.android), isFalse);
    });

    test('구글 — iOS 는 iOS·웹 client_id 둘 다 필요하다', () {
      const SocialLoginProvider g = SocialLoginProvider.google;
      const SocialLoginConfig webOnly = SocialLoginConfig(
        googleWebClientId: _webId,
      );
      const SocialLoginConfig both = SocialLoginConfig(
        googleWebClientId: _webId,
        googleIosClientId: _iosId,
      );
      const SocialLoginConfig iosOnly = SocialLoginConfig(
        googleIosClientId: _iosId,
      );
      expect(webOnly.isEnabled(g, SocialLoginPlatform.web), isTrue);
      expect(webOnly.isEnabled(g, SocialLoginPlatform.android), isTrue);
      expect(webOnly.isEnabled(g, SocialLoginPlatform.ios), isFalse);
      expect(both.isEnabled(g, SocialLoginPlatform.ios), isTrue);
      expect(iosOnly.isEnabled(g, SocialLoginPlatform.ios), isFalse);
      expect(both.isEnabled(g, SocialLoginPlatform.other), isFalse);
    });

    test('형식이 틀린 값은 꺼진 것으로 본다', () {
      const SocialLoginConfig config = SocialLoginConfig(
        kakaoNativeAppKey: 'kakao-key',
        googleWebClientId: 'not-a-client-id',
      );
      expect(
        config.isEnabled(
          SocialLoginProvider.kakao,
          SocialLoginPlatform.android,
        ),
        isFalse,
      );
      expect(
        config.isEnabled(SocialLoginProvider.google, SocialLoginPlatform.web),
        isFalse,
      );
    });
  });

  test('빌드 변수가 없으면 빈 설정이다', () {
    expect(SocialLoginConfig.fromEnvironment(), const SocialLoginConfig());
  });

  test('값 비교', () {
    expect(
      const SocialLoginConfig(googleWebClientId: _webId),
      const SocialLoginConfig(googleWebClientId: _webId),
    );
    expect(
      const SocialLoginConfig(googleWebClientId: _webId).hashCode,
      const SocialLoginConfig(googleWebClientId: _webId).hashCode,
    );
    expect(
      const SocialLoginConfig(googleWebClientId: _webId),
      isNot(const SocialLoginConfig()),
    );
  });

  test('provider id 는 서버 경로 이름이다', () {
    expect(SocialLoginProvider.kakao.id, 'kakao');
    expect(SocialLoginProvider.google.id, 'google');
  });

  test('결과 문자열에 토큰이 찍히지 않는다', () {
    const SocialSignInSuccess success = SocialSignInSuccess(
      SocialLoginProvider.google,
      'secret-id-token',
    );
    expect(success.toString(), isNot(contains('secret-id-token')));
    expect(
      const SocialSignInFailure(
        SocialSignInFailureReason.popupBlocked,
        'detail',
      ).toString(),
      'SocialSignInFailure(popupBlocked)',
    );
    expect(const SocialSignInCancelled().toString(), 'SocialSignInCancelled()');
  });
}

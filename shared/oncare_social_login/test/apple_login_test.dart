import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_social_login/oncare_social_login.dart';
import 'package:oncare_social_login/src/apple_login.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'fakes.dart';

void main() {
  late FakeAppleGateway gateway;
  AppleLogin login([SocialLoginPlatform p = SocialLoginPlatform.ios]) =>
      AppleLogin(platform: p, gateway: gateway);

  setUp(() => gateway = FakeAppleGateway());

  test('identity_token·authorization_code·이름을 넘긴다', () async {
    gateway.credential = (
      identityToken: 'jwt',
      authorizationCode: 'code-1',
      givenName: 'Ada',
      familyName: 'Lovelace',
    );
    final SocialSignInSuccess ok =
        await login().signIn() as SocialSignInSuccess;
    expect(ok.provider, SocialLoginProvider.apple);
    expect(ok.token, 'jwt');
    expect(ok.authorizationCode, 'code-1');
    expect(ok.name, 'Ada Lovelace');
    // 토큰·코드·이름은 문자열로 찍히지 않는다.
    expect(ok.toString(), 'SocialSignInSuccess(apple)');
  });

  test('두 번째 로그인부터는 이름이 없다 — name 은 null', () async {
    final SocialSignInSuccess ok =
        await login().signIn() as SocialSignInSuccess;
    expect(ok.name, isNull);
  });

  test('identity_token 이 없으면 실패', () async {
    gateway.credential = (
      identityToken: null,
      authorizationCode: 'code',
      givenName: null,
      familyName: null,
    );
    final SocialSignInResult r = await login().signIn();
    expect(
      (r as SocialSignInFailure).reason,
      SocialSignInFailureReason.providerError,
    );
  });

  test('사용자가 창을 닫으면 취소', () async {
    gateway.error = const SignInWithAppleAuthorizationException(
      code: AuthorizationErrorCode.canceled,
      message: 'canceled',
    );
    expect(await login().signIn(), isA<SocialSignInCancelled>());
  });

  test('그 밖의 오류는 providerError', () async {
    for (final Object e in <Object>[
      const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.failed,
        message: 'failed',
      ),
      PlatformException(code: 'x'),
      StateError('boom'),
    ]) {
      gateway.error = e;
      final SocialSignInResult r = await login().signIn();
      expect(
        (r as SocialSignInFailure).reason,
        SocialSignInFailureReason.providerError,
        reason: '$e',
      );
    }
  });

  test('iOS 가 아니면 창을 띄우지 않는다', () async {
    for (final SocialLoginPlatform p in <SocialLoginPlatform>[
      SocialLoginPlatform.web,
      SocialLoginPlatform.android,
      SocialLoginPlatform.other,
    ]) {
      expect(await login(p).signIn(), isA<SocialSignInFailure>());
    }
    expect(gateway.calls, 0);
  });

  group('appleDisplayName', () {
    test('한글은 성+이름을 붙여 쓴다', () {
      expect(appleDisplayName('수빈', '김'), '김수빈');
    });
    test('로마자는 이름 성 순서로 띄어 쓴다', () {
      expect(appleDisplayName('Ada', 'Lovelace'), 'Ada Lovelace');
    });
    test('한쪽만 있으면 그대로, 둘 다 비면 null', () {
      expect(appleDisplayName(' Ada ', null), 'Ada');
      expect(appleDisplayName(null, '김'), '김');
      expect(appleDisplayName('  ', ''), isNull);
      expect(appleDisplayName(null, null), isNull);
    });
  });
}

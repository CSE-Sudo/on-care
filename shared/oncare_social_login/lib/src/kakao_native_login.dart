import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

import 'package:oncare_social_login/src/social_login_config.dart';
import 'package:oncare_social_login/src/social_sign_in_result.dart';

/// 카카오 SDK 호출만 모은 경계 — 테스트는 이걸 바꿔 끼운다.
abstract interface class KakaoNativeGateway {
  Future<void> init(String nativeAppKey);
  Future<bool> isKakaoTalkInstalled();

  /// 카카오톡 앱으로 로그인하고 access_token 을 돌려준다.
  Future<String> loginWithKakaoTalk();

  /// 카카오계정(브라우저)으로 로그인하고 access_token 을 돌려준다.
  Future<String> loginWithKakaoAccount();

  /// SDK 가 기기에 저장한 카카오 토큰을 지운다.
  Future<void> clearToken();
}

/// 실제 카카오 Flutter SDK(`kakao_flutter_sdk_user`).
class KakaoSdkGateway implements KakaoNativeGateway {
  const KakaoSdkGateway();

  @override
  Future<void> init(String nativeAppKey) =>
      kakao.KakaoSdk.init(nativeAppKey: nativeAppKey);

  @override
  Future<bool> isKakaoTalkInstalled() => kakao.isKakaoTalkInstalled();

  @override
  Future<String> loginWithKakaoTalk() async =>
      (await kakao.UserApi.instance.loginWithKakaoTalk()).accessToken;

  @override
  Future<String> loginWithKakaoAccount() async =>
      (await kakao.UserApi.instance.loginWithKakaoAccount()).accessToken;

  @override
  Future<void> clearToken() =>
      kakao.TokenManagerProvider.instance.manager.clear();
}

/// 사용자가 카카오 로그인을 스스로 그만뒀는가(오류 안내를 띄우지 않는다).
bool isKakaoCancellation(Object error) => switch (error) {
  kakao.KakaoClientException(reason: kakao.ClientErrorCause.cancelled) => true,
  kakao.KakaoAuthException(error: kakao.AuthErrorCause.accessDenied) => true,
  // 카카오톡 앱에서 '취소'를 누르면 플랫폼 채널이 CANCELED 로 끝난다.
  PlatformException(code: 'CANCELED') => true,
  _ => false,
};

/// 모바일 카카오 로그인(Android·iOS, #330).
///
/// 카카오톡이 깔려 있으면 카카오톡으로, 실패하면(로그인 안 된 카카오톡 등) 카카오계정
/// 화면으로 넘어간다. 사용자가 카카오톡에서 취소했으면 계정 화면을 다시 띄우지 않는다.
/// 받은 access_token 은 서버 로그인에 한 번 쓰고 끝이라, SDK 가 기기에 남긴 토큰은
/// 바로 지운다 — 앱은 카카오 API 를 직접 부르지 않는다.
class KakaoNativeLogin {
  KakaoNativeLogin({
    required this.nativeAppKey,
    this.gateway = const KakaoSdkGateway(),
  });

  final String nativeAppKey;
  final KakaoNativeGateway gateway;

  Future<void>? _init;

  Future<SocialSignInResult> signIn() async {
    if (!SocialLoginConfig.isKakaoAppKey(nativeAppKey)) {
      return const SocialSignInFailure(SocialSignInFailureReason.notConfigured);
    }
    try {
      await (_init ??= gateway.init(nativeAppKey));
    } on Object catch (e) {
      _init = null;
      return SocialSignInFailure(SocialSignInFailureReason.providerError, e);
    }
    try {
      final String token = await _login();
      return token.isEmpty
          ? const SocialSignInFailure(SocialSignInFailureReason.providerError)
          : SocialSignInSuccess(SocialLoginProvider.kakao, token);
    } on Object catch (e) {
      return isKakaoCancellation(e)
          ? const SocialSignInCancelled()
          : SocialSignInFailure(SocialSignInFailureReason.providerError, e);
    } finally {
      await _clearQuietly();
    }
  }

  Future<String> _login() async {
    if (await gateway.isKakaoTalkInstalled()) {
      try {
        return await gateway.loginWithKakaoTalk();
      } on Object catch (e) {
        if (isKakaoCancellation(e)) rethrow;
        // 카카오톡에 로그인돼 있지 않거나 연결이 안 된 경우 — 계정 화면으로 넘어간다.
      }
    }
    return gateway.loginWithKakaoAccount();
  }

  Future<void> _clearQuietly() async {
    try {
      await gateway.clearToken();
    } on Object {
      // 지우기 실패는 로그인 결과를 바꾸지 않는다(다음 로그인 때 덮어쓴다).
    }
  }
}

import 'package:flutter/widgets.dart';

import 'package:oncare_social_login/src/google_button_stub.dart'
    if (dart.library.js_interop) 'package:oncare_social_login/src/google_button_web.dart';
import 'package:oncare_social_login/src/google_login.dart';
import 'package:oncare_social_login/src/kakao_native_login.dart';
import 'package:oncare_social_login/src/kakao_popup_stub.dart'
    if (dart.library.js_interop) 'package:oncare_social_login/src/kakao_popup_web.dart';
import 'package:oncare_social_login/src/kakao_web_login.dart';
import 'package:oncare_social_login/src/social_login_config.dart';
import 'package:oncare_social_login/src/social_sign_in_result.dart';

/// 화면이 쓰는 소셜 로그인 진입점(#330) — 회원 앱·트레이너 웹 공용.
///
/// | | 카카오 | 구글 |
/// | --- | --- | --- |
/// | Android·iOS | 카카오 SDK(카카오톡 → 카카오계정) | `google_sign_in` 로그인 창 |
/// | 웹 | 인가 코드 팝업 + 서버 교환 | 구글이 그리는 버튼(GIS) |
///
/// 결과는 언제나 [SocialSignInResult] 다. 받은 토큰은 화면이 그대로
/// `POST /auth/social/{provider}` 에 보낸다.
class SocialLoginService {
  SocialLoginService({
    required this.config,
    required KakaoCodeExchange exchangeKakaoCode,
    SocialLoginPlatform? platform,
    KakaoNativeGateway? kakaoGateway,
    KakaoPopupPort? kakaoPopup,
    GoogleSignInGateway? googleGateway,
  }) : platform = platform ?? SocialLoginPlatform.current {
    _kakaoNative = KakaoNativeLogin(
      nativeAppKey: config.kakaoNativeAppKey,
      gateway: kakaoGateway ?? const KakaoSdkGateway(),
    );
    _kakaoWeb = KakaoWebLogin(
      restApiKey: config.kakaoLoginRestApiKey,
      port: kakaoPopup ?? createKakaoPopupPort(),
      exchangeCode: exchangeKakaoCode,
    );
    _google = GoogleLogin(
      config: config,
      platform: this.platform,
      gateway: googleGateway ?? const PluginGoogleSignInGateway(),
    );
  }

  final SocialLoginConfig config;
  final SocialLoginPlatform platform;

  late final KakaoNativeLogin _kakaoNative;
  late final KakaoWebLogin _kakaoWeb;
  late final GoogleLogin _google;

  bool get _isWeb => platform == SocialLoginPlatform.web;

  /// 이 빌드에서 [provider] 버튼을 켤 수 있는가.
  bool isEnabled(SocialLoginProvider provider) =>
      config.isEnabled(provider, platform);

  /// 켤 수 있는 provider 가 하나라도 있는가(없으면 화면이 '준비 중'을 보인다).
  bool get anyEnabled => SocialLoginProvider.values.any(isEnabled);

  /// 구글을 구글이 그리는 버튼으로 받는가(웹).
  bool get usesGoogleWebButton =>
      _isWeb && isEnabled(SocialLoginProvider.google);

  /// 로그인 창을 팝업으로 기다리는가 — 그동안 화면을 막지 않는다(웹 카카오).
  bool waitsInPopup(SocialLoginProvider provider) =>
      _isWeb && provider == SocialLoginProvider.kakao;

  /// [provider] 로그인. 웹 구글은 [googleWebButton]·[googleWebResults] 로 한다.
  ///
  /// [onAuthorized] 는 팝업에서 동의를 마쳐 서버 교환을 시작할 때 부른다(웹 카카오).
  Future<SocialSignInResult> signIn(
    SocialLoginProvider provider, {
    VoidCallback? onAuthorized,
  }) async {
    if (!isEnabled(provider)) {
      return const SocialSignInFailure(SocialSignInFailureReason.notConfigured);
    }
    return switch (provider) {
      SocialLoginProvider.kakao when _isWeb => _kakaoWeb.signIn(
        onAuthorized: onAuthorized,
      ),
      SocialLoginProvider.kakao => _kakaoNative.signIn(),
      SocialLoginProvider.google => _google.signIn(),
    };
  }

  /// 웹 구글 버튼 로그인 결과(웹이 아니거나 꺼져 있으면 빈 스트림).
  Stream<SocialSignInResult> googleWebResults() => _google.webResults();

  /// 웹 구글 버튼. 준비되기 전·실패하면 [placeholder] 를 보인다.
  Widget googleWebButton({required Widget placeholder, required double size}) {
    if (!usesGoogleWebButton) return placeholder;
    return buildGoogleWebButton(
      ready: _google.ensureInitialized(),
      placeholder: placeholder,
      size: size,
    );
  }
}

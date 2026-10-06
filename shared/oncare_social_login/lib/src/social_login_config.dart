import 'package:flutter/foundation.dart';

/// 카카오·구글 로그인이 켜지는 provider(#330). 네이버·애플은 하지 않기로 했다.
enum SocialLoginProvider {
  kakao,
  google;

  /// 서버 경로·요청 본문에 쓰는 이름(`/auth/social/{id}`).
  String get id => name;
}

/// 로그인 방식이 갈리는 실행 환경.
enum SocialLoginPlatform {
  web,
  android,
  ios,

  /// 데스크톱·테스트 호스트 — 소셜 로그인을 열지 않는다.
  other;

  /// 지금 실행 중인 환경.
  static SocialLoginPlatform get current {
    if (kIsWeb) return SocialLoginPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => SocialLoginPlatform.android,
      TargetPlatform.iOS => SocialLoginPlatform.ios,
      _ => SocialLoginPlatform.other,
    };
  }
}

/// 구글 OAuth client_id 의 끝. 웹·Android·iOS 모두 이 꼴이다.
const String kGoogleClientIdSuffix = '.apps.googleusercontent.com';

/// 빌드 변수(`--dart-define`)로 받는 소셜 로그인 설정(#330).
///
/// 값은 모두 **공개 식별자**다(앱 키·client_id). 비밀(카카오 클라이언트 시크릿)은
/// 서버만 가진다. 값이 없거나 형식이 틀린 provider 는 꺼진 채로 두고, 화면은 기존처럼
/// '준비 중' 안내를 보인다 — 잘못된 키로 버튼을 켜 두면 누를 때마다 실패한다.
///
/// | 변수 | 쓰는 곳 |
/// | --- | --- |
/// | `KAKAO_NATIVE_APP_KEY` | Android·iOS 카카오 SDK(리다이렉트 스킴 `kakao<키>`) |
/// | `KAKAO_LOGIN_REST_API_KEY` | 웹 카카오 인가 창의 client_id(서버 교환 키와 같은 값) |
/// | `GOOGLE_WEB_CLIENT_ID` | 웹 GIS 버튼 client_id, Android·iOS 의 `serverClientId` |
/// | `GOOGLE_IOS_CLIENT_ID` | iOS Google Sign-In client_id |
@immutable
class SocialLoginConfig {
  const SocialLoginConfig({
    this.kakaoNativeAppKey = '',
    this.kakaoLoginRestApiKey = '',
    this.googleWebClientId = '',
    this.googleIosClientId = '',
  });

  /// 빌드 변수에서 읽는다. 앞뒤 공백은 지운다.
  factory SocialLoginConfig.fromEnvironment() {
    const String kakaoNative = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
    const String kakaoRest = String.fromEnvironment('KAKAO_LOGIN_REST_API_KEY');
    const String googleWeb = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    const String googleIos = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    return SocialLoginConfig(
      kakaoNativeAppKey: kakaoNative.trim(),
      kakaoLoginRestApiKey: kakaoRest.trim(),
      googleWebClientId: googleWeb.trim(),
      googleIosClientId: googleIos.trim(),
    );
  }

  final String kakaoNativeAppKey;
  final String kakaoLoginRestApiKey;
  final String googleWebClientId;
  final String googleIosClientId;

  /// 카카오 앱 키 형식 — 콘솔이 주는 영숫자 키(보통 32자 16진수).
  ///
  /// 스킴(`kakao<키>`)·주소 쿼리에 그대로 들어가므로 영숫자 밖의 글자는 받지 않는다.
  static bool isKakaoAppKey(String value) =>
      RegExp(r'^[A-Za-z0-9]{16,64}$').hasMatch(value);

  /// 구글 OAuth client_id 형식(`<번호>-<해시>.apps.googleusercontent.com`).
  static bool isGoogleClientId(String value) =>
      value.length > kGoogleClientIdSuffix.length &&
      value.endsWith(kGoogleClientIdSuffix) &&
      !value.contains(RegExp(r'\s'));

  /// [platform] 에서 [provider] 로그인을 켤 만큼 설정이 갖춰졌는가.
  ///
  /// - 카카오: 웹은 REST 키(인가 창 client_id), 모바일은 네이티브 앱 키.
  /// - 구글: 웹·Android 는 웹 client_id(Android 는 `serverClientId` 로 쓴다),
  ///   iOS 는 iOS client_id 와 웹 client_id 둘 다.
  bool isEnabled(SocialLoginProvider provider, SocialLoginPlatform platform) =>
      switch ((provider, platform)) {
        (_, SocialLoginPlatform.other) => false,
        (SocialLoginProvider.kakao, SocialLoginPlatform.web) => isKakaoAppKey(
          kakaoLoginRestApiKey,
        ),
        (SocialLoginProvider.kakao, _) => isKakaoAppKey(kakaoNativeAppKey),
        (SocialLoginProvider.google, SocialLoginPlatform.ios) =>
          isGoogleClientId(googleIosClientId) &&
              isGoogleClientId(googleWebClientId),
        (SocialLoginProvider.google, _) => isGoogleClientId(googleWebClientId),
      };

  @override
  bool operator ==(Object other) =>
      other is SocialLoginConfig &&
      other.kakaoNativeAppKey == kakaoNativeAppKey &&
      other.kakaoLoginRestApiKey == kakaoLoginRestApiKey &&
      other.googleWebClientId == googleWebClientId &&
      other.googleIosClientId == googleIosClientId;

  @override
  int get hashCode => Object.hash(
    kakaoNativeAppKey,
    kakaoLoginRestApiKey,
    googleWebClientId,
    googleIosClientId,
  );
}

import 'package:flutter/foundation.dart';

import 'package:oncare_social_login/src/social_login_config.dart';

/// provider 로그인 한 번의 결과(#330).
///
/// 화면은 세 갈래만 다룬다 — 토큰을 받았으면 서버 로그인, 사용자가 그만뒀으면 조용히
/// 제자리, 실패면 안내. 예외를 화면까지 던지지 않고 여기서 갈래를 정한다.
@immutable
sealed class SocialSignInResult {
  const SocialSignInResult();
}

/// provider 토큰을 받았다 — 서버 `POST /auth/social/{provider}` 에 그대로 보낸다.
///
/// 구글은 ID 토큰, 카카오는 access_token 이다. 웹 카카오는 서버가 인가 코드를
/// 바꿔 준 access_token 이다.
final class SocialSignInSuccess extends SocialSignInResult {
  const SocialSignInSuccess(this.provider, this.token);

  final SocialLoginProvider provider;
  final String token;

  // 토큰은 로그·오류 보고에 찍히지 않게 문자열에 담지 않는다.
  @override
  String toString() => 'SocialSignInSuccess(${provider.id})';
}

/// 사용자가 로그인 창을 닫거나 취소했다. 오류 안내 없이 화면에 머문다.
final class SocialSignInCancelled extends SocialSignInResult {
  const SocialSignInCancelled();

  @override
  String toString() => 'SocialSignInCancelled()';
}

/// 실패 이유. 화면 문구가 갈리는 경우만 나눈다.
enum SocialSignInFailureReason {
  /// 브라우저가 카카오 로그인 팝업을 막았다 — 팝업 허용을 안내한다.
  popupBlocked,

  /// 이 빌드에 그 provider 설정이 없다(버튼이 꺼져 있어야 하는 경우).
  notConfigured,

  /// provider SDK·서버 교환 실패.
  providerError,
}

/// 로그인하지 못했다.
final class SocialSignInFailure extends SocialSignInResult {
  const SocialSignInFailure(this.reason, [this.error]);

  final SocialSignInFailureReason reason;

  /// 원인(진단용). 화면에 그대로 보이지 않는다.
  final Object? error;

  @override
  String toString() => 'SocialSignInFailure(${reason.name})';
}

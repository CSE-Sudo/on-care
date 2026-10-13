import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_social_login/oncare_social_login.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 웹 카카오 인가 코드를 카카오 access_token 으로 바꾼다(`POST /auth/social/kakao/code`).
///
/// 카카오가 교환에 요구하는 REST 키·클라이언트 시크릿은 서버만 쓴다. 회원 앱과 같은
/// 엔드포인트다 — 서버는 앱을 가리지 않고 같은 카카오 앱으로 바꾼다.
Future<String> exchangeKakaoCode(
  Dio dio, {
  required String code,
  required String redirectUri,
}) async {
  final Response<Map<String, Object?>> res = await dio
      .post<Map<String, Object?>>(
        '/auth/social/kakao/code',
        data: <String, Object?>{'code': code, 'redirect_uri': redirectUri},
      );
  final Object? token = res.data?['access_token'];
  if (token is! String || token.isEmpty) {
    throw const FormatException('kakao code exchange: no access_token');
  }
  return token;
}

/// 실제 카카오·구글 연동(#330). 테스트는 가짜 경계를 넣은 것으로 바꿔 끼운다.
final socialLoginServiceProvider = Provider<SocialLoginService>((ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return SocialLoginService(
    config: config.socialLogin,
    exchangeKakaoCode: (code, redirectUri) => exchangeKakaoCode(
      ref.read(dioProvider),
      code: code,
      redirectUri: redirectUri,
    ),
  );
});

/// 트레이너 웹 화면(로그인·탈퇴 본인 확인)이 쓰는 소셜 로그인.
final trainerSocialLoginProvider = Provider<TrainerSocialLogin>(
  (ref) => TrainerSocialLogin(
    mock: ref.watch(appConfigProvider).usesMockSocialLogin,
    service: ref.watch(socialLoginServiceProvider),
  ),
);

/// 목업과 실연동을 한 자리에서 고른다(#330). 회원 앱 `MemberSocialLogin` 과 같은 규칙이다.
///
/// - 목업(데모 빌드): 두 버튼이 켜지고 목업 저장소가 받는 고정 토큰
///   (`demo-<provider>-token`)을 돌려준다.
/// - 실서버 빌드: 빌드 키가 있는 provider 만 켜진다. 하나도 없으면 화면이 '준비 중'
///   안내를 보인다(#2769) — 전에는 실서버에서도 이 버튼이 고정 토큰을 보냈다.
class TrainerSocialLogin {
  const TrainerSocialLogin({required this.mock, required this.service});

  final bool mock;
  final SocialLoginService service;

  bool isEnabled(SocialLoginProvider provider) =>
      mock || service.isEnabled(provider);

  bool get anyEnabled => mock || service.anyEnabled;

  /// 웹 구글은 구글이 그리는 버튼으로 받는다.
  bool get usesGoogleWebButton => !mock && service.usesGoogleWebButton;

  /// 팝업을 기다리는 동안 화면을 막지 않는다(웹 카카오).
  bool waitsInPopup(SocialLoginProvider provider) =>
      !mock && service.waitsInPopup(provider);

  Future<SocialSignInResult> signIn(
    SocialLoginProvider provider, {
    VoidCallback? onAuthorized,
  }) async {
    if (mock) return SocialSignInSuccess(provider, 'demo-${provider.id}-token');
    return service.signIn(provider, onAuthorized: onAuthorized);
  }

  /// 웹 구글 버튼의 로그인 결과(그 밖에는 빈 스트림).
  Stream<SocialSignInResult> googleWebResults() => usesGoogleWebButton
      ? service.googleWebResults()
      : const Stream<SocialSignInResult>.empty();

  /// 구글 버튼 자리. 웹 실연동이면 구글 버튼, 아니면 [appButton] 그대로.
  ///
  /// 구글 버튼은 준비되기 전과 [busy] 동안 꺼진 앱 버튼([disabledAppButton])으로 둔다.
  Widget googleButton({
    required Widget appButton,
    required Widget disabledAppButton,
    required bool busy,
  }) {
    if (!usesGoogleWebButton) return appButton;
    if (busy) return disabledAppButton;
    return service.googleWebButton(
      placeholder: disabledAppButton,
      size: OnCareSize.socialLoginButton,
    );
  }
}

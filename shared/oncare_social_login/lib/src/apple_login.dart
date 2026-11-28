import 'package:oncare_social_login/src/social_login_config.dart';
import 'package:oncare_social_login/src/social_sign_in_result.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// 애플 로그인 창이 돌려준 값 중 서버가 쓰는 것만.
typedef AppleCredential = ({
  String? identityToken,
  String authorizationCode,
  String? givenName,
  String? familyName,
});

/// `sign_in_with_apple` 호출만 모은 경계 — 테스트는 이걸 바꿔 끼운다.
abstract interface class AppleSignInGateway {
  /// 애플 로그인 창을 띄우고 이름·이메일 공유를 묻는다.
  Future<AppleCredential> getCredential();
}

/// 실제 `sign_in_with_apple` 플러그인(iOS AuthenticationServices).
class PluginAppleSignInGateway implements AppleSignInGateway {
  const PluginAppleSignInGateway();

  @override
  Future<AppleCredential> getCredential() async {
    final AuthorizationCredentialAppleID c =
        await SignInWithApple.getAppleIDCredential(
          scopes: const <AppleIDAuthorizationScopes>[
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
    return (
      identityToken: c.identityToken,
      authorizationCode: c.authorizationCode,
      givenName: c.givenName,
      familyName: c.familyName,
    );
  }
}

/// 사용자가 애플 로그인 창을 닫았는가(오류 안내를 띄우지 않는다).
bool isAppleCancellation(Object error) =>
    error is SignInWithAppleAuthorizationException &&
    error.code == AuthorizationErrorCode.canceled;

/// 애플 로그인(#3499) — 회원 iOS 앱에서만 켠다.
///
/// 서버에는 identity_token(JWT)을 보낸다. 서버가 Apple 공개키로 직접 검증한다.
/// 이름은 **첫 로그인 때만** 애플이 앱에 주므로 [SocialSignInSuccess.name] 으로 함께
/// 넘긴다 — 가입 뒤에 이름을 다시 묻지 않는다(App Review Guideline 4.8).
/// `authorizationCode` 는 탈퇴 때 서버가 Apple 토큰을 철회하는 데 쓴다.
class AppleLogin {
  AppleLogin({
    required this.platform,
    this.gateway = const PluginAppleSignInGateway(),
  });

  final SocialLoginPlatform platform;
  final AppleSignInGateway gateway;

  Future<SocialSignInResult> signIn() async {
    if (platform != SocialLoginPlatform.ios) {
      return const SocialSignInFailure(SocialSignInFailureReason.notConfigured);
    }
    try {
      final AppleCredential c = await gateway.getCredential();
      final String token = c.identityToken ?? '';
      if (token.isEmpty) {
        return const SocialSignInFailure(
          SocialSignInFailureReason.providerError,
        );
      }
      return SocialSignInSuccess(
        SocialLoginProvider.apple,
        token,
        name: appleDisplayName(c.givenName, c.familyName),
        authorizationCode: c.authorizationCode,
      );
    } on Object catch (e) {
      return isAppleCancellation(e)
          ? const SocialSignInCancelled()
          : SocialSignInFailure(SocialSignInFailureReason.providerError, e);
    }
  }
}

/// 애플이 준 이름 조각을 한 줄로. 둘 다 비면 `null`.
///
/// 한글 이름(성이 앞, 붙여 씀)과 로마자 이름(이름이 앞, 띄어 씀)을 가른다.
String? appleDisplayName(String? givenName, String? familyName) {
  final String given = (givenName ?? '').trim();
  final String family = (familyName ?? '').trim();
  if (given.isEmpty && family.isEmpty) return null;
  if (given.isEmpty) return family;
  if (family.isEmpty) return given;
  final bool hangul = RegExp(r'[가-힣]').hasMatch('$family$given');
  return hangul ? '$family$given' : '$given $family';
}

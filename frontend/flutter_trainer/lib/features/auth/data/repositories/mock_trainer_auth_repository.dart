import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/features/auth/data/repositories/signup_email_code_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppInputError, AppInputRules;

/// Pure in-memory mock used for the demo bypass and `USE_MOCK_API=true`.
///
/// Accepts any non-empty email/password (mirroring the user app's demo
/// login), issues fake tokens, and returns the fixed [seedTrainerProfile]
/// from [fetchProfile]. No network, no real validation.
class MockTrainerAuthRepository implements TrainerAuthRepository {
  const MockTrainerAuthRepository({this.language = DemoLanguage.ko});

  /// 로그인에 붙일 데모 프로필의 언어 (#2304).
  final DemoLanguage language;

  static const _loginDelay = Duration(milliseconds: 400);

  TrainerAuthTokens _demoTokens(String tag) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return TrainerAuthTokens(
      access: 'demo-trainer-$tag-$stamp',
      refresh: 'demo-trainer-$tag-refresh-$stamp',
    );
  }

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(_loginDelay);
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException(AuthFailure.emptyCredentials);
    }
    return _demoTokens('token');
  }

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String emailCode,
    List<String>? consents,
  }) async {
    await Future<void>.delayed(_loginDelay);
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException(AuthFailure.emptyCredentials);
    }
    // 비밀번호는 서버와 같은 기준으로 본다(#1555) — 데모에서만 가입되는
    // 비밀번호가 있으면 실서버에서 처음 실패를 보게 된다.
    switch (AppInputRules.signUpPassword(password)) {
      case null:
        break;
      case AppInputError.passwordTooLong:
        throw const AuthException(AuthFailure.passwordTooLong);
      default:
        throw const AuthException(AuthFailure.passwordWeak);
    }
    // 이메일 인증 코드(#3038) — 서버와 같은 순서·같은 실패다. 메일이 가지 않는
    // 데모는 정해진 코드 하나만 통과시킨다. 화면은 데모에서 그 코드를 안내한다.
    final String code = emailCode.trim();
    if (code.isEmpty) {
      throw const AuthException(AuthFailure.emailCodeRequired);
    }
    if (code != MockSignupEmailCodeRepository.demoCode) {
      throw const AuthException(AuthFailure.emailCodeInvalid);
    }
    return _demoTokens('signup');
  }

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async {
    await Future<void>.delayed(_loginDelay);
    if (token.isEmpty) {
      throw const AuthException(AuthFailure.noSocialToken);
    }
    return _demoTokens(provider);
  }

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async {
    if (refreshToken.isEmpty) {
      throw const AuthException(AuthFailure.sessionExpired);
    }
    return _demoTokens('token');
  }

  @override
  Future<void> logout(String refreshToken) async {
    // 데모에는 폐기할 서버가 없다. 로그아웃은 로컬 자격을 지우는 것으로 끝난다.
  }

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async {
    if (accessToken.isEmpty) {
      throw const AuthException(AuthFailure.sessionExpired);
    }
    return seedTrainerProfileFor(language);
  }
}

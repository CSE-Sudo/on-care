import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// 로그인·가입 실패의 **원인 코드**. 문구가 아니다.
///
/// 리포지토리에는 컨텍스트가 없어 로케일을 알 수 없다. 여기서 한국어 문장을
/// 들고 있으면 영어 로케일에서 그 문장만 한국어로 남는다. 화면이 코드를 받아
/// 자기 언어의 문구를 붙인다. (#501)
enum AuthFailure {
  invalidCredentials,
  emailTaken,

  /// 서버가 가입 비밀번호를 기준 미달로 거절했다(#1555).
  passwordWeak,

  /// 서버가 가입 비밀번호를 너무 길다고 거절했다 — 64자·UTF-8 72바이트(#1555).
  passwordTooLong,

  /// 이메일 인증 코드가 틀렸거나, 만료됐거나, 이미 쓰였다(400
  /// `invalid_email_code`, #3038). 어느 쪽인지 서버도 밝히지 않는다 — 코드를
  /// 다시 받으면 된다.
  emailCodeInvalid,

  /// 가입 요청에 인증 코드가 없었다(422 `email_code_required`, #3038).
  emailCodeRequired,
  sessionExpired,
  noSocialToken,
  emptyCredentials,
  network,
  emptyResponse,
  notTrainer,
  unknown,
}

/// 로그인·가입이 거부됐을 때 던진다. 사용자에게 보일 문구가 아니라
/// [AuthFailure] 코드를 들고 나가며, 문구는 화면이 [authFailureText] 로 붙인다.
class AuthException implements Exception {
  const AuthException(this.failure, {this.detail});

  /// 무엇이 잘못됐는가. 화면이 이 값으로 문구를 고른다.
  final AuthFailure failure;

  /// 로그·디버깅용 상세(파서 메시지 등). **화면에 그리지 않는다** — 로케일도
  /// 모르고 사용자가 읽을 문장도 아니다. [toString] 에만 실린다.
  final String? detail;

  @override
  String toString() =>
      'AuthException: $failure${detail == null ? '' : ' ($detail)'}';
}

/// Raised when the authenticated account is not a trainer (the backend
/// answers `/trainer/me` with 403). The trainer app and the member app
/// use fully separate accounts, so a member credential must be rejected.
class NotTrainerException extends AuthException {
  const NotTrainerException() : super(AuthFailure.notTrainer);
}

/// Authenticates a trainer against the backend and reads the trainer
/// profile. Two implementations sit behind this contract:
///
///  * [MockTrainerAuthRepository] — demo / `USE_MOCK_API=true`;
///  * `DioTrainerAuthRepository` — the real FastAPI backend.
///
/// The UI depends only on this interface (never on Dio directly).
abstract class TrainerAuthRepository {
  /// Exchanges email/password for tokens (POST /v1/auth/login).
  /// Throws [AuthException] on failure.
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  });

  /// Creates a new trainer account (POST /v1/auth/trainer/register) and
  /// returns tokens. Throws [AuthException] (409 duplicate email, 422
  /// password rejected by the server policy).
  ///
  /// 소속 헬스장은 가입 때 정하지 않는다 — 가입 뒤 헬스장을 찾아 고른다
  /// (#1627). 예전에는 헬스장 초대 코드가 소속을 정했지만 발급 경로가 없었다.
  ///
  /// [consents] 는 가입 화면에서 체크한 동의 항목이다(#2819). 서버가 계정과 한
  /// 트랜잭션으로 남기고, 필수 항목이 빠졌으면 계정을 만들지 않고 422 를 준다.
  /// 넘기지 않으면(null) 칸을 싣지 않는다 — 계정은 동의 기록 없이 만들어지고
  /// 로그인 직후 동의 화면을 거친다.
  ///
  /// [emailCode] 는 `POST /auth/register/email-code`(목적 `trainer_signup`)로
  /// 그 이메일 앞으로 받은 6자리 코드다(#3038). 틀리거나 만료되면
  /// [AuthFailure.emailCodeInvalid], 비었으면 [AuthFailure.emailCodeRequired].
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String emailCode,
    List<String>? consents,
  });

  /// Exchanges a provider (kakao/google) [token] for tokens
  /// (POST /v1/auth/social/{provider}). Throws [AuthException].
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  });

  /// Rotates an expired session (POST /v1/auth/refresh). Throws
  /// [AuthException] when the refresh token is invalid/expired.
  ///
  /// 회전에 쓴 토큰은 서버에서 **그 자리에 폐기된다** — 한 번 쓴 갱신 토큰으로
  /// 다시 회전하면 재사용으로 보고 거부된다(#966). 회전 결과는 반드시 저장해야
  /// 하고, 같은 토큰으로 두 번 부르면 안 된다.
  Future<TrainerAuthTokens> refresh(String refreshToken);

  /// 서버 쪽 세션을 끊는다 (POST /v1/auth/logout) — [refreshToken] 을 폐기해
  /// 더 이상 회전에 쓰이지 못하게 한다.
  ///
  /// 공용 PC 에서 브라우저 저장소가 복사되거나 토큰이 새면, 로컬 저장소를 지우는
  /// 것만으로는 그 세션이 끊기지 않는다 — 갱신 토큰은 만료(기본 30일)까지
  /// 살아 있다(#966).
  ///
  /// 다른 메서드처럼 실패하면 던진다. 다만 **로그아웃은 그 실패로 멈추지 않는다** —
  /// 사용자가 이미 결정한 일이라, 네트워크가 끊겼다고 로그인 화면으로 못 나가면 안 된다.
  /// 그 판단은 호출부(`SessionController.signOut`)가 한곳에서 한다. 서버가 못 받은
  /// 폐기는 그 토큰의 만료까지 남지만, 이 기기의 자격은 어차피 지워진다.
  Future<void> logout(String refreshToken);

  /// Reads the signed-in trainer's profile (GET /v1/trainer/me) using
  /// [accessToken].
  ///
  /// Error contract (kept in sync with the Dio implementation so callers
  /// can catch precisely):
  ///  * 403 → [NotTrainerException] — the account is not a trainer;
  ///  * 401 → `UnauthorizedError` (from `core/errors`), surfaced so
  ///    `SessionController` can attempt a token refresh;
  ///  * transport / empty-body failures → a typed `AppError`
  ///    (`NetworkError` / `ServerError`), NOT [AuthException], so restore
  ///    treats a transient failure as recoverable and keeps the tokens.
  Future<TrainerProfile> fetchProfile(String accessToken);
}

/// 실패 코드 → 현재 로케일의 문구. (#501)
///
/// [AuthException.detail] 은 쓰지 않는다. 지금 그 자리에 들어오는 값은 서버가 준
/// 사유가 아니라 토큰 파싱 실패의 [FormatException] 메시지뿐이라, 그대로 내보내면
/// 로케일과 무관하게 파서 내부 문구가 사용자에게 보인다.
String authFailureText(AppLocalizations l, AuthException e) {
  return switch (e.failure) {
    AuthFailure.invalidCredentials => l.authErrInvalidCredentials,
    AuthFailure.emailTaken => l.authErrEmailTaken,
    AuthFailure.passwordWeak => l.authErrPasswordWeak,
    AuthFailure.passwordTooLong => l.authErrPasswordTooLong,
    AuthFailure.emailCodeInvalid => l.signUpCodeInvalid,
    AuthFailure.emailCodeRequired => l.signUpCodeRequired,
    AuthFailure.sessionExpired => l.authErrSessionExpired,
    AuthFailure.noSocialToken => l.authErrNoSocialToken,
    AuthFailure.emptyCredentials => l.authErrEmptyCredentials,
    AuthFailure.network => l.authErrNetwork,
    AuthFailure.emptyResponse => l.authErrEmptyResponse,
    AuthFailure.notTrainer => l.authErrNotTrainer,
    AuthFailure.unknown => l.authErrGeneric,
  };
}

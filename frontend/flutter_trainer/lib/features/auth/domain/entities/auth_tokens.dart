/// A pair of JWT tokens issued by the backend auth endpoints.
///
/// The access token authorizes API calls; the refresh token mints a new
/// pair when the access token expires (POST /v1/auth/refresh).
class TrainerAuthTokens {
  const TrainerAuthTokens({
    required this.access,
    required this.refresh,
    this.consentRequired = false,
  });

  final String access;
  final String refresh;

  /// 이 계정에 아직 남은 가입 동의가 있는가 — 로그인 응답의
  /// `consent_required`. (#2819)
  ///
  /// 동의 절차가 생기기 전에 가입한 계정, 소셜 첫 로그인, 문서 버전이 올라간
  /// 계정이 참이다. 칸이 없으면(옛 서버) 거짓이다.
  final bool consentRequired;

  /// Parses `{ access_token, refresh_token }` (snake_case, per the
  /// FastAPI `Token` schema). Throws [FormatException] if no access token
  /// is present so callers fail loudly rather than storing an empty token.
  factory TrainerAuthTokens.fromJson(Map<String, Object?> json) {
    final access = (json['access_token'] as String?) ?? '';
    if (access.isEmpty) {
      throw const FormatException('응답에 access_token 이 없습니다.');
    }
    return TrainerAuthTokens(
      access: access,
      refresh: (json['refresh_token'] as String?) ?? '',
      consentRequired: json['consent_required'] == true,
    );
  }
}

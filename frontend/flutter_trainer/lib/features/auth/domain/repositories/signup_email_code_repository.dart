/// 가입 이메일 인증 코드(#3038).
///
/// 가입 전에 그 이메일이 정말 본인 것인지 확인한다. 화면이 코드를 받아 가입
/// 요청의 `email_code` 로 싣는다. 코드는 (소문자 이메일, 목적) 에 묶여 있어
/// 이메일을 고치면 새 코드가 필요하다.
abstract final class SignupEmailCode {
  /// 코드 길이. 숫자만 쓴다.
  static const int length = 6;

  /// 트레이너 가입 코드의 목적 — 회원 가입 코드(`member_signup`)로는 가입되지 않는다.
  static const String purpose = 'trainer_signup';

  static final RegExp _complete = RegExp(r'^\d{6}$');

  /// 가입 요청에 실을 만한 코드인가. 맞는 코드인지는 서버가 판단한다.
  static bool isComplete(String value) => _complete.hasMatch(value.trim());

  /// 코드가 어느 이메일에 묶였는지 비교할 모양 — 앞뒤 공백을 빼고 소문자로.
  static String emailKey(String email) => email.trim().toLowerCase();
}

/// 인증 코드 요청이 막힌 이유. 화면은 이 값으로 자기 로케일의 문구를 고른다.
enum SignupEmailCodeFailure {
  /// 이메일 형식이 틀렸다(422). 화면이 미리 거르므로 드물다.
  invalidEmail,

  /// 너무 자주 요청했다(429).
  tooMany,

  /// 서버가 지금 메일을 보낼 수 없다(503).
  unavailable,

  /// 연결 실패·서버 오류.
  temporary,
}

/// [SignupEmailCodeRepository] 가 던지는 실패.
class SignupEmailCodeError implements Exception {
  const SignupEmailCodeError(this.kind);

  final SignupEmailCodeFailure kind;

  @override
  String toString() => 'SignupEmailCodeError($kind)';
}

/// 코드 요청을 받았다는 응답(202). 가입된 이메일이든 아니든 같은 값이다 —
/// 가입된 주소에는 코드 대신 "이미 계정이 있어요" 메일이 간다. 화면이 둘을
/// 다르게 말하면 아무 이메일이나 넣어 가입 여부를 알 수 있다.
class SignupEmailCodeSent {
  const SignupEmailCodeSent({
    required this.expiresInMinutes,
    required this.resendAfterSeconds,
    this.demoCode,
  });

  /// 코드가 살아 있는 시간(분).
  final int expiresInMinutes;

  /// 다시 받기까지 기다릴 시간(초).
  final int resendAfterSeconds;

  /// 데모 빌드에서만 채운다 — 메일이 가지 않으니 화면이 데모 코드를 안내한다.
  /// 실 서버는 늘 null.
  final String? demoCode;
}

/// `POST /auth/register/email-code` — 가입 전 이메일 인증 코드를 받는다(#3038).
abstract interface class SignupEmailCodeRepository {
  /// [email] 앞으로 트레이너 가입 코드를 보낸다. 실패는 [SignupEmailCodeError].
  Future<SignupEmailCodeSent> request({required String email});
}

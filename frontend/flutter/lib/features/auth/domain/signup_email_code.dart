/// 가입 이메일 인증 코드(#3038).
///
/// 가입하기 전에 그 이메일로 받은 6자리 숫자 코드를 확인한다. 확인 안 된
/// 계정이 아예 생기지 않게 하려는 것이다 — 남의 주소로 계정을 먼저 만들어
/// 두는 일을 막는다. 규약은 `backend/API_CONTRACT.md` 의 가입 절이다.
abstract final class SignupEmailCode {
  /// 코드 길이. 모바일에서 옮겨 치기 쉬운 숫자 여섯 자리다.
  static const int length = 6;

  /// 회원 가입 코드의 용도. 같은 이메일이라도 트레이너 가입 코드와 섞이지 않는다.
  static const String memberPurpose = 'member_signup';

  /// 데모(기기 안 목업)가 받아 주는 코드. 데모는 메일을 보내지 않으므로 화면이
  /// 이 값을 안내한다. 실 서버에는 이런 코드가 없다.
  static const String demoCode = '000000';

  static final RegExp _complete = RegExp(r'^\d{6}$');

  /// 서버에 보낼 만한 코드인가 — 숫자 여섯 자리. 맞는 코드인지는 서버가 본다.
  static bool isComplete(String value) => _complete.hasMatch(value.trim());
}

/// 코드를 보냈다는 응답. 이메일이 이미 가입돼 있어도 같은 응답이다 — 화면도
/// "보냈다" 와 "이미 가입됐다" 를 가르지 않는다.
class SignupEmailCodeSent {
  const SignupEmailCodeSent({
    required this.expiresInMinutes,
    required this.resendAfterSeconds,
  });

  /// 코드가 살아 있는 시간(분).
  final int expiresInMinutes;

  /// 다시 받기까지 기다릴 시간(초).
  final int resendAfterSeconds;
}

/// 코드 요청이 막힌 이유.
enum SignupEmailCodeFailure {
  /// 이메일 형식이 틀렸다(422). 화면이 보내기 전에 거르므로 드물다.
  invalidEmail,

  /// 너무 자주 요청했다(429).
  tooMany,

  /// 서버가 지금 메일을 보낼 수 없다(503).
  unavailable,

  /// 연결 실패·서버 오류.
  temporary,
}

/// [SignupEmailCodeRepository.requestCode] 가 던지는 실패.
class SignupEmailCodeError implements Exception {
  const SignupEmailCodeError(this.kind);

  final SignupEmailCodeFailure kind;

  @override
  String toString() => 'SignupEmailCodeError($kind)';
}

/// 가입 요청이 코드 때문에 거절된 이유.
enum SignupCodeRejection {
  /// 코드를 보내지 않았다 — 422 `email_code_required`.
  required,

  /// 코드가 틀렸거나 만료됐거나 이미 쓰였다 — 400 `invalid_email_code`.
  invalid,
}

/// 가입 응답(상태 코드·본문)이 코드 거절이면 그 이유, 아니면 null.
///
/// 서버는 `detail: {code, message}` 로 준다. 문장은 한국어 하나뿐이라 화면은
/// 코드만 보고 자기 로케일의 문구를 고른다.
SignupCodeRejection? signupCodeRejectionOf(int? status, Object? body) {
  final Object? detail = body is Map ? body['detail'] : null;
  final Object? code = detail is Map ? detail['code'] : null;
  return switch ((status, code)) {
    (400, 'invalid_email_code') => SignupCodeRejection.invalid,
    (422, 'email_code_required') => SignupCodeRejection.required,
    _ => null,
  };
}

/// 가입 이메일 인증 코드 요청(#3038).
abstract interface class SignupEmailCodeRepository {
  /// `POST /auth/register/email-code`. 실패는 [SignupEmailCodeError].
  Future<SignupEmailCodeSent> requestCode({required String email});
}

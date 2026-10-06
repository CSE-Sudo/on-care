/// 소셜 로그인 응답(상태 코드·본문)이 "같은 이메일의 계정이 이미 있다" 인가(#1551).
///
/// provider 가 확인하지 않은 이메일이 기존 계정의 이메일과 같으면 서버는 연결도,
/// 새 계정도 만들지 않고 409 `detail: {code: social_email_in_use, message}` 로 답한다.
/// 문장은 한국어 하나뿐이라 화면은 코드만 보고 자기 로케일의 문구를 고른다.
bool isSocialEmailInUse(int? status, Object? body) {
  final Object? detail = body is Map ? body['detail'] : null;
  final Object? code = detail is Map ? detail['code'] : null;
  return status == 409 && code == 'social_email_in_use';
}

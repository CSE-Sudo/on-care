/// 비밀번호 재설정 코드의 모양(#2824).
///
/// 서버(`backend/app/services/password_reset.py`)·회원 앱과 같은 규칙이다. 메일의
/// 코드를 옮겨 칠 때 대소문자·공백·하이픈을 어떻게 넣든 같은 코드로 읽는다.
abstract final class PasswordResetCode {
  /// 코드에 쓰는 글자. 0/O, 1/I/L 처럼 옮겨 적다 틀리기 쉬운 글자를 뺐다.
  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// 구분자를 뺀 코드 길이.
  static const int length = 16;

  /// 보여 줄 때 몇 글자마다 `-` 를 넣는가.
  static const int group = 4;

  static final RegExp _separators = RegExp(r'[\s\-]');

  /// 사람이 친 값을 비교할 모양으로 — 대문자, 공백·하이픈 제거.
  static String normalize(String value) =>
      value.replaceAll(_separators, '').toUpperCase();

  /// 서버에 보낼 만한 코드인가. 길이와 글자만 본다 — 맞는 코드인지는 서버가
  /// 판단한다.
  static bool isWellFormed(String value) {
    final String code = normalize(value);
    if (code.length != length) return false;
    for (int i = 0; i < code.length; i++) {
      if (!alphabet.contains(code[i])) return false;
    }
    return true;
  }

  /// `XXXX-XXXX-XXXX-XXXX` 모양으로 보여 준다. 모양이 틀리면 정규화한 값 그대로.
  static String format(String value) {
    final String code = normalize(value);
    if (code.length != length) return code;
    return <String>[
      for (int i = 0; i < length; i += group) code.substring(i, i + group),
    ].join('-');
  }
}

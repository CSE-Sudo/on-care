import 'package:flutter/services.dart';

/// 입력 칸 형식 검사의 결과 — 무엇이 잘못됐는가(#1784).
///
/// 문구는 앱마다 로케일 파일에 있으므로 여기서는 종류만 돌려주고, 두 앱이
/// 각자의 문구로 바꿔 칸 아래에 그린다.
enum AppInputError {
  /// 이메일 칸이 비었다.
  emailEmpty,

  /// 이메일 형식이 아니다.
  emailInvalid,

  /// 전화번호가 `000-0000-0000` 형식이 아니다(비어 있는 경우 포함).
  phoneInvalid,

  /// 비밀번호 칸이 비었다.
  passwordEmpty,

  /// 가입 비밀번호 규칙(8자 이상, 영문·숫자 각 1자 이상)에 맞지 않는다.
  passwordWeak,

  /// 비밀번호 확인이 비밀번호와 다르다.
  passwordMismatch,
}

/// 로그인·가입 입력의 형식 규칙(#1784). 두 앱이 같은 정규식을 쓰도록 한곳에 둔다.
///
/// 서버 검증은 따로 다룬다(비밀번호 #1555, 이메일·전화번호 #1780). 여기 규칙은
/// 요청을 보내기 전에 사용자가 바로 고칠 수 있게 알려 주는 용도다.
abstract final class AppInputRules {
  /// 로컬 부분@도메인.최상위 — 흔히 쓰는 주소는 통과시키고 빈칸·골뱅이 누락·
  /// 최상위 도메인 누락 같은 오타를 잡는 정도로만 엄격하다.
  static final RegExp _email = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$',
  );

  /// 휴대전화 표기 3-4-4.
  static final RegExp _phone = RegExp(r'^\d{3}-\d{4}-\d{4}$');

  static final RegExp _letter = RegExp('[A-Za-z]');
  static final RegExp _digit = RegExp(r'\d');

  /// 가입 비밀번호의 최소 길이.
  static const int passwordMinLength = 8;

  /// 전화번호 숫자 개수(3 + 4 + 4).
  static const int phoneDigits = 11;

  /// 이메일 — 앞뒤 공백은 보내기 전에 잘라내므로 잘라낸 값으로 본다.
  static AppInputError? email(String value) {
    final String email = value.trim();
    if (email.isEmpty) return AppInputError.emailEmpty;
    final String local = email.split('@').first;
    // 점으로 시작·끝나거나 점이 이어진 로컬 부분은 정규식으로 적으면 읽기
    // 어려워 따로 본다.
    if (!_email.hasMatch(email) ||
        local.startsWith('.') ||
        local.endsWith('.') ||
        email.contains('..')) {
      return AppInputError.emailInvalid;
    }
    return null;
  }

  /// 전화번호 — 정확히 `000-0000-0000`. [AppPhoneNumberFormatter] 가 하이픈을
  /// 넣어 주므로 숫자 11자리를 채우면 맞는다.
  static AppInputError? phone(String value) =>
      _phone.hasMatch(value.trim()) ? null : AppInputError.phoneInvalid;

  /// 로그인 비밀번호 — 비어 있지만 않으면 된다. 규칙 이전에 만든 계정이
  /// 로그인에서 막히지 않도록 가입 규칙을 적용하지 않는다.
  static AppInputError? signInPassword(String value) =>
      value.isEmpty ? AppInputError.passwordEmpty : null;

  /// 가입 비밀번호 — 8자 이상, 영문과 숫자를 각각 1자 이상.
  static AppInputError? signUpPassword(String value) {
    if (value.isEmpty) return AppInputError.passwordEmpty;
    if (value.length < passwordMinLength ||
        !_letter.hasMatch(value) ||
        !_digit.hasMatch(value)) {
      return AppInputError.passwordWeak;
    }
    return null;
  }

  /// 비밀번호 확인 — 비밀번호와 글자 그대로 같아야 한다.
  static AppInputError? passwordConfirm(String password, String confirm) =>
      password == confirm ? null : AppInputError.passwordMismatch;
}

/// 숫자만 쳐도 `010-1234-5678` 로 하이픈을 넣어 주는 입력 서식(#1784).
///
/// 숫자가 아닌 글자는 버리고 최대 [AppInputRules.phoneDigits] 자리까지만 받는다.
/// 하이픈은 다음 숫자가 들어올 때 붙으므로 지우는 중에 하이픈만 남지 않는다.
class AppPhoneNumberFormatter extends TextInputFormatter {
  const AppPhoneNumberFormatter();

  static final RegExp _nonDigit = RegExp(r'\D');

  /// 숫자열을 3-4-4 로 끊는다. 모자라면 있는 만큼만 끊는다.
  static String format(String digits) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 3 || i == 7) out.write('-');
      out.write(digits[i]);
    }
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(_nonDigit, '');
    int cursorDigits = _digitsBefore(newValue.text, newValue.selection.end);

    // 하이픈 바로 뒤에서 지우기를 누르면 하이픈만 지워지고 숫자는 그대로라,
    // 다시 끊으면 아무 일도 없던 것처럼 보인다. 그 경우 앞 숫자를 함께 지운다.
    final String oldDigits = oldValue.text.replaceAll(_nonDigit, '');
    final bool removedOnlySeparator =
        newValue.text.length < oldValue.text.length &&
        digits == oldDigits &&
        newValue.selection.isCollapsed &&
        cursorDigits > 0;
    if (removedOnlySeparator) {
      digits =
          digits.substring(0, cursorDigits - 1) +
          digits.substring(cursorDigits);
      cursorDigits -= 1;
    }

    if (digits.length > AppInputRules.phoneDigits) {
      digits = digits.substring(0, AppInputRules.phoneDigits);
    }
    if (cursorDigits > digits.length) cursorDigits = digits.length;

    final String text = format(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: _offsetAfterDigits(text, cursorDigits),
      ),
    );
  }

  /// [text] 의 [end] 앞에 있는 숫자 개수. 선택이 없으면 끝으로 본다.
  static int _digitsBefore(String text, int end) {
    final int limit = end < 0 || end > text.length ? text.length : end;
    return text.substring(0, limit).replaceAll(_nonDigit, '').length;
  }

  /// 서식을 입힌 [text] 에서 숫자 [count] 개 바로 뒤 위치.
  static int _offsetAfterDigits(String text, int count) {
    if (count <= 0) return 0;
    int seen = 0;
    for (int i = 0; i < text.length; i++) {
      if (text[i] != '-') seen++;
      if (seen == count) return i + 1;
    }
    return text.length;
  }
}

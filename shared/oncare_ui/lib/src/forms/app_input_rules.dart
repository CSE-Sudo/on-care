import 'package:flutter/services.dart';

/// 입력 칸 형식 검사의 결과 — 무엇이 잘못됐는가(#1784).
///
/// 문구는 앱마다 로케일 파일에 있으므로 여기서는 종류만 돌려주고, 두 앱이
/// 각자의 문구로 바꿔 칸 아래에 그린다.
enum AppInputError {
  /// 이름 칸이 비었다(공백뿐인 경우 포함).
  nameEmpty,

  /// 이름이 저장 가능한 길이를 넘는다(#1887).
  nameTooLong,

  /// 이메일 칸이 비었다.
  emailEmpty,

  /// 이메일 형식이 아니다.
  emailInvalid,

  /// 전화번호가 `010-0000-0000` 형식이 아니다(비어 있는 경우 포함).
  phoneInvalid,

  /// 비밀번호 칸이 비었다.
  passwordEmpty,

  /// 가입 비밀번호 규칙(8자 이상, 영문·숫자 각 1자 이상)에 맞지 않는다.
  passwordWeak,

  /// 비밀번호 확인이 비밀번호와 다르다.
  passwordMismatch,

  /// 생년월일이 `YYYY-MM-DD` 로 읽히지 않는다(#1887).
  birthDateInvalid,
}

/// 로그인·가입 입력의 형식 규칙(#1784). 두 앱이 같은 정규식을 쓰도록 한곳에 둔다.
///
/// 여기 규칙은 요청을 보내기 전에 사용자가 바로 고칠 수 있게 알려 주는 용도다.
/// 저장되는 값의 기준은 서버에 있다 — 가입 이메일·전화번호는
/// `backend/app/services/contact_format.py` 가, 이름·생년월일은
/// `backend/app/services/profile_format.py` 가 같은 것을 다시 본다(#1780·#1887).
/// 비밀번호는 아직 서버 기준이 없다(#1555).
abstract final class AppInputRules {
  /// 로컬 부분@도메인.최상위 — 흔히 쓰는 주소는 통과시키고 빈칸·골뱅이 누락·
  /// 최상위 도메인 누락 같은 오타를 잡는 정도로만 엄격하다.
  ///
  /// 서버(`contact_format._EMAIL`)가 **같은 식**을 쓴다. 한쪽만 고치면 화면은
  /// 괜찮다는데 가입이 422 로 떨어지는 자리가 생긴다 — 함께 고쳐야 한다.
  static final RegExp _email = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$',
  );

  /// 휴대전화 표기 `010-0000-0000`.
  ///
  /// **앞자리를 `010` 으로 못박는다.** 3자리를 아무 숫자나 받던 때는
  /// `123-4567-8901` 처럼 걸 수 없는 번호가 그대로 통과해, 트레이너가 담당
  /// 회원에게 연락하려고 보는 자리에 남았다. 자릿수만 맞으면 되니 화면은
  /// 아무 말도 하지 않았다.
  ///
  /// 01X 번호는 2021-06-30 에 서비스가 끝나 지금 쓰이는 휴대전화는 전부 010
  /// 이다 — 앞자리를 넓혀도 막히던 사람이 풀리지 않고, 011 은 3-3-4 라
  /// [AppPhoneNumberFormatter] 의 끊는 자리까지 갈라진다.
  ///
  /// 서버(`contact_format.normalize_phone`)가 **같은 앞자리**를 다시 본다.
  static final RegExp _phone = RegExp(r'^010-\d{4}-\d{4}$');

  /// 생년월일 표기 `YYYY-MM-DD`. 실제 날짜인지는 [DateTime.tryParse] 가 본다.
  static final RegExp _birthDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static final RegExp _letter = RegExp('[A-Za-z]');
  static final RegExp _digit = RegExp(r'\d');

  /// 가입 비밀번호의 최소 길이.
  static const int passwordMinLength = 8;

  /// 전화번호 숫자 개수(3 + 4 + 4).
  static const int phoneDigits = 11;

  /// 저장 가능한 이름 길이. 서버 `profile_format.NAME_MAX_LENGTH` 와 같다 —
  /// `users.name` 컬럼(`String(100)`)이 그 기준이다(#1887).
  static const int nameMaxLength = 100;

  /// 이름 — 가입에 꼭 필요하다. 공백만 친 값은 잘라내면 비므로 빈칸으로 본다.
  ///
  /// 상한을 함께 보는 이유는, 넘기면 서버가 422 로 되돌리기 때문이다. 전에는
  /// 컬럼 길이를 넘긴 값이 저장 단계에서 500 으로 터졌다(#1887).
  static AppInputError? name(String value) {
    final String name = value.trim();
    if (name.isEmpty) return AppInputError.nameEmpty;
    if (name.length > nameMaxLength) return AppInputError.nameTooLong;
    return null;
  }

  /// 생년월일 — `YYYY-MM-DD` 이거나 비어 있어야 한다.
  ///
  /// **빈 값을 통과시킨다.** 넣을 자리가 없던 시절에 가입한 회원과 소셜 로그인
  /// 가입자에게는 처음부터 없는 값이라, 이름만 고치려는 사람을 생년월일로 막는
  /// 화면이 되면 안 된다. 서버도 같은 판정이다(#1887).
  ///
  /// 표기만 보지 않고 실제 날짜인지까지 본다 — `1990-13-45` 는 저장된 뒤에
  /// 나이를 세는 쪽에서 조용히 실패한다.
  ///
  /// 읽은 날짜를 **다시 적어 견준다.** [DateTime.tryParse] 만으로는 모자라다 —
  /// 범위를 넘는 값을 되돌려 주지 않고 다음 달로 굴려 버려서(`1990-13-45` 는
  /// 1991-02-14 로 읽힌다), 회원이 친 날짜가 아닌 날짜가 통과한다.
  static AppInputError? birthDate(String value) {
    final String birthDate = value.trim();
    if (birthDate.isEmpty) return null;
    final DateTime? parsed = _birthDate.hasMatch(birthDate)
        ? DateTime.tryParse(birthDate)
        : null;
    if (parsed == null || _asYmd(parsed) != birthDate) {
      return AppInputError.birthDateInvalid;
    }
    return null;
  }

  /// `YYYY-MM-DD`. 위에서 읽은 날짜를 다시 적을 때만 쓴다.
  static String _asYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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

  /// 전화번호 — 정확히 `010-0000-0000`. [AppPhoneNumberFormatter] 가 하이픈을
  /// 넣어 주므로 `010` 으로 시작하는 숫자 11자리를 채우면 맞는다.
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

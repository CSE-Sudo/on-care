/// 로그인·가입 입력 형식 규칙과 전화번호 하이픈 서식 — #1784·#1887.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppPhoneNumberFormatter _formatter = AppPhoneNumberFormatter();

/// [before] 에서 커서 [cursor] 자리에 입력해 [after]·[afterCursor] 가 된 편집을
/// 서식에 통과시킨다.
TextEditingValue _edit(
  String before,
  int cursor,
  String after,
  int afterCursor,
) {
  return _formatter.formatEditUpdate(
    TextEditingValue(
      text: before,
      selection: TextSelection.collapsed(offset: cursor),
    ),
    TextEditingValue(
      text: after,
      selection: TextSelection.collapsed(offset: afterCursor),
    ),
  );
}

/// 끝에서 한 글자씩 치고 매번의 결과를 모은다.
List<String> _typeAtEnd(String keys) {
  TextEditingValue value = TextEditingValue.empty;
  final List<String> seen = <String>[];
  for (final String key in keys.split('')) {
    final String typed = value.text + key;
    value = _edit(value.text, value.text.length, typed, typed.length);
    expect(value.selection.baseOffset, value.text.length, reason: typed);
    seen.add(value.text);
  }
  return seen;
}

void main() {
  group('이름', () {
    test('비었거나 공백뿐이면 빈칸 오류다', () {
      expect(AppInputRules.name(''), AppInputError.nameEmpty);
      expect(AppInputRules.name('   '), AppInputError.nameEmpty);
      expect(AppInputRules.name('\t\n'), AppInputError.nameEmpty);
    });

    test('한 글자라도 있으면 통과한다', () {
      expect(AppInputRules.name('김'), isNull);
      expect(AppInputRules.name(' 김신규 '), isNull);
      expect(AppInputRules.name('Jisu Lee'), isNull);
    });

    // 상한은 서버 `profile_format.NAME_MAX_LENGTH` 와 같은 값이다 — 넘기면
    // 저장이 422 로 되돌아온다(#1887).
    test('상한 바로 안까지만 통과한다', () {
      expect(AppInputRules.name('가' * AppInputRules.nameMaxLength), isNull);
      expect(
        AppInputRules.name('가' * (AppInputRules.nameMaxLength + 1)),
        AppInputError.nameTooLong,
      );
    });

    test('앞뒤 공백은 길이에 세지 않는다 — 보낼 때 잘라내는 값이다', () {
      final String atLimit = '가' * AppInputRules.nameMaxLength;
      expect(AppInputRules.name('  $atLimit  '), isNull);
    });
  });

  group('생년월일', () {
    test('YYYY-MM-DD 는 통과한다', () {
      expect(AppInputRules.birthDate('1996-03-21'), isNull);
      expect(AppInputRules.birthDate('  1996-03-21  '), isNull);
      expect(AppInputRules.birthDate('2024-02-29'), isNull);  // 윤년
    });

    test('비어 있으면 통과한다 — 처음부터 없는 회원이 있다', () {
      expect(AppInputRules.birthDate(''), isNull);
      expect(AppInputRules.birthDate('   '), isNull);
    });

    test('날짜가 아니면 형식 오류다', () {
      for (final String value in <String>[
        'asdfghjkl',
        '1990-01-01T00:00:00Z',  // 컬럼 길이(10)를 넘긴다
        '19900101',
        '90-01-01',
        '1990-1-1',
      ]) {
        expect(AppInputRules.birthDate(value), AppInputError.birthDateInvalid,
            reason: value);
      }
    });

    // DateTime.tryParse 는 범위를 넘는 값을 되돌려 주지 않고 다음 달로 굴린다 —
    // 그대로 두면 회원이 친 날짜가 아닌 날짜가 통과한다.
    test('표기는 맞지만 실제 날짜가 아니면 형식 오류다', () {
      for (final String value in <String>[
        '1990-13-45',
        '1990-02-30',
        '1990-00-01',
        '2023-02-29',  // 평년
      ]) {
        expect(AppInputRules.birthDate(value), AppInputError.birthDateInvalid,
            reason: value);
      }
    });
  });

  group('이메일', () {
    test('흔히 쓰는 주소는 통과한다', () {
      for (final String email in <String>[
        'trainer@oncare.com',
        'minsu@oncare.com',
        'a.b+tag@sub.example.co.kr',
        'USER_1%x@EXAMPLE.ORG',
        'first-last@my-domain.io',
        // 앞뒤 공백은 보내기 전에 잘라내므로 형식 오류가 아니다.
        '  minsu@oncare.com  ',
      ]) {
        expect(AppInputRules.email(email), isNull, reason: email);
      }
    });

    test('비었거나 공백뿐이면 빈칸 오류다', () {
      expect(AppInputRules.email(''), AppInputError.emailEmpty);
      expect(AppInputRules.email('   '), AppInputError.emailEmpty);
    });

    test('형식이 틀리면 형식 오류다', () {
      for (final String email in <String>[
        'plain',
        'no-at.com',
        'a@b',
        'a@b.c',
        'a@.com',
        'a@b..com',
        'a@-b.com',
        'a@b-.com',
        'a@b.com.',
        '.a@b.com',
        'a.@b.com',
        'a..b@c.com',
        'a b@c.com',
        'a@@b.com',
        '@oncare.com',
        '회원@oncare.com',
      ]) {
        expect(
          AppInputRules.email(email),
          AppInputError.emailInvalid,
          reason: email,
        );
      }
    });
  });

  group('전화번호', () {
    test('정확히 000-0000-0000 만 통과한다', () {
      expect(AppInputRules.phone('010-1234-5678'), isNull);
      expect(AppInputRules.phone(' 010-1234-5678 '), isNull);
      for (final String phone in <String>[
        '',
        '01012345678',
        '010-123-5678',
        '02-1234-5678',
        '010-1234-567',
        '010-1234-56789',
        '0101-234-5678',
        '010 1234 5678',
        '010-1234-5678-',
        'abc-defg-hijk',
      ]) {
        expect(
          AppInputRules.phone(phone),
          AppInputError.phoneInvalid,
          reason: phone,
        );
      }
    });
  });

  group('비밀번호', () {
    test('가입은 8자 이상에 영문·숫자를 모두 포함해야 한다', () {
      expect(AppInputRules.signUpPassword(''), AppInputError.passwordEmpty);
      for (final String weak in <String>[
        'abc1234', // 7자
        'abcdefgh', // 숫자 없음
        '12345678', // 영문 없음
        '비밀번호비밀번호12', // 한글은 영문이 아니다
        '!@#\$%^&*',
      ]) {
        expect(
          AppInputRules.signUpPassword(weak),
          AppInputError.passwordWeak,
          reason: weak,
        );
      }
      for (final String ok in <String>[
        'abcdefg1', // 딱 8자
        '1234567a',
        'ABCDEFG1',
        'oncare123',
        'pass word1',
        'signup-pw-1234',
      ]) {
        expect(AppInputRules.signUpPassword(ok), isNull, reason: ok);
      }
    });

    test('로그인은 비었는지만 본다 — 규칙 이전 계정이 막히지 않는다', () {
      expect(AppInputRules.signInPassword(''), AppInputError.passwordEmpty);
      expect(AppInputRules.signInPassword('pw'), isNull);
      expect(AppInputRules.signInPassword('12345678'), isNull);
      expect(AppInputRules.signInPassword('oncare123'), isNull);
    });

    test('확인은 글자 그대로 같아야 한다', () {
      expect(AppInputRules.passwordConfirm('abcdefg1', 'abcdefg1'), isNull);
      expect(
        AppInputRules.passwordConfirm('abcdefg1', 'abcdefg2'),
        AppInputError.passwordMismatch,
      );
      expect(
        AppInputRules.passwordConfirm('abcdefg1', ''),
        AppInputError.passwordMismatch,
      );
    });
  });

  group('전화번호 하이픈 서식', () {
    test('숫자를 치는 대로 3-4-4 로 끊는다', () {
      expect(_typeAtEnd('01012345678'), <String>[
        '0',
        '01',
        '010',
        '010-1',
        '010-12',
        '010-123',
        '010-1234',
        '010-1234-5',
        '010-1234-56',
        '010-1234-567',
        '010-1234-5678',
      ]);
    });

    test('11자리를 넘으면 더 받지 않는다', () {
      final TextEditingValue value = _edit(
        '010-1234-5678',
        13,
        '010-1234-56789',
        14,
      );
      expect(value.text, '010-1234-5678');
      expect(value.selection.baseOffset, 13);
    });

    test('숫자가 아닌 글자는 버리고, 붙여 넣은 번호도 다시 끊는다', () {
      expect(_edit('', 0, 'abc', 3).text, '');
      expect(_edit('', 0, '010 1234 5678', 13).text, '010-1234-5678');
      expect(_edit('', 0, '010.1234.5678', 13).text, '010-1234-5678');
    });

    test('끝에서 지우면 하이픈이 홀로 남지 않는다', () {
      TextEditingValue value = _edit('010-1234-5', 10, '010-1234-', 9);
      expect(value.text, '010-1234');
      expect(value.selection.baseOffset, 8);

      value = _edit('010-1', 5, '010-', 4);
      expect(value.text, '010');
      expect(value.selection.baseOffset, 3);
    });

    test('하이픈 바로 뒤에서 지우면 앞 숫자가 지워진다', () {
      // 하이픈만 지우고 다시 끊으면 아무 일도 없던 것처럼 보인다.
      final TextEditingValue value = _edit('010-1234', 4, '0101234', 3);
      expect(value.text, '011-234');
      expect(value.selection.baseOffset, 2);
    });

    test('가운데를 고치면 커서가 고친 숫자 뒤에 남는다', () {
      // '010-1|234' 에 9 를 넣는다.
      TextEditingValue value = _edit('010-1234', 5, '010-19234', 6);
      expect(value.text, '010-1923-4');
      expect(value.selection.baseOffset, 6);

      // '010-12|34-5678' 에서 2 를 지운다.
      value = _edit('010-1234-5678', 6, '010-134-5678', 5);
      expect(value.text, '010-1345-678');
      expect(value.selection.baseOffset, 5);
    });
  });
}

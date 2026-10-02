/// 비밀번호 재설정 코드 모양(#2824) — 서버 `password_reset.normalize_code` 와
/// 같은 규칙인지 본다. 어긋나면 "메일에 적힌 대로 쳤는데 안 된다" 가 된다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/auth/domain/password_reset_code.dart';

void main() {
  test('서버와 같은 글자·길이다', () {
    expect(PasswordResetCode.alphabet, 'ABCDEFGHJKMNPQRSTUVWXYZ23456789');
    expect(PasswordResetCode.length, 16);
    for (final String ch in '01OIL'.split('')) {
      expect(PasswordResetCode.alphabet.contains(ch), isFalse, reason: ch);
    }
  });

  for (final String typed in <String>[
    'ABCD-EFGH-JKMN-PQRS',
    'abcd-efgh-jkmn-pqrs',
    'ABCDEFGHJKMNPQRS',
    ' ABCD EFGH JKMN PQRS ',
    'abcd efgh-JKMN pqrs\n',
  ]) {
    test('"$typed" 는 같은 코드로 읽는다', () {
      expect(PasswordResetCode.normalize(typed), 'ABCDEFGHJKMNPQRS');
      expect(PasswordResetCode.isWellFormed(typed), isTrue);
      expect(PasswordResetCode.format(typed), 'ABCD-EFGH-JKMN-PQRS');
    });
  }

  for (final String bad in <String>[
    '',
    'ABCD-EFGH-JKMN-PQR',
    'ABCD-EFGH-JKMN-PQRST',
    'ABCD-EFGH-JKMN-PQR0',
    'ABCD-EFGH-JKMN-PQRI',
    '!!!!-!!!!-!!!!-!!!!',
  ]) {
    test('"$bad" 는 모양부터 틀렸다', () {
      expect(PasswordResetCode.isWellFormed(bad), isFalse);
    });
  }

  test('모양이 틀린 값은 하이픈을 넣지 않고 정규화만 한다', () {
    expect(PasswordResetCode.format('ab-cd'), 'ABCD');
  });
}

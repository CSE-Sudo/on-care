/// 회원 동의 항목 규칙 — 서버(`signup_consent.py`)의 회원 기준과 같아야 한다. #2819.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/auth/domain/signup_consent.dart';

void main() {
  test('회원 필수 항목은 약관·개인정보·건강정보·만 14세다 — 마케팅은 선택', () {
    expect(SignupConsent.memberRequired, <String>{
      'terms',
      'privacy',
      'health',
      'age14',
    });
    expect(SignupConsent.isRequired('marketing'), isFalse);
    expect(SignupConsent.memberKinds, contains('marketing'));
  });

  test('건강정보 동의는 개인정보 동의와 별개 항목이다', () {
    expect(SignupConsent.health, isNot(SignupConsent.privacy));
    expect(
      SignupConsent.hasAllRequired(<String>{'terms', 'privacy', 'age14'}),
      isFalse,
    );
  });

  test('필수가 하나라도 빠지면 준비되지 않았다', () {
    for (final String skip in SignupConsent.memberRequired) {
      final Set<String> checked = Set<String>.of(SignupConsent.memberRequired)
        ..remove(skip);
      expect(SignupConsent.hasAllRequired(checked), isFalse, reason: skip);
    }
    expect(SignupConsent.hasAllRequired(<String>{}), isFalse);
  });

  test('선택 항목은 필수 충족에 영향이 없다', () {
    expect(SignupConsent.hasAllRequired(SignupConsent.memberRequired), isTrue);
    expect(
      SignupConsent.hasAllRequired(<String>{
        ...SignupConsent.memberRequired,
        'marketing',
      }),
      isTrue,
    );
  });

  test('보낼 목록은 화면 순서이고 모르는 값은 빠진다', () {
    expect(
      SignupConsent.toPayload(<String>{'marketing', 'age14', 'terms', 'bogus'}),
      <String>['terms', 'age14', 'marketing'],
    );
    expect(SignupConsent.toPayload(<String>{}), isEmpty);
  });
}

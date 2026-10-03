/// 회원 동의 항목 규칙 — 서버(`signup_consent.py`)의 회원 기준과 같아야 한다. #2819.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/auth/domain/signup_consent.dart';

void main() {
  test('회원 필수 항목은 약관·개인정보·건강정보·만 14세다', () {
    expect(SignupConsent.memberRequired, <String>{
      'terms',
      'privacy',
      'health',
      'age14',
    });
  });

  test('마케팅 수신 동의는 더는 묻지 않는다 — 화면 항목은 모두 필수다 (#3007)', () {
    expect(SignupConsent.memberKinds, isNot(contains('marketing')));
    expect(SignupConsent.memberKinds.toSet(), SignupConsent.memberRequired);
    for (final String kind in SignupConsent.memberKinds) {
      expect(SignupConsent.isRequired(kind), isTrue, reason: kind);
    }
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

  test('모르는 값이 섞여도 필수 충족에 영향이 없다', () {
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
      <String>['terms', 'age14'],
    );
    expect(SignupConsent.toPayload(<String>{}), isEmpty);
  });
}

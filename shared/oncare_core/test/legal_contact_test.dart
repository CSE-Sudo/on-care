/// 법적 문서 연락처 정의 지점의 모양. (#3005)
///
/// 값 자체는 팀이 정한다. 여기서는 처리방침 본문과 공개 페이지가 그대로 끼워
/// 넣을 수 있는 모양인지만 본다 — 공백·꺾쇠가 섞이면 mailto 링크와 본문이 깨진다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/legal_contact.dart';

void main() {
  test('보호책임자 연락처는 이메일 하나다', () {
    const String email = LegalContact.privacyOfficerEmail;
    expect(email, matches(RegExp(r'^[^@\s<>"]+@[^@\s<>"]+\.[a-z]{2,}$')));
    expect(email, equals(email.trim()));
  });
}

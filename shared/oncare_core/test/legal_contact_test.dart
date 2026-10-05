/// 법적 문서 연락처 정의 지점의 모양. (#3005)
///
/// 처리방침 본문과 공개 페이지가 그대로 끼워 넣을 수 있는 모양인지 본다 — 공백·
/// 꺾쇠가 섞이면 mailto 링크와 본문이 깨진다. 값은 팀 수신 주소다(#3132).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/legal_contact.dart';

void main() {
  test('보호책임자 연락처는 이메일 하나다', () {
    const String email = LegalContact.privacyOfficerEmail;
    expect(email, matches(RegExp(r'^[^@\s<>"]+@[^@\s<>"]+\.[a-z]{2,}$')));
    expect(email, equals(email.trim()));
  });

  test('보호책임자 연락처는 데모 도메인이 아니다 (#3132)', () {
    // 데모 시드 전용 도메인은 메일을 받지 못한다 — 공개 페이지 생성 도구
    // (`tool/legal/build_legal_pages.py` `DEMO_EMAIL_DOMAINS`)와 같은 목록이다.
    const String email = LegalContact.privacyOfficerEmail;
    final String domain = email.split('@').last;
    for (final String demo in <String>[
      'oncare.com',
      'oncare.demo',
      'example.com',
    ]) {
      expect(domain == demo || domain.endsWith('.$demo'), isFalse);
    }
    expect(email, 'sudo.capstone@gmail.com');
  });
}

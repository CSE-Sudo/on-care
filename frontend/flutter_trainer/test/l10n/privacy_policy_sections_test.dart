/// 트레이너 웹 개인정보 처리방침의 법정 기재 절이 빠지지 않는지. (#2820)
///
/// 회원 앱과 같은 원본 표(`docs/privacy_processing.md`)를 따른다. 트레이너 쪽은
/// 자기 건강정보가 없으므로 민감정보는 3항(담당 회원 정보)에서 다루고, AI 기능으로
/// 국외에 가는 것은 코칭 조건과 담당 회원의 운동 기록·리포트 수치다.
///
/// 문장을 통째로 비교하지 않는다 — 빠지면 안 되는 사실만 본다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/legal_contact.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

const List<String> koSections = <String>[
  '1. 수집하는 개인정보 항목',
  '2. 개인정보의 수집 및 이용 목적',
  '3. 담당 회원 정보의 열람과 처리',
  '4. 개인정보의 보유 및 이용 기간',
  '5. 개인정보의 제3자 제공',
  '6. 개인정보 처리의 위탁',
  '7. 개인정보의 국외 이전',
  '8. 개인정보의 파기 절차 및 방법',
  '9. 개인정보 자동 수집 장치의 설치·운영 및 거부',
  '10. 안전성 확보 조치',
  '11. 만 14세 미만 아동의 개인정보',
  '12. 이용자의 권리',
  '13. 개인정보 보호책임자',
  '14. 권익침해 구제 방법',
  '15. 처리방침의 변경',
];

const List<String> enSections = <String>[
  '1. Information collected',
  '2. Purpose of collection and use',
  '3. Access to and processing of member information',
  '4. Retention',
  '5. Provision to third parties',
  '6. Entrusted processing',
  '7. Transfer of personal information overseas',
  '8. Destruction procedure and method',
  '9. Automatic collection tools',
  '10. Safeguards',
  '11. Children under 14',
  '12. Your rights',
  '13. Privacy officer',
  '14. Remedies for infringement',
  '15. Changes to this policy',
];

const List<String> _processors = <String>[
  'Amazon Web Services, Inc.',
  'Neon',
  'Google LLC',
  'Functional Software, Inc.',
];

List<int> _numbers(String body) => RegExp(
  r'^(\d+)\. ',
  multiLine: true,
).allMatches(body).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();

void main() {
  test('한국어본에 필수 절이 순서대로 모두 있다', () {
    final String body = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    int last = -1;
    for (final String heading in koSections) {
      final int at = body.indexOf('\n$heading\n');
      expect(at, greaterThan(last), reason: '$heading 이 없거나 순서가 다르다');
      last = at;
    }
  });

  test('영문본에 같은 절이 같은 순서로 있다', () {
    final String body = en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    int last = -1;
    for (final String heading in enSections) {
      final int at = body.indexOf('\n$heading\n');
      expect(at, greaterThan(last), reason: '$heading 이 없거나 순서가 다르다');
      last = at;
    }
  });

  test('조항 번호가 1부터 빠짐없이 이어진다 — 두 언어가 같다', () {
    final List<int> expected = List<int>.generate(15, (int i) => i + 1);
    expect(
      _numbers(ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail)),
      expected,
    );
    expect(
      _numbers(en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail)),
      expected,
    );
  });

  test('실제 수탁자와 이전 국가·근거 조항을 적는다', () {
    for (final String name in _processors) {
      expect(
        ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains(name),
        reason: name,
      );
      expect(
        en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
        contains(name),
        reason: name,
      );
    }
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('주식회사 카카오'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('Kakao Corp.'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('싱가포르'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('제28조의8'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('Singapore'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('Article 28-8'),
    );
  });

  test('보관 기간과 탈퇴 시 남는 것을 적는다', () {
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('접속 기록: 1년'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('탈퇴 기록: 2년'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('리포트 PDF 파일 포함'),
    );
    // 회원이 보낸 상담 요청은 트레이너 탈퇴로 지워지지 않는다(trainer_id SET NULL).
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('트레이너 정보만 지운 채 남습니다'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('one year'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('two years'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains("with the trainer's details removed"),
    );
  });

  test('보호책임자는 직책과 연락처로 적는다', () {
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('직책:'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('연락처: ${LegalContact.privacyOfficerEmail}'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('Position:'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('Contact: ${LegalContact.privacyOfficerEmail}'),
    );
  });

  test('시행일이 자리표시자가 아니고 두 언어가 같으며 개정 이력이 있다', () {
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('시행일: 2026년 10월 5일'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('Effective: October 5, 2026'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      isNot(contains('2026년 1월 1일')),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      isNot(contains('January 1, 2026')),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('2026년 10월 1일: 제정'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('October 1, 2026: first issued'),
    );
    expect(ko.myLegalPrivacyEffectiveDate, '시행일 2026. 10. 05.');
    expect(en.myLegalPrivacyEffectiveDate, 'Effective Oct 5, 2026');
  });

  test('보호책임자 연락처 변경이 개정 이력의 맨 위에 있다 (#3132)', () {
    final String k = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    final String e = en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    expect(k, contains('- 2026년 10월 5일: 개인정보 보호책임자 연락처 변경'));
    expect(
      e,
      contains(
        '- October 5, 2026: changed the contact address of the privacy officer',
      ),
    );
    expect(k.indexOf('2026년 10월 5일:'), lessThan(k.indexOf('2026년 10월 3일:')));
    expect(
      e.indexOf('October 5, 2026:'),
      lessThan(e.indexOf('October 3, 2026:')),
    );
  });

  test('보호책임자 연락처가 팀 수신 주소로 채워진다 (#3132)', () {
    expect(LegalContact.privacyOfficerEmail, 'sudo.capstone@gmail.com');
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('연락처: sudo.capstone@gmail.com'),
    );
    expect(
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('Contact: sudo.capstone@gmail.com'),
    );
    for (final String body in <String>[
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
    ]) {
      expect(body, isNot(contains('{contact}')));
      expect(body, isNot(contains('@oncare.com')));
    }
  });

  test('약관 시행일은 처리방침과 따로 간다', () {
    expect(ko.myLegalTermsBody, contains('2026년 10월 3일부터 시행'));
    expect(en.myLegalTermsBody, contains('October 3, 2026'));
    expect(ko.myLegalTermsEffectiveDate, '시행일 2026. 10. 03.');
    expect(en.myLegalTermsEffectiveDate, 'Effective Oct 3, 2026');
  });
}

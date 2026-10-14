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
  test('필수 절이 순서대로 모두 있다', () {
    final String body = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    int last = -1;
    for (final String heading in koSections) {
      final int at = body.indexOf('\n$heading\n');
      expect(at, greaterThan(last), reason: '$heading 이 없거나 순서가 다르다');
      last = at;
    }
  });

  test('조항 번호가 1부터 빠짐없이 이어진다', () {
    final List<int> expected = List<int>.generate(15, (int i) => i + 1);
    expect(
      _numbers(ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail)),
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
    }
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('주식회사 카카오'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('싱가포르'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('제28조의8'),
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
  });

  test('시행일이 자리표시자가 아니고 개정 이력이 있다', () {
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('시행일: 2026년 10월 14일'),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      isNot(contains('2026년 1월 1일')),
    );
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('2026년 10월 1일: 제정'),
    );
    expect(ko.myLegalPrivacyEffectiveDate, '시행일 2026. 10. 14.');
  });

  test('개정 이력은 최신순이고 맨 위가 메일 발송 위탁이다 (#3132·#3443)', () {
    final String k = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    expect(k, contains('- 2026년 10월 5일: 개인정보 보호책임자 연락처 변경'));
    expect(k.indexOf('2026년 10월 14일:'), lessThan(k.indexOf('2026년 10월 5일:')));
    expect(k.indexOf('2026년 10월 5일:'), lessThan(k.indexOf('2026년 10월 3일:')));
  });

  test('메일 발송(Gmail)을 위탁과 국외 이전에 함께 적는다 (#3443)', () {
    // 트레이너는 가입 인증 코드와 비밀번호 재설정 메일을 받는다. 로그인 이메일
    // 변경은 회원 앱에만 있어 변경 안내는 적지 않는다.
    final String body = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    expect(body, contains('- Google LLC: 가입 인증 코드, 비밀번호 재설정 메일 발송(Gmail)'));
    expect(
      body,
      contains('⑤ Google LLC(Gmail) / 미국 등 Google이 운영하는 데이터센터 소재 국가 / '),
    );
    expect(body, contains('그 메일을 보내기 위해 ⑤로 전송됩니다'));
    expect(body, isNot(contains('이메일 변경 안내')));
  });

  test('보호책임자 연락처가 팀 수신 주소로 채워진다 (#3132)', () {
    expect(LegalContact.privacyOfficerEmail, 'sudo.capstone@gmail.com');
    expect(
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      contains('연락처: sudo.capstone@gmail.com'),
    );
    final String body = ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    expect(body, isNot(contains('{contact}')));
    expect(body, isNot(contains('@oncare.com')));
  });

  test('약관 시행일은 처리방침과 따로 간다', () {
    expect(ko.myLegalTermsBody, contains('2026년 10월 3일부터 시행'));
    expect(ko.myLegalTermsEffectiveDate, '시행일 2026. 10. 03.');
  });

  test('처리방침·약관이 네이버·애플을 로그인 수단으로 적지 않는다 (#3217)', () {
    // 네이버·애플 로그인은 제공하지 않는다. 트레이너 웹 문서는 처음부터 소셜 로그인
    // 수단을 나열하지 않았지만, 회원 앱과 문안을 맞추다 다시 들어오지 않게 본다.
    for (final String body in <String>[
      ko.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
      ko.myLegalTermsBody,
    ]) {
      expect(body, isNot(contains('애플')));
      expect(body, isNot(contains('네이버')));
    }
  });
}

/// 위치기반서비스 이용약관 문구(#3136).
///
/// 두 언어의 조 수가 같고, 시행일이 동의 기록 버전(2026-10-05)과 같으며, 동의
/// 시트가 약관과 어긋난 말을 하지 않는지 본다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/legal_contact.dart';

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  const String contact = LegalContact.privacyOfficerEmail;

  test('두 언어의 조 수가 같다', () {
    final int koArticles = RegExp(
      r'^제\d+조 ',
      multiLine: true,
    ).allMatches(ko.myLegalLocationBody(contact)).length;
    final int enArticles = RegExp(
      r'^Article \d+ ',
      multiLine: true,
    ).allMatches(en.myLegalLocationBody(contact)).length;
    expect(koArticles, 11);
    expect(enArticles, koArticles);
  });

  test('시행일이 동의 기록 버전과 같다', () {
    expect(ko.myLegalLocationBody(contact), contains('2026년 10월 5일부터 시행'));
    expect(en.myLegalLocationBody(contact), contains('5 October 2026'));
    expect(ko.myLegalLocationEffectiveDate, '시행일 2026. 10. 05.');
    expect(en.myLegalLocationEffectiveDate, 'Effective Oct 5, 2026');
  });

  test('위치정보관리책임자 연락처가 채워진다', () {
    expect(ko.myLegalLocationBody(contact), contains('연락처: $contact'));
    expect(en.myLegalLocationBody(contact), contains('Contact: $contact'));
    expect(ko.myLegalLocationBody(contact), isNot(contains('{contact}')));
  });

  test('약관이 저장하지 않음·카카오 제공·철회 경로를 밝힌다', () {
    final String body = ko.myLegalLocationBody(contact);
    expect(body, contains('저장하지 않습니다'));
    expect(body, contains('카카오'));
    expect(body, contains('위치정보 이용 동의'));
    final String e = en.myLegalLocationBody(contact);
    expect(e, contains('not stored'));
    expect(e, contains('Kakao'));
    expect(e, contains('Korean version governs'));
  });

  test('동의 시트가 약관과 같은 말을 한다', () {
    // 보관·제공·거부 시 영향 — 시트가 약관과 다른 말을 하면 동의가 흐려진다.
    expect(ko.locationConsentRetention, contains('저장하지 않아요'));
    expect(ko.locationConsentRecipient, contains('카카오'));
    expect(en.locationConsentRetention, contains('Not stored'));
    expect(en.locationConsentRecipient, contains('Kakao'));
    // 철회 경로는 MY 의 스위치 이름과 같다.
    expect(ko.locationConsentRefuse, contains('MY'));
    expect(
      ko.myLegalLocationBody(contact),
      contains(ko.myLocationConsentTitle),
    );
    expect(
      en.myLegalLocationBody(contact),
      contains(en.myLocationConsentTitle),
    );
  });

  test('처리방침의 위치 항목이 동의 절차와 약관을 가리킨다', () {
    final String body = ko.myLegalPrivacyBody(contact);
    expect(body, contains('위치정보 이용에 동의하고'));
    expect(body, contains(ko.myLegalLocationTitle));
    final String e = en.myLegalPrivacyBody(contact);
    expect(e, contains('agree to the use of location information'));
    expect(e, contains(en.myLegalLocationTitle));
  });
}

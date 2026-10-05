/// 영문 약관·개인정보처리방침이 한 문장으로 끝나지 않는지. (#1934)
///
/// 예전에는 영어 로케일에서 `"Terms of Service (Korean original governs)."`
/// 한 줄만 나왔다. 건강 정보를 다루는 앱의 동의 문서라, **수집 항목·보유 기간·
/// 제3자 제공·이용자 권리** 중 어느 것도 고지되지 않는 상태였다.
///
/// 문장을 그대로 비교하지 않는다 — 문안은 다듬을 수 있어야 한다. 대신 한국어본이
/// 가진 조·항이 영문본에도 남아 있는지를 본다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/legal_contact.dart';

void main() {
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  test('영문 약관에 조문이 모두 있다', () {
    final String body = en.myLegalTermsBody;
    for (int article = 1; article <= 14; article++) {
      expect(body, contains('Article $article'), reason: '제$article조가 빠졌다');
    }
    // 한국어본의 조 수만큼 영문본에도 있어야 한다 — 한쪽만 늘면 갈라진다.
    expect(RegExp(r'제\d+조').allMatches(ko.myLegalTermsBody).length, 14);
    // 약관 시행일은 약관 동의 기록 버전과 같은 날이다(#2820, #3006).
    expect(body, contains('3 October 2026'));
  });

  test('영문 개인정보처리방침에 여섯 항이 모두 있다', () {
    final String body = en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail);
    for (final String heading in <String>[
      'Personal information collected',
      'Purpose of collection and use',
      'Retention and use period',
      'Provision to third parties',
      'Rights of the user',
      'Personal information protection officer',
    ]) {
      expect(body, contains(heading));
    }
    expect(body, contains(LegalContact.privacyOfficerEmail));
  });

  test('두 문서 모두 한국어본이 원본임을 밝힌다', () {
    for (final String body in <String>[
      en.myLegalTermsBody,
      en.myLegalPrivacyBody(LegalContact.privacyOfficerEmail),
    ]) {
      expect(body, contains('the Korean version governs'));
      // 한 문장짜리 자리 표시자로 되돌아가지 않게 길이도 함께 본다.
      expect(body.split('\n\n').length, greaterThan(4));
    }
  });

  test('약관에 포인트·쿠폰·해지 효과·분쟁 해결 조항이 두 언어로 있다 (#3006)', () {
    for (final String title in <String>[
      '(포인트)',
      '(쿠폰과 교환 상품)',
      '(예약과 상담 신청)',
      '(이용 계약의 해지와 그 효과)',
      '(분쟁 해결과 관할)',
    ]) {
      expect(ko.myLegalTermsBody, contains(title), reason: title);
    }
    for (final String title in <String>[
      '(Points)',
      '(Coupons and Exchange Items)',
      '(Bookings and Consultation Requests)',
      '(Termination and Its Effects)',
      '(Dispute Resolution and Jurisdiction)',
    ]) {
      expect(en.myLegalTermsBody, contains(title), reason: title);
    }
    expect(
      RegExp(
        r'^Article \d+ ',
        multiLine: true,
      ).allMatches(en.myLegalTermsBody).length,
      RegExp(
        r'^제\d+조 ',
        multiLine: true,
      ).allMatches(ko.myLegalTermsBody).length,
    );
  });

  test('탈퇴 확인 문구가 사라지는 것과 취소되는 것을 말한다 (#3006)', () {
    for (final String part in <String>[
      '포인트',
      '사용 전 쿠폰',
      '보호권',
      'PT 예약',
      '상담 요청',
    ]) {
      expect(ko.myWithdrawConfirm, contains(part), reason: part);
    }
    for (final String part in <String>[
      'points',
      'unused coupons',
      'shields',
      'PT bookings',
      'consultation requests',
    ]) {
      expect(en.myWithdrawConfirm, contains(part), reason: part);
    }
  });
}

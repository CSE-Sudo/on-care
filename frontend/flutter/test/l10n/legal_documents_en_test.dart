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

void main() {
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  test('영문 약관에 조문이 모두 있다', () {
    final String body = en.myLegalTermsBody;
    for (int article = 1; article <= 5; article++) {
      expect(body, contains('Article $article'), reason: '제$article조가 빠졌다');
    }
    // 한국어본의 조 수만큼 영문본에도 있어야 한다 — 한쪽만 늘면 갈라진다.
    expect(RegExp(r'제\d조').allMatches(ko.myLegalTermsBody).length, 5);
    expect(body, contains('1 January 2026'));
  });

  test('영문 개인정보처리방침에 여섯 항이 모두 있다', () {
    final String body = en.myLegalPrivacyBody;
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
    expect(body, contains('support@oncare.com'));
  });

  test('두 문서 모두 한국어본이 원본임을 밝힌다', () {
    for (final String body in <String>[
      en.myLegalTermsBody,
      en.myLegalPrivacyBody,
    ]) {
      expect(body, contains('the Korean version governs'));
      // 한 문장짜리 자리 표시자로 되돌아가지 않게 길이도 함께 본다.
      expect(body.split('\n\n').length, greaterThan(4));
    }
  });
}

/// 트레이너 탈퇴 확인창 문구가 실제로 지워지고 끝나는 것을 빠짐없이 말하는지. (#3006)
///
/// 서버의 트레이너 탈퇴는 프로필·대화·보낸 PT 프로그램·개인운동·일정·예약 가능 시간을 지우고,
/// 담당 회원 연결과 예정된 예약을 끝내며, 회원의 사용 전 PT 재등록 쿠폰을 취소해
/// 포인트를 돌려준다. 확인창이 그중 일부만 말하면 되돌릴 수 없는 동작 앞에서
/// 무엇을 잃는지 모르고 누른다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  test('한국어 문구가 지워지는 것과 끝나는 것을 모두 말한다', () {
    for (final String part in <String>[
      '프로필',
      '회원과의 대화',
      '보낸 PT 프로그램·개인운동',
      '예약 가능 시간',
      '담당 회원 연결',
      '예정된 예약',
      '알림',
      'PT 재등록 쿠폰',
      '포인트가 회원에게 돌아가요',
      '되돌릴 수 없어요',
    ]) {
      expect(ko.myDeleteBody, contains(part), reason: part);
    }
  });

  test('영문 문구도 같은 항목을 말한다', () {
    for (final String part in <String>[
      'profile',
      'messages with members',
      'PT programs and personal exercises you sent',
      'booking times',
      'member links',
      'upcoming bookings',
      'notified',
      'PT renewal coupons',
      'points are returned',
      "can't be undone",
    ]) {
      expect(en.myDeleteBody, contains(part), reason: part);
    }
  });

  test('약관 조 수가 한국어·영문본에서 같다', () {
    final int koArticles = RegExp(
      r'^제\d+조 ',
      multiLine: true,
    ).allMatches(ko.myLegalTermsBody).length;
    final int enArticles = RegExp(
      r'^\d+\. ',
      multiLine: true,
    ).allMatches(en.myLegalTermsBody).length;
    expect(koArticles, 13);
    expect(enArticles, koArticles);
  });

  test('약관에 쿠폰 사용 처리·이용 제한·분쟁 해결 조항이 있다', () {
    expect(ko.myLegalTermsBody, contains('회원 쿠폰의 사용 처리'));
    expect(ko.myLegalTermsBody, contains('이용 제한'));
    expect(ko.myLegalTermsBody, contains('분쟁 해결과 관할'));
  });
}

/// 트레이너 데이터 공유 동의 문구가 알려야 하는 것. (#2826)
///
/// 담당 연결이 성립하는 두 순간(동기화 코드 시트·담당 요청 수락 동의창)의 문구는
/// 무엇을 볼 수 있는지만이 아니라 이용 목적, 철회 뒤에도 남는 기록, 거부할 권리까지
/// 말해야 한다. 공유 범위는 서로, 그리고 개인정보 처리방침 5항과 같아야 한다.
///
/// 문장을 통째로 비교하지 않는다. 빠지면 안 되는 사실이 남아 있는지만 본다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  const String koScope = '식단 기록·운동 기록·신체 정보와 건강 목표';
  const String enScope =
      'meal records, workout records, body information and health goals';

  group('한국어', () {
    final Map<String, String> consents = <String, String>{
      'coachInviteConsentBody': ko.coachInviteConsentBody('김코치'),
      'trainerSyncConsent': ko.trainerSyncConsent,
    };

    test('두 동의 문구가 같은 범위·목적·남는 기록·거부권을 말한다', () {
      consents.forEach((String key, String text) {
        expect(text, contains(koScope), reason: key);
        expect(text, contains('코칭·상담·리포트 작성'), reason: key);
        expect(text, contains('열람 권한'), reason: key);
        expect(text, contains('주고받은 대화와 전달된 리포트는 남아요'), reason: key);
        expect(text, contains('동의하지 않아도'), reason: key);
      });
    });

    test('수락 안내도 같은 범위를 말한다 — 식단·운동만으로 좁히지 않는다', () {
      expect(ko.coachInviteExplain, contains(koScope));
    });

    test('범위가 처리방침 5항과 같다', () {
      expect(ko.myLegalPrivacyBody, contains(koScope));
      expect(ko.trainerShareItems, koScope);
    });

    test('자세히는 받는 사람·항목·목적·기간·거부권 다섯 가지다', () {
      expect(ko.trainerShareRecipient, contains('트레이너'));
      expect(ko.trainerSharePurpose, '코칭·상담·리포트 작성');
      expect(ko.trainerSharePeriod, contains('MY 탭'));
      expect(ko.trainerSharePeriod, contains('철회'));
      expect(ko.trainerSharePeriod, contains('대화와 전달된 리포트'));
      expect(ko.trainerShareRefuse, contains('개인 기록 기능'));
      expect(ko.trainerShareRefuse, contains('트레이너 연결만 되지 않아요'));
    });

    test('상담 신청 안내도 목적·남는 곳·거부할 때를 한 줄씩 말한다', () {
      final String text = ko.exConsultDataSharingNotice;
      expect(text, contains('이름·운동 목표·문의 내용'));
      expect(text, contains('상담을 위해'));
      expect(text, contains('상담 요청과 일정에 남아요'));
      expect(text, contains('동의하지 않으면'));
    });
  });

  group('영어', () {
    final Map<String, String> consents = <String, String>{
      'coachInviteConsentBody': en.coachInviteConsentBody('Kim'),
      'trainerSyncConsent': en.trainerSyncConsent,
    };

    test('두 동의 문구가 같은 범위·목적·남는 기록·거부권을 말한다', () {
      consents.forEach((String key, String text) {
        expect(text, contains(enScope), reason: key);
        expect(
          text,
          contains('coaching, consultations and writing reports'),
          reason: key,
        );
        expect(text, contains('reports already delivered'), reason: key);
        expect(text, contains("even if you don't agree"), reason: key);
      });
    });

    test('수락 안내와 처리방침도 같은 범위를 말한다', () {
      expect(en.coachInviteExplain, contains(enScope));
      expect(en.myLegalPrivacyBody, contains(enScope));
    });

    test('자세히의 다섯 항목이 모두 있다', () {
      for (final String text in <String>[
        en.trainerShareRecipientLabel,
        en.trainerShareRecipient,
        en.trainerShareItemsLabel,
        en.trainerShareItems,
        en.trainerSharePurposeLabel,
        en.trainerSharePurpose,
        en.trainerSharePeriodLabel,
        en.trainerSharePeriod,
        en.trainerShareRefuseLabel,
        en.trainerShareRefuse,
      ]) {
        expect(text, isNotEmpty);
      }
      expect(en.trainerSharePeriod, contains('MY tab'));
      expect(en.trainerShareRefuse, contains('personal records'));
    });

    test('상담 신청 안내도 목적·남는 곳·거부할 때를 말한다', () {
      final String text = en.exConsultDataSharingNotice;
      expect(text, contains('for the consultation'));
      expect(text, contains('stay with the request'));
      expect(text, contains("If you don't agree"));
    });
  });
}

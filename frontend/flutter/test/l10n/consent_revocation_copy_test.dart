/// 담당 해제 = 데이터 공유 동의 철회를 회원에게 알리는 문구. (#1631)
///
/// 서버는 담당을 끊는 순간 동의를 비우고 철회 시각을 남긴다. 회원이 그 사실을
/// 모른 채 해제하지 않도록, 해제 확인 창과 개인정보 처리방침이 같은 규칙을 말해야
/// 한다 — 철회되면 트레이너가 새 기록을 볼 수 없고, 이미 주고받은 대화·리포트는
/// 남는다.
///
/// 문장을 통째로 비교하지 않는다. 문안은 다듬을 수 있어야 하므로, 빠지면 안 되는
/// 사실이 남아 있는지만 본다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  group('해제 확인 창 — 한국어', () {
    final List<String> messages = <String>[
      ko.myTrainerDisconnectConfirm('김코치', '온케어짐'),
      ko.myGymDisconnectWithTrainerConfirm('온케어짐', '김코치'),
    ];

    test('동의 철회를 알린다', () {
      for (final String message in messages) {
        expect(message, contains('데이터 공유 동의'));
        expect(message, contains('철회'));
      }
    });

    test('트레이너가 새 기록을 볼 수 없다고 말한다', () {
      for (final String message in messages) {
        expect(message, contains('새 기록'));
      }
    });

    test('이미 주고받은 대화와 리포트는 남는다고 말한다', () {
      for (final String message in messages) {
        expect(message, contains('대화'));
        expect(message, contains('리포트'));
        expect(message, contains('남습니다'));
      }
    });

    test('기존 안내(무엇이 끊기고 무엇이 남는지)는 그대로다', () {
      expect(messages[0], startsWith('담당 트레이너 김코치 연결을 삭제하시겠습니까?'));
      expect(messages[0], contains('온케어짐 헬스장 연결은 유지됩니다.'));
      expect(messages[1], startsWith('온케어짐 연결을 삭제하시겠습니까?'));
      expect(messages[1], contains('담당 트레이너 김코치 연결도 함께 해제됩니다.'));
    });

    test('담당이 없는 헬스장 해제에는 동의 안내를 붙이지 않는다', () {
      final String message = ko.myGymDisconnectConfirm('온케어짐');
      expect(message, isNot(contains('동의')));
    });
  });

  group('해제 확인 창 — 영어', () {
    final List<String> messages = <String>[
      en.myTrainerDisconnectConfirm('Coach Kim', 'OnCare Gym'),
      en.myGymDisconnectWithTrainerConfirm('OnCare Gym', 'Coach Kim'),
    ];

    test('동의 철회와 기록 보존을 알린다', () {
      for (final String message in messages) {
        expect(message, contains('data-sharing consent'));
        expect(message, contains('withdrawn'));
        expect(message, contains('new records'));
        expect(message, contains('Messages and reports'));
        expect(message, contains('will stay'));
      }
    });

    test('한국어가 섞이지 않는다', () {
      for (final String message in messages) {
        expect(RegExp(r'[가-힣]').hasMatch(message), isFalse, reason: message);
      }
    });

    test('담당이 없는 헬스장 해제에는 동의 안내를 붙이지 않는다', () {
      expect(
        en.myGymDisconnectConfirm('OnCare Gym'),
        isNot(contains('consent')),
      );
    });
  });

  group('개인정보 처리방침', () {
    test('한국어본에 트레이너 공유·동의 철회 조항이 있다', () {
      final String body = ko.myLegalPrivacyBody;
      expect(body, contains('5. 담당 트레이너와의 정보 공유 및 동의 철회'));
      expect(body, contains('동의한 시각과 철회한 시각을 기록'));
      expect(body, contains('새 기록을 볼 수 없'));
      expect(body, contains('새로 동의해야'));
      expect(body, contains('삭제되지 않고 남습니다'));
      // 트레이너가 해제한 경우도 철회다.
      expect(body, contains('트레이너가 담당을 해제한 경우에도'));
    });

    test('영문본에 같은 조항이 있다', () {
      final String body = en.myLegalPrivacyBody;
      expect(
        body,
        contains('5. Sharing with your trainer and withdrawing consent'),
      );
      expect(
        body,
        contains('when consent was given and when it was withdrawn'),
      );
      expect(body, contains('can no longer see your new records'));
      expect(body, contains('requires your consent again'));
      expect(body, contains('are not deleted'));
      expect(body, contains('when the trainer ends the coaching relationship'));
    });

    List<int> numbers(String body) => RegExp(
      r'^(\d)\. ',
      multiLine: true,
    ).allMatches(body).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();

    test('조항 번호가 1부터 빠짐없이 이어진다 — 두 언어가 같다', () {
      final List<int> expected = <int>[1, 2, 3, 4, 5, 6, 7];
      expect(numbers(ko.myLegalPrivacyBody), expected);
      expect(numbers(en.myLegalPrivacyBody), expected);
    });

    test('기존 조항은 뒤로 밀렸을 뿐 그대로 있다', () {
      expect(ko.myLegalPrivacyBody, contains('6. 이용자의 권리'));
      expect(ko.myLegalPrivacyBody, contains('7. 개인정보 보호책임자'));
      expect(en.myLegalPrivacyBody, contains('6. Rights of the user'));
      expect(
        en.myLegalPrivacyBody,
        contains('7. Personal information protection officer'),
      );
    });

    test('담당 연결 동의 화면과 같은 공유 범위를 말한다', () {
      // 연결할 때 보여 준 범위와 처리방침의 범위가 갈리면 안 된다.
      expect(
        ko.coachInviteConsentBody('김코치'),
        contains('식단 기록·운동 기록·신체 정보와 건강 목표'),
      );
      expect(ko.myLegalPrivacyBody, contains('식단 기록·운동 기록·신체 정보와 건강 목표'));
      expect(
        en.coachInviteConsentBody('Kim'),
        contains(
          'meal records, workout records, body information and health goals',
        ),
      );
      expect(
        en.myLegalPrivacyBody,
        contains(
          'meal records, workout records, body information and health goals',
        ),
      );
    });
  });
}

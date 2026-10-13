import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/search/domain/client_search.dart';
import 'package:oncare_trainer/features/search/domain/client_search_facts.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/chat_preview.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

/// 로스터 미리보기 코드가 화면 문구로 옮겨지는지 본다 (#2303).
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  group('chatPreviewMessage', () {
    test('대화가 없으면 "아직 대화가 없어요" 다', () {
      expect(chatPreviewMessage(ko, ''), '아직 대화가 없어요');
    });

    test('공백만 있어도 대화가 없는 것이다', () {
      expect(chatPreviewMessage(ko, '   '), '아직 대화가 없어요');
      expect(chatPreviewMessage(ko, '\n\t '), '아직 대화가 없어요');
    });

    test('이모티콘 코드는 화면 문구로 옮겨진다', () {
      expect(chatPreviewMessage(ko, ChatPreviewCode.emote), '이모티콘을 보냈어요');
    });

    test('회원의 말은 그대로다', () {
      for (final String body in <String>['내일 봬요!', 'See you tomorrow', '-']) {
        expect(chatPreviewMessage(ko, body), body);
      }
    });

    test('예전에 저장된 한국어 문구는 손대지 않는다', () {
      // 코드가 아니면 회원·트레이너가 쓴 글로 본다 — 추측해서 옮기지 않는다.
      expect(chatPreviewMessage(ko, '(이모티콘)'), '(이모티콘)');
    });
  });

  group('chatPreviewTime', () {
    test('방금 코드는 화면 문구로 옮겨진다', () {
      expect(chatPreviewTime(ko, ChatPreviewCode.justNow), '방금');
    });

    test('시각·날짜·자리표시는 그대로다', () {
      for (final String time in <String>['18:16', '2026-09-20', '-', '']) {
        expect(chatPreviewTime(ko, time), time);
      }
    });
  });

  group('ChatPreviewCode', () {
    test('코드만 코드로 본다', () {
      expect(ChatPreviewCode.isCode(ChatPreviewCode.emote), isTrue);
      expect(ChatPreviewCode.isCode(ChatPreviewCode.justNow), isTrue);
      expect(ChatPreviewCode.isCode('emote'), isFalse);
      expect(ChatPreviewCode.isCode(''), isFalse);
      expect(ChatPreviewCode.isCode('방금'), isFalse);
    });

    test('두 코드는 서로 다르고 화면 문구와 겹치지 않는다', () {
      expect(ChatPreviewCode.emote, isNot(ChatPreviewCode.justNow));
      expect(ChatPreviewCode.isCode(ko.messagesPreviewEmote), isFalse);
      expect(ChatPreviewCode.isCode(ko.messagesTimeJustNow), isFalse);
      expect(ChatPreviewCode.isCode(ko.messagesNoPreview), isFalse);
    });
  });

  group('TrainerClient 확장', () {
    test('방금 보낸 이모티콘은 화면 문구로 읽힌다', () {
      final TrainerClient client = makeClient(
        lastMessage: ChatPreviewCode.emote,
        lastTime: ChatPreviewCode.justNow,
      );
      expect(client.previewMessage(ko), '이모티콘을 보냈어요');
      expect(client.previewTime(ko), '방금');
    });
  });

  group('검색', () {
    test('검색 요약의 미리보기도 화면 문구다', () {
      final TrainerClient client = makeClient(
        lastMessage: ChatPreviewCode.emote,
        lastTime: ChatPreviewCode.justNow,
      );
      final String detail = clientSearchDetail(
        ko,
        client,
        ClientSearchFacts.none,
      );
      expect(detail, contains('이모티콘을 보냈어요 · 방금'));
      expect(detail, isNot(contains('@')));
    });

    test('회원의 말은 검색 요약에 그대로 나온다', () {
      final TrainerClient client = makeClient(
        lastMessage: 'See you tomorrow',
        lastTime: ChatPreviewCode.justNow,
      );
      expect(
        clientSearchDetail(ko, client, ClientSearchFacts.none),
        contains('See you tomorrow · 방금'),
      );
    });

    test('미리보기 코드는 검색어로 걸리지 않는다', () {
      final TrainerClient emote = makeClient(
        id: 'e',
        name: '김하나',
        lastMessage: ChatPreviewCode.emote,
      );
      expect(searchClients(<TrainerClient>[emote], 'emote'), isEmpty);
      expect(searchClients(<TrainerClient>[emote], '@'), isEmpty);
      // 이름으로는 그대로 찾는다.
      expect(searchClients(<TrainerClient>[emote], '김하나'), <TrainerClient>[
        emote,
      ]);
    });

    test('회원의 말은 계속 검색된다', () {
      final TrainerClient client = makeClient(
        lastMessage: 'knee feels better now',
      );
      expect(searchClients(<TrainerClient>[client], 'knee'), <TrainerClient>[
        client,
      ]);
    });
  });
}

/// 회원 대화를 쪽 단위로 받아 합치는 규칙. (#2749)
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/clients/domain/chat_thread_paging.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

ClientChatMessage _m(String id, int minute, {String body = ''}) =>
    ClientChatMessage(
      id: id,
      sender: ChatSender.client,
      body: body.isEmpty ? id : body,
      timeLabel: '10:00',
      createdAt: DateTime.utc(2026, 9, 14, 1, minute),
    );

List<String> _ids(Iterable<ClientChatMessage> list) =>
    list.map((m) => m.id).toList();

void main() {
  group('compareChatMessages', () {
    test('시각이 먼저, 같은 시각이면 id 로 가른다', () {
      final List<ClientChatMessage> list = <ClientChatMessage>[
        _m('b', 1),
        _m('c', 0),
        _m('a', 1),
      ]..sort(compareChatMessages);

      expect(_ids(list), <String>['c', 'a', 'b']);
    });
  });

  group('mergeChatThread', () {
    test('겹치는 id 는 하나만 남기고 오래된→최신으로 세운다', () {
      final merged = mergeChatThread(
        <ClientChatMessage>[_m('m1', 1), _m('m2', 2), _m('m3', 3)],
        <ClientChatMessage>[_m('m3', 3), _m('m4', 4)],
      );

      expect(_ids(merged), <String>['m1', 'm2', 'm3', 'm4']);
    });

    test('같은 id 는 나중에 받은 쪽을 쓴다', () {
      final merged = mergeChatThread(
        <ClientChatMessage>[_m('m1', 1, body: '옛 본문')],
        <ClientChatMessage>[_m('m1', 1, body: '새 본문')],
      );

      expect(merged.single.body, '새 본문');
    });

    test('받은 차례와 상관없이 시각 순서로 둔다', () {
      final merged = mergeChatThread(
        <ClientChatMessage>[_m('late', 9)],
        <ClientChatMessage>[_m('early', 1)],
      );

      expect(_ids(merged), <String>['early', 'late']);
    });

    test('폴링이 최신 쪽만 다시 줘도 받아 둔 이전 쪽은 사라지지 않는다', () {
      // 이전 쪽(0~49)을 받아 둔 뒤, 폴링이 최신 쪽(50~99)을 다시 준다.
      final List<ClientChatMessage> all = <ClientChatMessage>[
        for (int i = 0; i < 100; i++) _m('m${i.toString().padLeft(3, '0')}', i),
      ];
      final List<ClientChatMessage> latest = pageChatThread(all);
      final List<ClientChatMessage> older = pageChatThread(
        all,
        before: latest.first,
      );
      final List<ClientChatMessage> held = mergeChatThread(older, latest);

      final List<ClientChatMessage> afterPoll = mergeChatThread(
        held,
        pageChatThread(all),
      );

      expect(afterPoll, hasLength(100));
      expect(_ids(afterPoll), _ids(all));
    });
  });

  group('pageChatThread', () {
    final List<ClientChatMessage> all = <ClientChatMessage>[
      for (int i = 0; i < 120; i++) _m('m${i.toString().padLeft(3, '0')}', i),
    ];

    test('커서가 없으면 최신 chatPageSize 건이다', () {
      final page = pageChatThread(all);

      expect(page, hasLength(chatPageSize));
      expect(page.first.id, 'm070');
      expect(page.last.id, 'm119');
    });

    test('커서 앞의 최신 한 쪽을 준다 — 커서 자신은 빠진다', () {
      final page = pageChatThread(all, before: all[70]);

      expect(page, hasLength(chatPageSize));
      expect(page.first.id, 'm020');
      expect(page.last.id, 'm069');
    });

    test('남은 것이 한 쪽보다 적으면 덜 찬 쪽 — 그 앞에는 없다', () {
      final page = pageChatThread(all, before: all[20]);

      expect(page, hasLength(20));
      expect(page.first.id, 'm000');
    });

    test('같은 시각의 메시지도 id 로 경계를 가른다', () {
      final List<ClientChatMessage> tied = <ClientChatMessage>[
        _m('a', 5),
        _m('b', 5),
        _m('c', 5),
      ];

      expect(_ids(pageChatThread(tied, before: tied[2])), <String>['a', 'b']);
    });
  });
}

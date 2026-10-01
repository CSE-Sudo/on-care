/// 회원 메시지의 이전 쪽 상태 — 받기·멈춤·폴링 병합·실패·틈 메우기. (#2749)
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/clients/domain/chat_thread_paging.dart';
import 'package:oncare_trainer/features/clients/presentation/controllers/chat_thread_history.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

import '../../helpers/paged_chat_repository.dart';

const String _client = 'c1';

void main() {
  late PagedChatRepository repo;
  late ProviderContainer container;

  ProviderContainer open(int count) {
    repo = PagedChatRepository(pagedChatThread(count));
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[chatRepositoryProvider.overrideWithValue(repo)],
    );
    // 화면처럼 둘 다 지켜본다 — autoDispose 라 듣는 이가 없으면 사라진다.
    c
      ..listen(chatThreadProvider(_client), (_, _) {})
      ..listen(chatThreadHistoryProvider(_client), (_, _) {});
    addTearDown(() async {
      c.dispose();
      await repo.close();
    });
    return c;
  }

  Future<List<ClientChatMessage>> latest() =>
      container.read(chatThreadProvider(_client).future);

  ChatThreadHistoryState history() =>
      container.read(chatThreadHistoryProvider(_client));

  ChatThreadHistory notifier() =>
      container.read(chatThreadHistoryProvider(_client).notifier);

  List<ClientChatMessage> visible() => visibleChatThread(
    history(),
    container.read(chatThreadProvider(_client)).valueOrNull ??
        const <ClientChatMessage>[],
  );

  test('이전 쪽을 받으면 최신 쪽 앞에 이어 붙는다', () async {
    container = open(120);
    final List<ClientChatMessage> first = await latest();

    await notifier().loadOlder(first.first);

    expect(repo.olderCursors.single.id, 'm070');
    expect(visible(), hasLength(100));
    expect(visible().first.id, 'm020');
    expect(history().exhausted, isFalse);
  });

  test('처음 메시지까지 받으면 더 요청하지 않는다', () async {
    container = open(120);
    await notifier().loadOlder((await latest()).first);
    await notifier().loadOlder(visible().first);

    expect(history().exhausted, isTrue);
    expect(visible(), hasLength(120));
    expect(visible().first.id, 'm000');

    await notifier().loadOlder(visible().first);
    expect(repo.olderCursors, hasLength(2));
    expect(
      canLoadOlderChat(history(), await latest()),
      isFalse,
      reason: '맨 위 자리도 사라진다',
    );
  });

  test('최신 쪽이 덜 찬 대화는 이전 쪽을 받을 자리가 없다', () async {
    container = open(30);

    expect(canLoadOlderChat(history(), await latest()), isFalse);
  });

  test('받는 중에 다시 불러도 한 번만 요청한다', () async {
    container = open(120);
    final ClientChatMessage oldest = (await latest()).first;
    repo.olderGate = Completer<void>();

    final Future<void> first = notifier().loadOlder(oldest);
    expect(history().loading, isTrue);
    await notifier().loadOlder(oldest);
    repo.olderGate!.complete();
    await first;

    expect(repo.olderCursors, hasLength(1));
    expect(history().loading, isFalse);
  });

  test('폴링 뒤에도 받아 둔 이전 쪽이 남고 중복되지 않는다', () async {
    container = open(120);
    await notifier().loadOlder((await latest()).first);

    // 새 메시지 두 건이 오고, 폴링이 최신 쪽을 다시 준다.
    repo.thread = <ClientChatMessage>[
      ...repo.thread,
      pagedChatMessage(120),
      pagedChatMessage(121),
    ];
    repo.poll();
    await pumpEventQueue();

    final List<ClientChatMessage> thread = visible();
    expect(thread, hasLength(102));
    expect(thread.first.id, 'm020');
    expect(thread.last.id, 'm121');
    expect(thread.map((m) => m.id).toSet(), hasLength(thread.length));
    // 최신 쪽이 m072.. 로 밀려도 경계의 m070·m071 이 남는다.
    expect(thread.map((m) => m.id), containsAll(<String>['m070', 'm071']));
  });

  test('폴링 사이에 한 쪽이 넘게 오면 그 틈을 커서로 메운다', () async {
    container = open(120);
    await notifier().loadOlder((await latest()).first);

    // 60건이 한꺼번에 와서 새 최신 쪽(m130..m179)이 받아 둔 것과 겹치지 않는다.
    repo.thread = <ClientChatMessage>[
      ...repo.thread,
      for (int i = 120; i < 180; i++) pagedChatMessage(i),
    ];
    repo.poll();
    await pumpEventQueue();

    final List<String> ids = visible().map((m) => m.id).toList();
    expect(ids, hasLength(160));
    expect(ids.first, 'm020');
    expect(ids, containsAll(<String>['m120', 'm125', 'm129']));
    expect(repo.olderCursors.last.id, 'm130');
  });

  test('이전 쪽을 받기 전에는 폴링을 따로 모으지 않는다', () async {
    container = open(120);
    await latest();
    repo.poll();
    await pumpEventQueue();

    expect(history().messages, isEmpty);
    expect(visible(), hasLength(chatPageSize));
  });

  test('실패해도 받아 둔 것을 지키고, 다시 부르면 같은 커서로 받는다', () async {
    container = open(170);
    await notifier().loadOlder((await latest()).first);
    final int before = visible().length;

    repo.failOlder = true;
    await notifier().loadOlder(visible().first);
    expect(history().failed, isTrue);
    expect(history().loading, isFalse);
    expect(visible(), hasLength(before));

    repo.failOlder = false;
    await notifier().loadOlder(visible().first);
    expect(history().failed, isFalse);
    expect(visible(), hasLength(before + chatPageSize));
    expect(repo.olderCursors[1].id, repo.olderCursors[2].id);
  });
}

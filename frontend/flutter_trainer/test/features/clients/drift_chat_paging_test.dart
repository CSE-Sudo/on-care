/// 데모 대화도 서버와 같은 쪽으로 준다. (#2749)
///
/// 데모가 언제나 전부를 주면 쪽 사이의 경계가 데모에서만 없어 보여, 이어 받기가
/// 데모로는 확인되지 않는다.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/clients/domain/chat_thread_paging.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

void main() {
  late AppDatabase db;
  late DriftChatRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftChatRepository(db);
  });

  tearDown(() => db.close());

  Future<void> insert(String clientId, String id, DateTime at) => db
      .into(db.clientChatMessages)
      .insert(
        ClientChatMessagesCompanion.insert(
          id: id,
          clientId: clientId,
          sender: 'client',
          body: id,
          timeLabel: '10:00',
          createdAt: at,
        ),
      );

  Future<void> insertMany(int count) async {
    for (int i = 0; i < count; i++) {
      await insert(
        'c1',
        'm${i.toString().padLeft(3, '0')}',
        DateTime(2026, 9, 2).add(Duration(minutes: i)),
      );
    }
  }

  List<String> ids(List<ClientChatMessage> list) =>
      list.map((m) => m.id).toList();

  test('watchThread 는 최신 한 쪽만 오래된→최신으로 준다', () async {
    await insertMany(120);

    final latest = await repo.watchThread('c1').first;

    expect(latest, hasLength(chatPageSize));
    expect(latest.first.id, 'm070');
    expect(latest.last.id, 'm119');
  });

  test('fetchOlder 로 처음 메시지까지 이어 받고, 마지막 쪽은 덜 찬다', () async {
    await insertMany(120);

    final latest = await repo.watchThread('c1').first;
    final second = await repo.fetchOlder('c1', before: latest.first);
    final third = await repo.fetchOlder('c1', before: second.first);

    expect(second, hasLength(chatPageSize));
    expect(second.first.id, 'm020');
    expect(second.last.id, 'm069');
    expect(third, hasLength(20));
    expect(third.first.id, 'm000');

    final whole = mergeChatThread(mergeChatThread(third, second), latest);
    expect(whole, hasLength(120));
  });

  test('다른 회원의 메시지는 섞이지 않는다', () async {
    await insertMany(60);
    await insert('c2', 'other', DateTime(2026, 8, 2));

    final latest = await repo.watchThread('c1').first;
    final older = await repo.fetchOlder('c1', before: latest.first);

    expect(ids(older), isNot(contains('other')));
    expect(older, hasLength(10));
  });

  test('같은 시각의 메시지는 id 로 경계를 가른다 — 빠지거나 겹치지 않는다', () async {
    final DateTime at = DateTime(2026, 9, 1, 9);
    for (final String id in <String>['a', 'b', 'c']) {
      await insert('c1', id, at);
    }
    final ClientChatMessage cursor = (await repo.watchThread('c1').first)
        .firstWhere((m) => m.id == 'c');

    final older = await repo.fetchOlder('c1', before: cursor);

    expect(ids(older), <String>['a', 'b']);
  });

  test('한 쪽이 안 되는 대화는 watchThread 가 전부를 준다', () async {
    await insertMany(3);

    expect(ids(await repo.watchThread('c1').first), <String>[
      'm000',
      'm001',
      'm002',
    ]);
  });
}

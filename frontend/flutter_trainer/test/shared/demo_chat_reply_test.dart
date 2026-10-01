/// 트레이너 웹 데모의 회원 자동 답장. (#2790)
///
/// 실서버에서는 회원이 실제로 답하고, 답이 오면 안 읽음 배지와 고객 목록
/// 미리보기가 바뀐다. 데모에는 답할 사람이 없어 보내도 대화가 멈춰 있었다.
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

const String _client = 'seed-client-1';
const Duration _delay = Duration(milliseconds: 10);

Future<void> _waitReply() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db);
  });

  tearDown(() async => db.close());

  Future<List<ClientChatMessage>> thread(DriftChatRepository repo) =>
      repo.watchThread(_client).first;

  test('보내면 잠시 뒤 회원 답이 붙고 안 읽음이 된다', () async {
    final DemoRepliesChatRepository repo = DemoRepliesChatRepository(
      db,
      replyDelay: _delay,
    );
    addTearDown(repo.dispose);
    await repo.markThreadRead(_client);
    expect((await repo.watchUnreadCounts().first)[_client], isNull);

    await repo.sendTrainerMessage(clientId: _client, text: '오늘 걷기 잊지 마세요');
    expect((await thread(repo)).last.sender, ChatSender.trainer);

    await _waitReply();
    final ClientChatMessage last = (await thread(repo)).last;
    expect(last.sender, ChatSender.client);
    expect(last.body, isNotEmpty);
    expect((await repo.watchUnreadCounts().first)[_client], 1);

    final TrainerClientRow row = await (db.select(
      db.trainerClients,
    )..where((t) => t.id.equals(_client))).getSingle();
    expect(row.lastMessage, last.body);
  });

  test('사진을 보내도 답한다', () async {
    final DemoRepliesChatRepository repo = DemoRepliesChatRepository(
      db,
      replyDelay: _delay,
    );
    addTearDown(repo.dispose);

    await repo.sendTrainerImage(
      clientId: _client,
      bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]),
      fileName: 'pose.jpg',
    );
    await _waitReply();

    expect((await thread(repo)).last.sender, ChatSender.client);
  });

  test('리포트 등록 안내에는 답하지 않는다', () async {
    final DemoRepliesChatRepository repo = DemoRepliesChatRepository(
      db,
      replyDelay: _delay,
    );
    addTearDown(repo.dispose);

    await repo.sendTrainerMessage(
      clientId: _client,
      text: '이번 주 리포트 등록해 뒀어요',
      reportWeekStart: DateTime(2026, 9, 28),
    );
    await _waitReply();

    expect((await thread(repo)).last.sender, ChatSender.trainer);
  });

  test('데모 답장 저장소가 아니면 답하지 않는다', () async {
    final DriftChatRepository repo = DriftChatRepository(db);

    await repo.sendTrainerMessage(clientId: _client, text: '안녕하세요');
    await _waitReply();

    expect((await thread(repo)).last.sender, ChatSender.trainer);
  });

  test('저장소를 버리면 기다리던 답을 거둔다', () async {
    final DemoRepliesChatRepository repo = DemoRepliesChatRepository(
      db,
      replyDelay: _delay,
    );

    await repo.sendTrainerMessage(clientId: _client, text: '안녕하세요');
    repo.dispose();
    await _waitReply();

    expect((await thread(repo)).last.sender, ChatSender.trainer);
  });

  test('영어 데모에는 영어로 답한다', () async {
    final AppDatabase en = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(en.close);
    await seedIfEmpty(en, language: DemoLanguage.en);
    final DemoRepliesChatRepository repo = DemoRepliesChatRepository(
      en,
      replyDelay: _delay,
    );
    addTearDown(repo.dispose);

    await repo.sendTrainerMessage(clientId: _client, text: 'Hello');
    await _waitReply();

    final ClientChatMessage last = (await repo.watchThread(_client).first).last;
    expect(last.sender, ChatSender.client);
    expect(RegExp(r'[가-힣]').hasMatch(last.body), isFalse);
  });
}

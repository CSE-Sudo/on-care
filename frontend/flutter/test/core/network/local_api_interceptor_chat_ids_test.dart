/// 데모 API 의 AI 대화 메시지 식별자와 요청 키(#3352).
///
/// 실서버는 저장한 질문·답 두 줄의 식별자·저장 시각·멱등키를 응답과 저장된 대화에
/// 함께 싣는다. 데모도 같은 모양으로 답해야 화면이 같은 길로 두 쪽을 맞춘다.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/ai_coach/data/repositories/dio_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      LocalApiInterceptor(
        db,
        Logger(level: Level.off),
        points: DemoPointsLedger(openingBalance: 1000),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<Map<String, Object?>> chat(String message, {String? key}) async =>
      (await dio.post<Map<String, Object?>>(
        '/ai-coach/chat',
        data: <String, Object?>{'message': message, 'client_request_id': ?key},
      )).data!;

  Future<List<Map<String, Object?>>> stored() async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/ai-coach/messages');
    return <Map<String, Object?>>[
      for (final Object? m in res.data!['messages']! as List<Object?>)
        (m! as Map<Object?, Object?>).cast<String, Object?>(),
    ];
  }

  test('응답의 식별자·시각·키가 저장된 두 줄과 같다', () async {
    final Map<String, Object?> body = await chat('오늘 뭐 먹을까요', key: 'k1');

    final List<Map<String, Object?>> rows = await stored();
    final Map<String, Object?> question = rows[rows.length - 2];
    final Map<String, Object?> answer = rows.last;
    expect(question['role'], 'user');
    expect(answer['role'], 'coach');
    expect(body['user_message_id'], question['id']);
    expect(body['reply_message_id'], answer['id']);
    expect(body['user_message_id'], isNot(body['reply_message_id']));
    expect(body['user_created_at'], question['created_at']);
    expect(body['reply_created_at'], answer['created_at']);
    expect(body['client_request_id'], 'k1');
    expect(question['client_request_id'], 'k1');
    expect(answer['client_request_id'], 'k1');
  });

  test('같은 키로 다시 보내면 같은 두 줄을 가리키고 한 쌍 더 저장하지 않는다', () async {
    final Map<String, Object?> first = await chat('오늘 뭐 먹을까요', key: 'k1');
    final int before = (await stored()).length;

    final Map<String, Object?> again = await chat('오늘 뭐 먹을까요', key: 'k1');

    expect(again['user_message_id'], first['user_message_id']);
    expect(again['reply_message_id'], first['reply_message_id']);
    expect((await stored()).length, before);
  });

  test('같은 글을 다른 키로 보내면 서로 다른 줄이다', () async {
    final Map<String, Object?> first = await chat('네', key: 'k1');
    final Map<String, Object?> second = await chat('네', key: 'k2');

    expect(second['user_message_id'], isNot(first['user_message_id']));
    final List<Map<String, Object?>> rows = await stored();
    expect(
      <Object?>[
        for (final Map<String, Object?> m in rows)
          if (m['role'] == 'user' && m['content'] == '네')
            m['client_request_id'],
      ],
      <Object?>['k1', 'k2'],
    );
  });

  test('키 없이 보내도 식별자는 받는다', () async {
    final Map<String, Object?> body = await chat('오늘 뭐 먹을까요');

    final List<Map<String, Object?>> rows = await stored();
    expect(body['client_request_id'], isNull);
    expect(body['user_message_id'], rows[rows.length - 2]['id']);
    expect(body['reply_message_id'], rows.last['id']);
    expect(rows.last['client_request_id'], isNull);
  });

  test('시드 대화도 줄마다 식별자가 있고 서로 겹치지 않는다', () async {
    final List<Map<String, Object?>> rows = await stored();

    expect(rows, isNotEmpty);
    expect(rows.every((Map<String, Object?> m) => m['id'] is String), isTrue);
    expect(<Object?>{
      for (final Map<String, Object?> m in rows) m['id'],
    }, hasLength(rows.length));
  });

  test('예전 시드처럼 식별자가 겹치는 저장분은 줄 순서대로 다시 매겨 저장한다', () async {
    // 이미 데모를 켜 본 기기 — 같은 날 주고받은 줄이 같은 식별자를 갖고 있다.
    Map<String, Object?> row(String id, String role, String text) =>
        <String, Object?>{
          'id': id,
          'role': role,
          'text': text,
          'sources': const <String>[],
          'created_at': DateTime(2026, 10, 1, 9).toIso8601String(),
        };
    await db.putValue(
      'ai_coach_user_messages_v3',
      jsonEncode(<Map<String, Object?>>[
        row('local-ai-seed-3-me', 'user', '첫 질문'),
        row('local-ai-seed-3-coach', 'coach', '첫 답'),
        row('local-ai-seed-3-me', 'user', '둘째 질문'),
        row('local-ai-seed-3-coach', 'coach', '둘째 답'),
      ]),
    );

    final List<Map<String, Object?>> rows = await stored();

    expect(
      <Object?>[for (final Map<String, Object?> m in rows) m['content']],
      <Object?>['첫 질문', '첫 답', '둘째 질문', '둘째 답'],
    );
    expect(<Object?>{
      for (final Map<String, Object?> m in rows) m['id'],
    }, hasLength(4));
    // 처음 나온 줄의 식별자는 그대로다.
    expect(rows[0]['id'], 'local-ai-seed-3-me');
    expect(rows[1]['id'], 'local-ai-seed-3-coach');
    // 다시 매긴 값이 저장돼, 다음에 읽어도 같은 식별자다.
    expect(
      <Object?>[for (final Map<String, Object?> m in await stored()) m['id']],
      <Object?>[for (final Map<String, Object?> m in rows) m['id']],
    );
  });

  test('저장소가 데모 응답의 식별자를 그대로 읽는다', () async {
    final DioAiCoachRepository repo = DioAiCoachRepository(dio);

    final ChatMessage reply = await repo.sendMessage(
      message: '오늘 뭐 먹을까요',
      history: const <ChatMessage>[],
      clientRequestId: 'k1',
    );
    final List<ChatMessage> history = await repo.fetchHistory();

    expect(reply.id, history.last.id);
    expect(reply.questionId, history[history.length - 2].id);
    expect(reply.clientRequestId, 'k1');
    expect(history.last.clientRequestId, 'k1');
    expect(reply.at, history.last.at);
  });
}

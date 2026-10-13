/// AI 코치 REST 계약 — 백엔드 실응답 형태를 그대로 넣어 필드명 어긋남을 잡는다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/ai_coach/data/repositories/dio_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.status = 200});

  final String body;
  final int status;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_StubAdapter adapter) {
  // 전역 기본값을 앱과 같게 둔다 — 채팅만 더 긴 타임아웃을 쓰는지 확인해야 하므로.
  final dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 15)))
    ..httpClientAdapter = adapter;
  return dio;
}

void main() {
  test('저장된 대화를 role/content/sources 로 복원한다', () async {
    final adapter = _StubAdapter(
      '{"messages":['
      '{"role":"user","content":"나트륨 줄이는 법","sources":[],'
      '"created_at":"2026-08-08T10:00:00Z"},'
      '{"role":"coach","content":"국물을 남겨보세요","sources":["나트륨 줄이기"],'
      '"created_at":"2026-08-08T10:00:01Z"}]}',
    );
    final repo = DioAiCoachRepository(_dioWith(adapter));

    final history = await repo.fetchHistory();

    expect(history.length, 2);
    expect(history.first.isUser, isTrue);
    expect(history.first.content, '나트륨 줄이는 법');
    expect(history.last.role, ChatRole.coach);
    expect(history.last.sources, <String>['나트륨 줄이기']);
    expect(adapter.lastRequest?.path, '/ai-coach/messages');
  });

  test('빈 히스토리도 정상 처리한다', () async {
    final repo = DioAiCoachRepository(
      _dioWith(_StubAdapter('{"messages":[]}')),
    );
    expect(await repo.fetchHistory(), isEmpty);
  });

  test('채팅은 전역 15초가 아니라 더 긴 타임아웃을 쓴다', () async {
    // 코치 답변은 RAG + Gemini 라 실측 7.6~12.8초였다. 15초면 배포 후 정기적으로
    // 넘고, 서버는 답변을 저장하므로 사용자는 실패를 본 뒤 다음에 열었을 때
    // 본 적 없는 답변을 발견하게 된다.
    final adapter = _StubAdapter('{"reply":"네","sources":[]}');
    final repo = DioAiCoachRepository(_dioWith(adapter));

    await repo.sendMessage(message: '안녕', history: const <ChatMessage>[]);

    final timeout = adapter.lastRequest?.receiveTimeout;
    expect(timeout, isNotNull);
    expect(timeout! > const Duration(seconds: 15), isTrue);
  });

  test('코칭 피드백은 서버의 두 코치 호출 상한보다 길게 기다린다', () async {
    // #2813: 서버는 식단·운동 코치를 차례로 부르고 각 호출 상한이 30초다. 전역
    // 15초에서 끊기면 정상 응답도 실패가 되어 코칭 시트가 오류에 머문다.
    final adapter = _StubAdapter('{"greeting":"안녕하세요","suggestions":[]}');
    final repo = DioAiCoachRepository(_dioWith(adapter));

    await repo.fetchState();

    expect(adapter.lastRequest?.path, '/ai-coach/feedback');
    final timeout = adapter.lastRequest?.receiveTimeout;
    expect(timeout, DioAiCoachRepository.feedbackTimeout);
    expect(timeout! >= const Duration(seconds: 60), isTrue);
  });

  test('코치 답변의 근거를 그대로 싣는다', () async {
    final adapter = _StubAdapter(
      '{"reply":"국물을 남겨보세요",'
      '"sources":["2025 한국인 영양소 섭취기준 · 보건복지부/한국영양학회 — 나트륨과 염소"]}',
    );
    final repo = DioAiCoachRepository(_dioWith(adapter));

    final reply = await repo.sendMessage(
      message: '나트륨',
      history: const <ChatMessage>[],
    );

    expect(reply.role, ChatRole.coach);
    expect(reply.content, '국물을 남겨보세요');
    expect(
      reply.sources,
      contains('2025 한국인 영양소 섭취기준 · 보건복지부/한국영양학회 — 나트륨과 염소'),
    );
  });

  group('메시지 식별자와 요청 키 (#3352)', () {
    test('저장된 대화의 식별자와 키를 읽는다', () async {
      final adapter = _StubAdapter(
        '{"messages":['
        '{"id":"aimsg-q","role":"user","content":"네","sources":[],'
        '"created_at":"2026-08-08T10:00:00Z","client_request_id":"k1"},'
        '{"id":"aimsg-a","role":"coach","content":"좋아요","sources":[],'
        '"created_at":"2026-08-08T10:00:00Z","client_request_id":"k1"}]}',
      );
      final repo = DioAiCoachRepository(_dioWith(adapter));

      final history = await repo.fetchHistory();

      expect(history.first.id, 'aimsg-q');
      expect(history.last.id, 'aimsg-a');
      expect(history.first.clientRequestId, 'k1');
      expect(history.last.clientRequestId, 'k1');
    });

    test('식별자·키를 주지 않는 예전 응답도 그대로 읽는다', () async {
      final adapter = _StubAdapter(
        '{"messages":[{"role":"user","content":"네","sources":[],'
        '"created_at":"2026-08-08T10:00:00Z"}]}',
      );
      final repo = DioAiCoachRepository(_dioWith(adapter));

      final history = await repo.fetchHistory();

      expect(history.single.id, isNull);
      expect(history.single.clientRequestId, isNull);
      expect(history.single.at, isNotNull);
    });

    test('답에 실려 온 두 줄의 식별자·시각·키를 읽는다', () async {
      final adapter = _StubAdapter(
        '{"reply":"좋아요","sources":[],'
        '"user_message_id":"aimsg-q","user_created_at":"2026-08-08T10:00:00Z",'
        '"reply_message_id":"aimsg-a","reply_created_at":"2026-08-08T10:00:00Z",'
        '"client_request_id":"k1"}',
      );
      final repo = DioAiCoachRepository(_dioWith(adapter));

      final reply = await repo.sendMessage(
        message: '네',
        history: const <ChatMessage>[],
        clientRequestId: 'k1',
      );

      expect(reply.id, 'aimsg-a');
      expect(reply.questionId, 'aimsg-q');
      expect(reply.clientRequestId, 'k1');
      // 서버 시각은 KST 벽시계로 읽는다 — 10:00Z 는 19:00 이다.
      expect(reply.at?.hour, 19);
      expect(reply.questionAt, reply.at);
    });

    test('식별자가 없는 예전 답은 비워 둔다', () async {
      final repo = DioAiCoachRepository(
        _dioWith(_StubAdapter('{"reply":"좋아요","sources":[]}')),
      );

      final reply = await repo.sendMessage(
        message: '네',
        history: const <ChatMessage>[],
      );

      expect(reply.id, isNull);
      expect(reply.questionId, isNull);
      expect(reply.at, isNull);
    });

    test('409 in_progress 는 처리 중으로 던진다', () async {
      final repo = DioAiCoachRepository(
        _dioWith(
          _StubAdapter(
            '{"detail":{"code":"in_progress","message":"같은 메시지에 답하는 중이에요."}}',
            status: 409,
          ),
        ),
      );

      await expectLater(
        repo.sendMessage(
          message: '네',
          history: const <ChatMessage>[],
          clientRequestId: 'k1',
        ),
        throwsA(isA<AiChatInProgress>()),
      );
    });

    test('409 insufficient_points 는 여전히 한도 거절이다', () async {
      final repo = DioAiCoachRepository(
        _dioWith(
          _StubAdapter(
            '{"detail":{"code":"insufficient_points","message":"","shortfall":20}}',
            status: 409,
          ),
        ),
      );

      await expectLater(
        repo.sendMessage(message: '네', history: const <ChatMessage>[]),
        throwsA(
          isA<AiChatBlocked>().having(
            (AiChatBlocked b) => b.shortfall,
            'shortfall',
            20,
          ),
        ),
      );
    });
  });
}

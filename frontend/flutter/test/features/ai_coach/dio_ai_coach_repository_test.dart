/// AI 코치 REST 계약 — 백엔드 실응답 형태를 그대로 넣어 필드명 어긋남을 잡는다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/ai_coach/data/repositories/dio_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final String body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async {
    lastRequest = options;
    return ResponseBody.fromString(
      body,
      200,
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
  final dio = Dio(
    BaseOptions(receiveTimeout: const Duration(seconds: 15)),
  )..httpClientAdapter = adapter;
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
    final repo = DioAiCoachRepository(_dioWith(_StubAdapter('{"messages":[]}')));
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
}

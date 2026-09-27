/// AI 코치 요청 크기 한도(#1549) — 입력칸·보내는 history·실제 요청 본문.
///
/// 서버는 질문 1000자·history 20턴·턴당 2000자를 넘는 요청을 422 로 거절한다.
/// 앱이 먼저 맞춰 보내야 회원이 쓴 대화가 한도 때문에 실패하지 않는다.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/ai_coach/data/repositories/dio_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/ai_coach_limits.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import 'free_quota.dart';

class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  Map<String, Object?> get sentBody {
    final Object? data = lastRequest!.data;
    return (data is String ? jsonDecode(data) : data)! as Map<String, Object?>;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async {
    lastRequest = options;
    return ResponseBody.fromString(
      '{"reply":"네","sources":[]}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 보낸 질문과 history 를 기록하는 저장소.
class _RecordingRepository implements AiCoachRepository {
  final List<String> messages = <String>[];
  final List<List<ChatMessage>> histories = <List<ChatMessage>>[];

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<void> dismissInsight(String messageId) async {}

  @override
  Future<AiChatQuota> fetchQuota() async => kFreeQuota;

  @override
  Future<ChatInsightHistory> fetchInsights() async =>
      const ChatInsightHistory();

  @override
  Future<List<ChatMessage>> fetchHistory() async => const <ChatMessage>[];

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
    bool payWithPoints = false,
    String? clientRequestId,
  }) async {
    messages.add(message);
    histories.add(history);
    return const ChatMessage(role: ChatRole.coach, content: '네');
  }
}

List<ChatMessage> _conversation(int n, {String Function(int i)? content}) =>
    <ChatMessage>[
      for (int i = 0; i < n; i++)
        ChatMessage(
          role: i.isEven ? ChatRole.user : ChatRole.coach,
          content: content?.call(i) ?? '턴 $i',
        ),
    ];

void main() {
  group('한도 값', () {
    test('서버 ChatRequest 와 같은 값이다', () {
      expect(AiCoachLimits.messageMaxLength, 1000);
      expect(AiCoachLimits.historyMaxTurns, 20);
      expect(AiCoachLimits.turnMaxLength, 2000);
    });
  });

  group('보내는 history', () {
    test('한도 이하면 그대로 보낸다', () {
      final payload = aiCoachHistoryPayload(_conversation(3));

      expect(payload, <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'content': '턴 0'},
        <String, Object?>{'role': 'coach', 'content': '턴 1'},
        <String, Object?>{'role': 'user', 'content': '턴 2'},
      ]);
    });

    test('빈 대화는 빈 목록이다', () {
      expect(aiCoachHistoryPayload(const <ChatMessage>[]), isEmpty);
    });

    test('정확히 20턴이면 하나도 버리지 않는다', () {
      final payload = aiCoachHistoryPayload(_conversation(20));

      expect(payload, hasLength(20));
      expect(payload.first['content'], '턴 0');
    });

    test('20턴을 넘으면 최근 20턴만 순서대로 보낸다', () {
      final payload = aiCoachHistoryPayload(_conversation(25));

      expect(payload, hasLength(AiCoachLimits.historyMaxTurns));
      expect(payload.first['content'], '턴 5');
      expect(payload.last['content'], '턴 24');
    });

    test('긴 코치 답변은 2000자까지만 보낸다', () {
      final payload = aiCoachHistoryPayload(
        _conversation(2, content: (int i) => i == 1 ? '가' * 2500 : '짧음'),
      );

      expect(payload[0]['content'], '짧음');
      expect(payload[1]['content'], '가' * 2000);
    });

    test('정확히 2000자인 턴은 자르지 않는다', () {
      final payload = aiCoachHistoryPayload(
        _conversation(1, content: (_) => 'a' * 2000),
      );

      expect(payload.single['content'], 'a' * 2000);
    });

    test('자를 때 서버처럼 코드 포인트로 센다', () {
      // 😀 는 UTF-16 두 칸이지만 서버(파이썬)는 한 글자로 센다.
      final payload = aiCoachHistoryPayload(
        _conversation(1, content: (_) => '😀' * 2100),
      );

      final String sent = payload.single['content']! as String;
      expect(sent.runes.length, 2000);
      expect(sent, '😀' * 2000);
    });

    test('화면의 대화는 건드리지 않는다', () {
      final List<ChatMessage> history = _conversation(25);

      aiCoachHistoryPayload(history);

      expect(history, hasLength(25));
    });
  });

  group('보내는 질문', () {
    test('한도 이하면 그대로다', () {
      expect(aiCoachMessagePayload('안녕'), '안녕');
      expect(aiCoachMessagePayload('a' * 1000), 'a' * 1000);
    });

    test('코드 포인트로 1000을 넘으면 1000까지 맞춘다', () {
      // 입력칸은 화면 글자로 세므로 여러 코드 포인트로 된 이모지가 섞이면
      // 서버가 세는 길이가 한도를 넘을 수 있다.
      final String sent = aiCoachMessagePayload('👍🏻' * 600);

      expect(sent.runes.length, 1000);
    });
  });

  group('실제 요청 본문', () {
    test('긴 대화는 최근 20턴·턴당 2000자로 잘려 나간다', () async {
      final adapter = _CapturingAdapter();
      final repo = DioAiCoachRepository(Dio()..httpClientAdapter = adapter);

      await repo.sendMessage(
        message: '다음엔 뭘 먹을까요?',
        history: _conversation(
          30,
          content: (int i) => i == 29 ? '나' * 3000 : '턴 $i',
        ),
      );

      final Map<String, Object?> body = adapter.sentBody;
      final List<Object?> history = body['history']! as List<Object?>;
      expect(history, hasLength(20));
      expect((history.first! as Map<String, Object?>)['content'], '턴 10');
      expect((history.last! as Map<String, Object?>)['content'], '나' * 2000);
      expect(body['message'], '다음엔 뭘 먹을까요?');
    });

    test('짧은 대화는 예전과 같은 모양으로 나간다', () async {
      final adapter = _CapturingAdapter();
      final repo = DioAiCoachRepository(Dio()..httpClientAdapter = adapter);

      await repo.sendMessage(message: 'q', history: _conversation(2));

      expect(adapter.sentBody['history'], <Object?>[
        <String, Object?>{'role': 'user', 'content': '턴 0'},
        <String, Object?>{'role': 'coach', 'content': '턴 1'},
      ]);
    });

    test('질문도 서버 한도 안으로 나간다', () async {
      final adapter = _CapturingAdapter();
      final repo = DioAiCoachRepository(Dio()..httpClientAdapter = adapter);

      await repo.sendMessage(
        message: '👍🏻' * 600,
        history: const <ChatMessage>[],
      );

      expect((adapter.sentBody['message']! as String).runes.length, 1000);
    });
  });

  group('입력칸', () {
    Future<_RecordingRepository> pumpPage(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _RecordingRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            aiCoachRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AICoachPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    final Finder counter = find.byKey(
      const ValueKey<String>('chat-input-length-counter'),
    );

    testWidgets('1000자를 넘는 글은 입력되지 않는다', (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), '가' * 1200);
      await tester.pump();

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, AiCoachLimits.messageMaxLength);
      expect(field.controller!.text, '가' * 1000);
    });

    testWidgets('평소에는 글자 수를 보이지 않는다', (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), '오늘 저녁 뭐 먹을까요?');
      await tester.pump();

      expect(counter, findsNothing);
    });

    testWidgets('한도에 가까워지면 글자 수를 보인다', (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), 'a' * 950);
      await tester.pump();

      expect(find.text('950/1000'), findsOneWidget);
    });

    testWidgets('한도까지 쓴 질문이 그대로 보내진다', (WidgetTester tester) async {
      final repo = await pumpPage(tester);

      await tester.enterText(find.byType(TextField), '가' * 1200);
      await tester.pump();
      await tester.tap(find.byTooltip('메시지 보내기'));
      await tester.pumpAndSettle();

      expect(repo.messages.single, '가' * 1000);
      expect(counter, findsNothing);
    });
  });
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/ai_coach/data/repositories/dio_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/data/repositories/mock_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';
import 'package:oncare/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// AI 챗봇 통증·부정적 반응 감지 — 응답 파싱, 메시지 표시, 감지 기록 창(#1824).

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

class _InsightRepo implements AiCoachRepository {
  _InsightRepo({
    this.history = const ChatInsightHistory(),
    this.withStoredChat = true,
  });

  final ChatInsightHistory history;

  /// 저장된 대화를 돌려줄지. 컨트롤러 테스트는 복원이 보낸 메시지를 덮지 않게 끈다.
  final bool withStoredChat;
  int insightCalls = 0;

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<List<ChatMessage>> fetchHistory() async => !withStoredChat
      ? const <ChatMessage>[]
      : const <ChatMessage>[
          ChatMessage(
            role: ChatRole.user,
            content: '어제부터 허리가 뻐근해요',
            insight: ChatInsight(
              kind: ChatInsightKind.discomfort,
              bodyPart: '허리',
            ),
          ),
          ChatMessage(role: ChatRole.coach, content: '스트레칭부터 해 보세요'),
        ];

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
  }) async => const ChatMessage(
    role: ChatRole.coach,
    content: '쉬어 가세요',
    replyToInsight: ChatInsight(
      kind: ChatInsightKind.discomfort,
      bodyPart: '무릎',
    ),
  );

  @override
  Future<ChatInsightHistory> fetchInsights() async {
    insightCalls += 1;
    return history;
  }
}

Future<void> _pumpPage(WidgetTester tester, AiCoachRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[aiCoachRepositoryProvider.overrideWithValue(repo)],
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
}

void main() {
  group('응답 파싱', () {
    test('저장된 대화의 회원 메시지 감지와 코치 답의 감지를 읽는다', () async {
      final repo = DioAiCoachRepository(
        Dio()
          ..httpClientAdapter = _StubAdapter(
            '{"messages":['
            '{"role":"user","content":"무릎이 아파요","sources":[],'
            '"created_at":"2026-09-16T10:00:00Z",'
            '"insight":{"kind":"discomfort","body_part":"무릎"}},'
            '{"role":"coach","content":"쉬어 가세요","sources":[],'
            '"created_at":"2026-09-16T10:00:01Z","insight":null}]}',
          ),
      );
      final history = await repo.fetchHistory();
      expect(
        history.first.insight,
        const ChatInsight(kind: ChatInsightKind.discomfort, bodyPart: '무릎'),
      );
      expect(history.last.insight, isNull);
    });

    test('채팅 답에 실린 방금 보낸 메시지의 감지를 읽는다', () async {
      final adapter = _StubAdapter(
        '{"reply":"괜찮아요","sources":[],'
        '"user_insight":{"kind":"negative_feedback","body_part":null}}',
      );
      final repo = DioAiCoachRepository(Dio()..httpClientAdapter = adapter);
      final reply = await repo.sendMessage(
        message: '못 했어요',
        history: const <ChatMessage>[],
      );
      expect(
        reply.replyToInsight,
        const ChatInsight(kind: ChatInsightKind.negativeFeedback),
      );
    });

    test('감지 기록은 기간·종류·부위·원문을 읽고 모르는 종류는 버린다', () async {
      final adapter = _StubAdapter(
        '{"window_days":30,"insights":['
        '{"message_id":"m1","created_at":"2026-09-15T09:00:00Z","kind":"discomfort",'
        '"body_part":"허리","text":"허리가 뻐근해요"},'
        '{"message_id":"m2","created_at":"2026-09-14T09:00:00Z","kind":"brand_new",'
        '"body_part":null,"text":"?"}]}',
      );
      final repo = DioAiCoachRepository(Dio()..httpClientAdapter = adapter);
      final history = await repo.fetchInsights();
      expect(adapter.lastRequest?.path, '/ai-coach/insights');
      expect(history.windowDays, 30);
      expect(history.records, hasLength(1));
      expect(history.records.single.text, '허리가 뻐근해요');
      expect(history.records.single.insight.bodyPart, '허리');
    });
  });

  test('보낸 메시지에 답에 실린 감지를 붙인다', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        aiCoachRepositoryProvider.overrideWithValue(
          _InsightRepo(withStoredChat: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(chatControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await container.read(chatControllerProvider.notifier).send('무릎이 아파요');
    final ChatState state = container.read(chatControllerProvider);
    final ChatMessage mine = state.messages.lastWhere((m) => m.isUser);
    expect(mine.content, '무릎이 아파요');
    expect(
      mine.insight,
      const ChatInsight(kind: ChatInsightKind.discomfort, bodyPart: '무릎'),
    );
  });

  testWidgets('감지된 회원 메시지 아래에 짧은 표시가 붙는다', (tester) async {
    await _pumpPage(tester, _InsightRepo());
    expect(find.text('어제부터 허리가 뻐근해요'), findsOneWidget);
    final Finder tag = find.byKey(const Key('aiCoachInsightTag'));
    expect(tag, findsOneWidget);
    expect(
      find.descendant(of: tag, matching: find.text('허리 통증 감지')),
      findsOneWidget,
    );
    // 말풍선 아래에 있다.
    expect(
      tester.getTopLeft(tag).dy,
      greaterThan(tester.getTopLeft(find.text('어제부터 허리가 뻐근해요')).dy),
    );
  });

  testWidgets('오른쪽 위 감지 기록 버튼이 최근 30일 기록을 보여 준다', (tester) async {
    final repo = _InsightRepo(
      history: ChatInsightHistory(
        records: <ChatInsightRecord>[
          ChatInsightRecord(
            messageId: 'm1',
            createdAt: DateTime(2026, 9, 15, 9),
            insight: const ChatInsight(
              kind: ChatInsightKind.discomfort,
              bodyPart: '허리',
            ),
            text: '허리가 뻐근해요',
          ),
          ChatInsightRecord(
            messageId: 'm2',
            createdAt: DateTime(2026, 9, 10, 9),
            insight: const ChatInsight(kind: ChatInsightKind.negativeFeedback),
            text: '너무 힘들어서 못 했어요',
          ),
        ],
      ),
    );
    await _pumpPage(tester, repo);

    await tester.tap(find.byKey(const Key('aiCoachInsightHistoryButton')));
    await tester.pumpAndSettle();

    final Finder sheet = find.byKey(const Key('aiCoachInsightHistorySheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('감지 기록')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('최근 30일')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('aiCoachInsightRow-m1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('부정적 반응 감지')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('너무 힘들어서 못 했어요')),
      findsOneWidget,
    );
    expect(repo.insightCalls, 1);
  });

  testWidgets('감지 기록이 없으면 빈 안내를 보인다', (tester) async {
    await _pumpPage(tester, _InsightRepo());
    await tester.tap(find.byKey(const Key('aiCoachInsightHistoryButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aiCoachInsightHistoryEmpty')), findsOneWidget);
    expect(find.text('최근 30일 동안 감지된 내용이 없어요'), findsOneWidget);
  });

  test('목업 저장소는 이번 세션에 보낸 메시지로 기록을 만든다', () async {
    final repo = MockAiCoachRepository();
    final reply = await repo.sendMessage(
      message: '발목이 좀 부었어요',
      history: const <ChatMessage>[],
    );
    await repo.sendMessage(
      message: '오늘 샐러드 먹었어요',
      history: const <ChatMessage>[],
    );
    expect(reply.replyToInsight?.bodyPart, '발목');
    final history = await repo.fetchInsights();
    expect(history.records.map((r) => r.text), <String>['발목이 좀 부었어요']);
  });

  group('로컬 목업 서버', () {
    late AppDatabase db;
    late Dio dio;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
    });
    tearDown(() async {
      await db.close();
      dio.close();
    });

    test('채팅 답에 감지를 싣고, 기록은 30일 안의 감지된 메시지만 최신순이다', () async {
      // 31일 전 메시지를 미리 둔다 — 기록에서 빠져야 한다.
      await db.putValue(
        'ai_coach_user_messages',
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'old',
            'text': '어깨가 아파요',
            'created_at': nowKst()
                .subtract(const Duration(days: 31))
                .toIso8601String(),
          },
        ]),
      );

      final chat = await dio.post<Map<String, Object?>>(
        '/ai-coach/chat',
        data: <String, Object?>{'message': '무릎이 아파요', 'history': <Object?>[]},
      );
      expect(chat.data!['user_insight'], <String, Object?>{
        'kind': 'discomfort',
        'body_part': '무릎',
      });
      await dio.post<Map<String, Object?>>(
        '/ai-coach/chat',
        data: <String, Object?>{
          'message': '너무 힘들어서 못 했어요',
          'history': <Object?>[],
        },
      );

      final listed = await dio.get<Map<String, Object?>>('/ai-coach/insights');
      final rows = (listed.data!['insights']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(listed.data!['window_days'], 30);
      expect(rows.map((r) => r['text']), <String>['너무 힘들어서 못 했어요', '무릎이 아파요']);
      expect(rows.last['body_part'], '무릎');
    });
  });
}

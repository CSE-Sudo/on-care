/// AI 코치 대화 복원이 끝나기 전에 보낸 질문. (#2642)
///
/// 화면을 열면 서버에 저장된 이전 대화를 불러온다. 예전에는 복원이 끝나는 순간
/// 목록을 복원분으로 통째로 바꿔, 그 사이 보낸 질문과 `답 생성 중` 말풍선이
/// 사라지고 뒤이어 온 답만 남았다. 복원분은 앞, 새 대화는 뒤에 남아야 한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';
import 'package:oncare/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show keepWords;

import 'free_quota.dart';

const ChatMessage _yesterdayQuestion = ChatMessage(
  role: ChatRole.user,
  content: '어제 물어본 것',
);
const ChatMessage _yesterdayAnswer = ChatMessage(
  role: ChatRole.coach,
  content: '어제 답변',
);

/// 복원과 답을 손으로 풀어 주는 저장소.
class _GatedRepository implements AiCoachRepository {
  final Completer<List<ChatMessage>> history = Completer<List<ChatMessage>>();
  Completer<ChatMessage> reply = Completer<ChatMessage>();

  /// 보낸 질문들 — 복원 중 버튼이 정말 잠겼는지 본다.
  final List<String> sent = <String>[];

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
  Future<List<ChatMessage>> fetchHistory() => history.future;

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
    bool payWithPoints = false,
    String? clientRequestId,
  }) {
    sent.add(message);
    return reply.future;
  }
}

ProviderContainer _container(AiCoachRepository repository) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      aiCoachRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _flush() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<String> _contents(ChatState state) => <String>[
  for (final ChatMessage m in state.messages) m.content,
];

void main() {
  group('합치기 규칙', () {
    const ChatMessage welcome = ChatMessage(
      role: ChatRole.coach,
      content: '',
      notice: ChatNotice.welcome,
    );
    const ChatMessage question = ChatMessage(
      role: ChatRole.user,
      content: '오늘 뭐 먹을까요',
    );
    const ChatMessage pending = ChatMessage(
      role: ChatRole.coach,
      content: '',
      pending: true,
    );

    test('복원분이 없으면 지금 모습 그대로다', () {
      expect(
        mergeRestoredChat(const <ChatMessage>[], const <ChatMessage>[welcome]),
        const <ChatMessage>[welcome],
      );
    });

    test('복원분이 인사 말풍선을 대신한다', () {
      expect(
        mergeRestoredChat(
          const <ChatMessage>[_yesterdayQuestion, _yesterdayAnswer],
          const <ChatMessage>[welcome],
        ),
        const <ChatMessage>[_yesterdayQuestion, _yesterdayAnswer],
      );
    });

    test('복원 중에 보낸 질문과 대기 말풍선은 복원분 뒤에 남는다', () {
      expect(
        mergeRestoredChat(
          const <ChatMessage>[_yesterdayQuestion, _yesterdayAnswer],
          const <ChatMessage>[question, pending],
        ),
        const <ChatMessage>[
          _yesterdayQuestion,
          _yesterdayAnswer,
          question,
          pending,
        ],
      );
    });

    test('실패 안내처럼 앱이 띄운 다른 말풍선은 거두지 않는다', () {
      const ChatMessage failure = ChatMessage(
        role: ChatRole.coach,
        content: '',
        notice: ChatNotice.failure,
      );
      expect(
        mergeRestoredChat(
          const <ChatMessage>[_yesterdayAnswer],
          const <ChatMessage>[question, failure],
        ),
        const <ChatMessage>[_yesterdayAnswer, question, failure],
      );
    });
  });

  group('컨트롤러', () {
    test('열자마자는 복원 중이다', () {
      final ProviderContainer container = _container(_GatedRepository());

      expect(container.read(chatControllerProvider).restoring, isTrue);
    });

    test('복원이 끝나면 복원 중 표시가 내려간다', () async {
      final _GatedRepository repository = _GatedRepository();
      final ProviderContainer container = _container(repository);
      container.read(chatControllerProvider);

      repository.history.complete(const <ChatMessage>[_yesterdayAnswer]);
      await _flush();

      final ChatState state = container.read(chatControllerProvider);
      expect(state.restoring, isFalse);
      expect(_contents(state), <String>['어제 답변']);
    });

    test('복원이 실패해도 복원 중 표시가 내려가고 인사로 시작한다', () async {
      final _GatedRepository repository = _GatedRepository();
      final ProviderContainer container = _container(repository);
      container.read(chatControllerProvider);

      repository.history.completeError(Exception('history unavailable'));
      await _flush();

      final ChatState state = container.read(chatControllerProvider);
      expect(state.restoring, isFalse);
      expect(state.messages.single.notice, ChatNotice.welcome);
    });

    test('저장된 대화가 없어도 복원 중 표시가 내려간다', () async {
      final _GatedRepository repository = _GatedRepository();
      final ProviderContainer container = _container(repository);
      container.read(chatControllerProvider);

      repository.history.complete(const <ChatMessage>[]);
      await _flush();

      final ChatState state = container.read(chatControllerProvider);
      expect(state.restoring, isFalse);
      expect(state.messages.single.notice, ChatNotice.welcome);
    });

    test('복원 전에 보낸 질문이 복원 뒤에도 남고, 답이 그 아래 붙는다', () async {
      final _GatedRepository repository = _GatedRepository();
      final ProviderContainer container = _container(repository);
      final ChatController controller = container.read(
        chatControllerProvider.notifier,
      );
      await _flush();

      final Future<ChatSendResult> sending = controller.send('오늘 뭐 먹을까요');
      await _flush();
      // 복원이 먼저 끝난다 — 예전에는 여기서 질문과 대기 말풍선이 지워졌다.
      repository.history.complete(const <ChatMessage>[
        _yesterdayQuestion,
        _yesterdayAnswer,
      ]);
      await _flush();

      ChatState state = container.read(chatControllerProvider);
      expect(_contents(state).take(3), <String>[
        '어제 물어본 것',
        '어제 답변',
        '오늘 뭐 먹을까요',
      ]);
      expect(state.messages.last.pending, isTrue);

      repository.reply.complete(
        const ChatMessage(role: ChatRole.coach, content: '닭가슴살 샐러드요'),
      );
      await sending;

      state = container.read(chatControllerProvider);
      expect(_contents(state), <String>[
        '어제 물어본 것',
        '어제 답변',
        '오늘 뭐 먹을까요',
        '닭가슴살 샐러드요',
      ]);
      expect(state.messages.any((ChatMessage m) => m.pending), isFalse);
    });

    test('복원이 답보다 늦게 끝나도 질문과 답이 복원분 뒤에 남는다', () async {
      final _GatedRepository repository = _GatedRepository();
      final ProviderContainer container = _container(repository);
      final ChatController controller = container.read(
        chatControllerProvider.notifier,
      );
      await _flush();

      final Future<ChatSendResult> sending = controller.send('오늘 뭐 먹을까요');
      repository.reply.complete(
        const ChatMessage(role: ChatRole.coach, content: '닭가슴살 샐러드요'),
      );
      await sending;
      repository.history.complete(const <ChatMessage>[_yesterdayAnswer]);
      await _flush();

      expect(_contents(container.read(chatControllerProvider)), <String>[
        '어제 답변',
        '오늘 뭐 먹을까요',
        '닭가슴살 샐러드요',
      ]);
    });

    test('보내다 한도에 걸려도 그 사이 끝난 복원분은 남는다', () async {
      final _GatedRepository repository = _GatedRepository();
      final ProviderContainer container = _container(repository);
      final ChatController controller = container.read(
        chatControllerProvider.notifier,
      );
      await _flush();

      final Future<ChatSendResult> sending = controller.send('오늘 뭐 먹을까요');
      repository.history.complete(const <ChatMessage>[_yesterdayAnswer]);
      await _flush();
      repository.reply.completeError(
        const AiChatBlocked(AiChatBlockReason.dailyLimit),
      );
      final ChatSendResult result = await sending;

      expect(result.outcome, ChatSendOutcome.dailyLimit);
      expect(_contents(container.read(chatControllerProvider)), <String>[
        '어제 답변',
      ]);
    });
  });

  group('화면', () {
    Future<_GatedRepository> pumpPage(WidgetTester tester) async {
      final _GatedRepository repository = _GatedRepository();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            aiCoachRepositoryProvider.overrideWithValue(repository),
            // 담당 트레이너가 없는 회원 — AI 코치 대화가 열린다.
            memberCoachProvider.overrideWith((ref) async => null),
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
      // 복원은 붙잡혀 있어 로딩이 돈다 — 멈출 때까지 기다리지 않고 몇 프레임만.
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return repository;
    }

    testWidgets('복원 중에는 로딩이 보이고 빠른 질문이 눌리지 않는다', (tester) async {
      final _GatedRepository repository = await pumpPage(tester);
      final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

      expect(find.byKey(const Key('aiCoachRestoring')), findsOneWidget);
      expect(find.text(l.aicQuickReply1), findsOneWidget);

      await tester.tap(find.text(l.aicQuickReply1), warnIfMissed: false);
      await tester.pump();

      expect(repository.sent, isEmpty);
      expect(find.text(l.aicGeneratingReply), findsNothing);

      repository.history.complete(const <ChatMessage>[]);
      await tester.pumpAndSettle();
    });

    testWidgets('복원 중에는 입력칸이 잠기고, 끝나면 풀린다', (tester) async {
      final _GatedRepository repository = await pumpPage(tester);

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

      repository.history.complete(const <ChatMessage>[]);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(repository.sent, isEmpty);
    });

    testWidgets('복원이 끝나면 로딩이 사라지고 빠른 질문을 보낼 수 있다', (tester) async {
      final _GatedRepository repository = await pumpPage(tester);
      final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

      repository.history.complete(const <ChatMessage>[_yesterdayAnswer]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('aiCoachRestoring')), findsNothing);
      expect(find.text(keepWords('어제 답변')), findsOneWidget);

      await tester.tap(find.text(l.aicQuickReply1));
      await tester.pump();

      expect(repository.sent, <String>[l.aicQuickReply1]);
      expect(find.text(l.aicGeneratingReply), findsOneWidget);

      repository.reply.complete(
        const ChatMessage(role: ChatRole.coach, content: '닭가슴살 샐러드요'),
      );
      await tester.pumpAndSettle();
      // 복원분이 앞, 새 질문과 답이 뒤에 선다.
      expect(
        tester.getTopLeft(find.text(keepWords('어제 답변'))).dy,
        lessThan(tester.getTopLeft(find.text(keepWords('닭가슴살 샐러드요'))).dy),
      );
    });
  });
}

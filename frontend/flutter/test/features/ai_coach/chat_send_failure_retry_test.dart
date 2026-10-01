/// AI 챗 전송 실패 — 보낸 말은 남고, `다시 보내기` 는 처음 쓴 키로 간다. (#2846)
///
/// 첫 요청이 서버에서 끝나 있었다면 같은 키의 재전송은 저장된 답을 돌려줄 뿐 다시
/// 세거나 차감하지 않는다. 그래서 앱이 키를 바꾸지 않는 것이 핵심이다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/ai_coach/data/repositories/mock_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';

import 'free_quota.dart';

/// 서버처럼 키를 기억하는 대역.
///
/// [loseResponses] 가 남아 있으면 답을 저장하고도 응답 대신 망 오류를 던진다 —
/// "서버는 처리했는데 앱은 모르는" 상황이다. [dropRequests] 면 서버에 닿지도 않는다.
class _ServerLike implements AiCoachRepository {
  _ServerLike({this.quota = kFreeQuota});

  AiChatQuota quota;
  int loseResponses = 0;
  bool dropRequests = false;
  AiChatBlocked? blockWith;
  bool historyAvailable = false;
  DateTime savedAt = DateTime(2026, 10, 1, 9);

  final List<String?> keys = <String?>[];
  final List<bool> paid = <bool>[];
  final List<List<ChatMessage>> histories = <List<ChatMessage>>[];
  final Map<String, ChatMessage> replies = <String, ChatMessage>{};
  final List<ChatMessage> stored = <ChatMessage>[];
  int counted = 0;

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<void> dismissInsight(String messageId) async {}

  @override
  Future<AiChatQuota> fetchQuota() async => quota;

  @override
  Future<ChatInsightHistory> fetchInsights() async =>
      const ChatInsightHistory();

  @override
  Future<List<ChatMessage>> fetchHistory() async {
    if (!historyAvailable) throw const NetworkError();
    return List<ChatMessage>.of(stored);
  }

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
    bool payWithPoints = false,
    String? clientRequestId,
  }) async {
    keys.add(clientRequestId);
    paid.add(payWithPoints);
    histories.add(history);
    if (dropRequests) throw const NetworkError();
    final ChatMessage? replayed = replies[clientRequestId];
    if (replayed != null) return replayed;
    final AiChatBlocked? blocked = blockWith;
    if (blocked != null) throw blocked;
    counted++;
    final ChatMessage reply = ChatMessage(
      role: ChatRole.coach,
      content: '답 $counted',
    );
    replies[clientRequestId!] = reply;
    stored
      ..add(ChatMessage(role: ChatRole.user, content: message, at: savedAt))
      ..add(ChatMessage(role: ChatRole.coach, content: reply.content));
    if (loseResponses > 0) {
      loseResponses--;
      throw const NetworkError();
    }
    return reply;
  }
}

ProviderContainer _container(
  AiCoachRepository repo, {
  DateTime Function()? wallClock,
}) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      chatControllerProvider.overrideWith(
        (Ref ref) => ChatController(
          repo,
          wallClock: wallClock ?? () => DateTime(2026, 10, 1, 9, 1),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // 컨트롤러를 지금 만들어 복원을 시작한다 — 뒤의 [_settle] 이 복원을 끝낸 다음에
  // 보내야 한다. 보낼 때 처음 만들면 복원이 아직 도는 중이라, 그 사이 서버에 저장된
  // 질문이 복원분으로 먼저 들어와 저장분 확인이 "이미 보낸 질문" 으로 보고 넘어간다.
  container.read(chatControllerProvider);
  return container;
}

Future<void> _settle() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ChatMessage _failed(ProviderContainer c) => c
    .read(chatControllerProvider)
    .messages
    .firstWhere((ChatMessage m) => m.failed);

void main() {
  test('망 오류면 보낸 말이 `보내지 못함` 으로 남고 결과는 failed 다', () async {
    final _ServerLike repo = _ServerLike()..dropRequests = true;
    final ProviderContainer c = _container(repo);
    await _settle();

    final ChatSendResult r = await c
        .read(chatControllerProvider.notifier)
        .send('긴 질문입니다');

    expect(r.outcome, ChatSendOutcome.failed);
    final ChatState state = c.read(chatControllerProvider);
    final ChatMessage failed = _failed(c);
    expect(failed.content, '긴 질문입니다');
    expect(failed.clientRequestId, repo.keys.single);
    expect(failed.paidAttempt, isFalse);
    expect(state.messages.last.notice, ChatNotice.failure);
    expect(state.sending, isFalse);
  });

  test('다시 보내기는 처음 쓴 키로 가고, 성공하면 실패 표시가 답으로 바뀐다', () async {
    final _ServerLike repo = _ServerLike()..dropRequests = true;
    final ProviderContainer c = _container(repo);
    await _settle();
    final ChatController chat = c.read(chatControllerProvider.notifier);
    await chat.send('질문');
    final String key = _failed(c).clientRequestId!;

    repo.dropRequests = false;
    final ChatSendResult r = await chat.retry(key);

    expect(r.outcome, ChatSendOutcome.sent);
    expect(repo.keys, <String?>[key, key]);
    final List<ChatMessage> messages = c.read(chatControllerProvider).messages;
    expect(messages.any((ChatMessage m) => m.failed), isFalse);
    expect(
      messages.any((ChatMessage m) => m.notice == ChatNotice.failure),
      isFalse,
    );
    expect(messages.where((ChatMessage m) => m.isUser).single.content, '질문');
    expect(messages.last.content, '답 1');
  });

  test('첫 요청이 서버에서 처리됐으면 재전송해도 한 번만 센다', () async {
    final _ServerLike repo = _ServerLike()..loseResponses = 1;
    final ProviderContainer c = _container(repo);
    await _settle();
    final ChatController chat = c.read(chatControllerProvider.notifier);
    await chat.send('질문');
    final String key = _failed(c).clientRequestId!;

    await chat.retry(key);

    expect(repo.counted, 1);
    expect(c.read(chatControllerProvider).messages.last.content, '답 1');
  });

  test('포인트로 보낸 메시지는 다시 보낼 때도 포인트로 보낸다', () async {
    final _ServerLike repo = _ServerLike(
      quota: const AiChatQuota(
        freeLimit: 5,
        freeLeft: 0,
        paidLimit: 10,
        paidLeft: 10,
        cost: 50,
        balance: 500,
        next: AiChatNext.paid,
      ),
    )..dropRequests = true;
    final ProviderContainer c = _container(repo);
    await _settle();
    final ChatController chat = c.read(chatControllerProvider.notifier);
    await chat.send('유료 질문', payWithPoints: true);
    final ChatMessage failed = _failed(c);
    expect(failed.paidAttempt, isTrue);

    repo.dropRequests = false;
    await chat.retry(failed.clientRequestId!);

    expect(repo.paid, <bool>[true, true]);
    expect(repo.keys.toSet(), hasLength(1));
  });

  test('다시 보내기는 앱의 한도로 미리 막지 않고 서버에 맡긴다', () async {
    // 첫 요청이 무료 마지막 한 번을 썼다면 앱의 한도는 이미 "포인트" 다. 같은 키의
    // 재전송은 서버가 저장한 답을 돌려줄 뿐이라 동의를 묻지 않아야 한다.
    final _ServerLike repo = _ServerLike()..loseResponses = 1;
    final ProviderContainer c = _container(repo);
    await _settle();
    final ChatController chat = c.read(chatControllerProvider.notifier);
    await chat.send('질문');
    repo.quota = const AiChatQuota(
      freeLimit: 5,
      freeLeft: 0,
      paidLimit: 10,
      paidLeft: 10,
      cost: 50,
      balance: 0,
      next: AiChatNext.paid,
    );
    await chat.refreshQuota();

    final ChatSendResult r = await chat.retry(_failed(c).clientRequestId!);

    expect(r.outcome, ChatSendOutcome.sent);
    expect(repo.counted, 1);
  });

  test('다시 보내기가 한도에 걸리면 실패 메시지가 그대로 남는다', () async {
    final _ServerLike repo = _ServerLike()..dropRequests = true;
    final ProviderContainer c = _container(repo);
    await _settle();
    final ChatController chat = c.read(chatControllerProvider.notifier);
    await chat.send('질문');
    final String key = _failed(c).clientRequestId!;

    repo
      ..dropRequests = false
      ..blockWith = const AiChatBlocked(AiChatBlockReason.pointsRequired);
    final ChatSendResult r = await chat.retry(key);

    expect(r.outcome, ChatSendOutcome.needsConsent);
    expect(_failed(c).clientRequestId, key);
    expect(
      c.read(chatControllerProvider).messages.last.notice,
      ChatNotice.failure,
    );
  });

  test('보내지 못한 메시지는 서버에 대화 이력으로 보내지 않는다', () async {
    final _ServerLike repo = _ServerLike()..dropRequests = true;
    final ProviderContainer c = _container(repo);
    await _settle();
    final ChatController chat = c.read(chatControllerProvider.notifier);
    await chat.send('실패한 질문');

    repo.dropRequests = false;
    await chat.send('새 질문');

    expect(
      repo.histories.last.any((ChatMessage m) => m.content == '실패한 질문'),
      isFalse,
    );
    // 화면에는 둘 다 남는다.
    expect(_failed(c).content, '실패한 질문');
  });

  test('길게 눌러 고쳐 쓰면 실패 메시지와 안내를 거두고 글을 돌려준다', () async {
    final _ServerLike repo = _ServerLike()..dropRequests = true;
    final ProviderContainer c = _container(repo);
    await _settle();
    final ChatController chat = c.read(chatControllerProvider.notifier);
    await chat.send('고칠 질문');

    final ChatMessage? taken = chat.discardFailed(_failed(c).clientRequestId!);

    expect(taken?.content, '고칠 질문');
    final List<ChatMessage> messages = c.read(chatControllerProvider).messages;
    expect(messages.any((ChatMessage m) => m.failed), isFalse);
    expect(
      messages.any((ChatMessage m) => m.notice == ChatNotice.failure),
      isFalse,
    );
  });

  group('시간 초과 뒤 저장분 확인', () {
    test('서버가 답을 저장했으면 실패 안내를 그 답으로 바꾼다', () async {
      final _ServerLike repo = _ServerLike()
        ..loseResponses = 1
        ..historyAvailable = true;
      // 복원은 비어 있는 채로 끝나야 하므로 처음엔 저장분이 없다.
      final ProviderContainer c = _container(repo);
      await _settle();

      final ChatSendResult r = await c
          .read(chatControllerProvider.notifier)
          .send('저장된 질문');

      expect(r.outcome, ChatSendOutcome.failed);
      final List<ChatMessage> messages = c
          .read(chatControllerProvider)
          .messages;
      expect(messages.any((ChatMessage m) => m.failed), isFalse);
      expect(messages.last.content, '답 1');
      expect(repo.counted, 1);
    });

    test('저장분이 오래된 같은 질문이면 바꾸지 않는다', () async {
      final _ServerLike repo = _ServerLike()
        ..loseResponses = 1
        ..historyAvailable = true;
      final ProviderContainer c = _container(
        repo,
        wallClock: () => DateTime(2026, 10, 1, 12),
      );
      await _settle();

      await c.read(chatControllerProvider.notifier).send('저장된 질문');

      expect(_failed(c).content, '저장된 질문');
    });

    test('저장분을 못 읽으면 실패로 남는다', () async {
      final _ServerLike repo = _ServerLike()..loseResponses = 1;
      final ProviderContainer c = _container(repo);
      await _settle();

      await c.read(chatControllerProvider.notifier).send('질문');

      expect(_failed(c).content, '질문');
    });
  });

  group('데모 저장소', () {
    test('같은 키로 다시 보내면 같은 답을 주고 다시 세지 않는다', () async {
      final MockAiCoachRepository mock = MockAiCoachRepository();

      final ChatMessage first = await mock.sendMessage(
        message: '질문',
        history: const <ChatMessage>[],
        clientRequestId: 'k1',
      );
      final ChatMessage again = await mock.sendMessage(
        message: '질문',
        history: const <ChatMessage>[],
        clientRequestId: 'k1',
      );

      expect(identical(first, again), isTrue);
      expect(mock.sentCount, 1);
      await mock.sendMessage(
        message: '질문',
        history: const <ChatMessage>[],
        clientRequestId: 'k2',
      );
      expect(mock.sentCount, 2);
    });
  });
}

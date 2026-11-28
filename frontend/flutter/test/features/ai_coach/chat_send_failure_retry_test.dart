/// AI 챗 전송 실패 — 보낸 말은 남고, `다시 보내기` 는 처음 쓴 키로 간다. (#2846)
///
/// 첫 요청이 서버에서 끝나 있었다면 같은 키의 재전송은 저장된 답을 돌려줄 뿐 다시
/// 세거나 차감하지 않는다. 그래서 앱이 키를 바꾸지 않는 것이 핵심이다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';

import '../../helpers/mock_ai_coach_repository.dart';
import 'free_quota.dart';

/// 서버처럼 키를 기억하는 대역.
///
/// [loseResponses] 가 남아 있으면 답을 저장하고도 응답 대신 망 오류를 던진다 —
/// "서버는 처리했는데 앱은 모르는" 상황이다. [dropRequests] 면 서버에 닿지도 않는다.
/// [restoreGate] 를 두면 첫 저장분 읽기(화면을 열 때의 복원)가 그것이 풀릴 때까지
/// 끝나지 않고, [replyGate] 를 두면 서버가 저장한 뒤 응답이 그것이 풀릴 때까지
/// 돌아오지 않는다. [laterHistoryFails] 면 복원 뒤의 저장분 읽기가 실패한다.
///
/// 저장분은 실서버처럼 줄마다 식별자와 그 전송의 키를 싣는다(#3352).
/// [inProgressReplies] 가 남아 있으면 그 수만큼 `in_progress` 로 답한다 — 같은 키의
/// 앞선 요청이 아직 답을 만드는 중이다. [finishAfterReads] 를 두면 저장분을 그만큼
/// 읽은 뒤에 앞선 요청이 끝나 저장된다.
class _ServerLike implements AiCoachRepository {
  _ServerLike({this.quota = kFreeQuota});

  AiChatQuota quota;
  int loseResponses = 0;
  bool dropRequests = false;
  AiChatBlocked? blockWith;
  bool historyAvailable = false;
  DateTime savedAt = DateTime(2026, 10, 1, 9);
  int inProgressReplies = 0;
  int? finishAfterReads;
  final List<({String key, String message})> _working =
      <({String key, String message})>[];
  Completer<void>? restoreGate;
  Completer<void>? replyGate;

  /// 두면 요청이 서버에 닿기 전에 이것이 풀릴 때까지 기다린다 — 성공·한도·망
  /// 오류 어느 쪽이든 답이 늦게 오게 한다(#3096).
  Completer<void>? sendGate;
  bool laterHistoryFails = false;
  int historyReads = 0;

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
    historyReads++;
    if (historyReads == 1) {
      await restoreGate?.future;
    } else if (laterHistoryFails) {
      throw const NetworkError();
    }
    if (!historyAvailable) throw const NetworkError();
    final int? after = finishAfterReads;
    if (after != null && historyReads > after) {
      for (final ({String key, String message}) w in _working) {
        _save(w.key, w.message);
      }
      _working.clear();
    }
    return List<ChatMessage>.of(stored);
  }

  /// 질문과 답을 저장하고 그 응답(답 + 두 줄의 식별자)을 돌려준다.
  ChatMessage _save(String key, String message) {
    counted++;
    final ChatMessage reply = ChatMessage(
      role: ChatRole.coach,
      content: '답 $counted',
      at: savedAt,
      id: 'a$counted',
      questionId: 'q$counted',
      questionAt: savedAt,
      clientRequestId: key,
    );
    replies[key] = reply;
    stored
      ..add(
        ChatMessage(
          role: ChatRole.user,
          content: message,
          at: savedAt,
          id: 'q$counted',
          clientRequestId: key,
        ),
      )
      ..add(
        ChatMessage(
          role: ChatRole.coach,
          content: reply.content,
          at: savedAt,
          id: 'a$counted',
          clientRequestId: key,
        ),
      );
    return reply;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
    bool payWithPoints = false,
    String? clientRequestId,
  }) async {
    await sendGate?.future;
    keys.add(clientRequestId);
    paid.add(payWithPoints);
    histories.add(history);
    if (dropRequests) throw const NetworkError();
    final ChatMessage? replayed = replies[clientRequestId];
    if (replayed != null) return replayed;
    final AiChatBlocked? blocked = blockWith;
    if (blocked != null) throw blocked;
    if (inProgressReplies > 0) {
      inProgressReplies--;
      if (!_working.any(
        (({String key, String message}) w) => w.key == clientRequestId,
      )) {
        _working.add((key: clientRequestId!, message: message));
      }
      throw const AiChatInProgress();
    }
    final ChatMessage reply = _save(clientRequestId!, message);
    await replyGate?.future;
    if (loseResponses > 0) {
      loseResponses--;
      throw const NetworkError();
    }
    return reply;
  }
}

ProviderContainer _container(AiCoachRepository repo) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      chatControllerProvider.overrideWith(
        // `in_progress` 뒤 저장분을 다시 읽는 간격을 없앤다 — 순서만 본다.
        (Ref ref) =>
            ChatController(repo, inProgressPollInterval: Duration.zero),
      ),
    ],
  );
  addTearDown(container.dispose);
  // 컨트롤러를 지금 만들어 복원을 시작한다 — 뒤의 [_settle] 이 복원을 끝낸 다음에
  // 보낸다. 복원과 겹치는 순서는 [_ServerLike.restoreGate] 로 따로 만든다.
  container.read(chatControllerProvider);
  return container;
}

Future<void> _settle() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<String> _users(ProviderContainer c) => <String>[
  for (final ChatMessage m in c.read(chatControllerProvider).messages)
    if (m.isUser) m.content,
];

bool _showsFailure(ProviderContainer c) => c
    .read(chatControllerProvider)
    .messages
    .any((ChatMessage m) => m.failed || m.notice == ChatNotice.failure);

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

    test('저장분에 같은 글의 다른 전송만 있으면 바꾸지 않는다 (#3352)', () async {
      // 예전에는 같은 글과 시각으로 추측해, 직전에 보낸 같은 문장의 답을 실패한
      // 질문에 붙이고 실패 표시를 지웠다.
      final _ServerLike repo = _ServerLike()..historyAvailable = true;
      final ProviderContainer c = _container(repo);
      await _settle();
      final ChatController chat = c.read(chatControllerProvider.notifier);
      await chat.send('네');

      repo.dropRequests = true;
      final ChatSendResult r = await chat.send('네');

      expect(r.outcome, ChatSendOutcome.failed);
      expect(_users(c), <String>['네', '네']);
      expect(_failed(c).content, '네');
      expect(_failed(c).clientRequestId, repo.keys.last);
      expect(
        c
            .read(chatControllerProvider)
            .messages
            .where((ChatMessage m) => m.content == '답 1'),
        hasLength(1),
      );
    });

    test('바꾼 질문과 답은 서버가 준 식별자와 키를 갖는다 (#3352)', () async {
      final _ServerLike repo = _ServerLike()
        ..loseResponses = 1
        ..historyAvailable = true;
      final ProviderContainer c = _container(repo);
      await _settle();

      await c.read(chatControllerProvider.notifier).send('저장된 질문');

      final List<ChatMessage> messages = c
          .read(chatControllerProvider)
          .messages;
      final ChatMessage question = messages.firstWhere(
        (ChatMessage m) => m.isUser,
      );
      expect(question.id, 'q1');
      expect(question.clientRequestId, repo.keys.single);
      expect(messages.last.id, 'a1');
    });

    test('저장분을 못 읽으면 실패로 남는다', () async {
      final _ServerLike repo = _ServerLike()..loseResponses = 1;
      final ProviderContainer c = _container(repo);
      await _settle();

      await c.read(chatControllerProvider.notifier).send('질문');

      expect(_failed(c).content, '질문');
    });

    test('같은 글을 일부러 두 번 보내 뒤의 것이 시간 초과면 각자의 답으로 남는다', () async {
      final _ServerLike repo = _ServerLike()..historyAvailable = true;
      final ProviderContainer c = _container(repo);
      await _settle();
      final ChatController chat = c.read(chatControllerProvider.notifier);
      await chat.send('같은 질문');

      // 저장 시각이 같아도 키로 제 답을 찾는다.
      repo.loseResponses = 1;
      final ChatSendResult r = await chat.send('같은 질문');

      expect(r.outcome, ChatSendOutcome.failed);
      expect(_users(c), <String>['같은 질문', '같은 질문']);
      expect(_showsFailure(c), isFalse);
      final List<ChatMessage> messages = c
          .read(chatControllerProvider)
          .messages;
      expect(messages.last.content, '답 2');
      expect(
        messages.where((ChatMessage m) => m.content == '답 1'),
        hasLength(1),
      );
    });

    test('같은 글을 두 번 보내 뒤의 것이 서버에 닿지 않았으면 앞의 답을 붙이지 않는다', () async {
      // 붙여 보내 시각으로는 가를 수 없어도, 저장분의 쌍은 앞의 질문 것이다.
      final _ServerLike repo = _ServerLike()..historyAvailable = true;
      final ProviderContainer c = _container(repo);
      await _settle();
      final ChatController chat = c.read(chatControllerProvider.notifier);
      await chat.send('같은 질문');

      repo.dropRequests = true;
      await chat.send('같은 질문');

      expect(_users(c), <String>['같은 질문', '같은 질문']);
      expect(_failed(c).content, '같은 질문');
      expect(
        c.read(chatControllerProvider).messages.last.notice,
        ChatNotice.failure,
      );
    });
  });

  group('대화 복원과 겹친 첫 질문의 시간 초과', () {
    test('보내는 사이 복원이 그 질문·답을 가져와도 한 번만 남고 실패 표시가 없다', () async {
      final _ServerLike repo = _ServerLike()
        ..historyAvailable = true
        ..loseResponses = 1
        ..restoreGate = Completer<void>()
        ..replyGate = Completer<void>();
      final ProviderContainer c = _container(repo);
      await _settle();
      expect(c.read(chatControllerProvider).restoring, isTrue);

      // 화면을 열자마자 첫 질문 — 서버는 저장했지만 응답이 아직 오지 않았다.
      final Future<ChatSendResult> sending = c
          .read(chatControllerProvider.notifier)
          .send('첫 질문');
      await _settle();

      // 그 사이 복원이 끝나 방금 저장된 질문·답을 가져온다.
      repo.restoreGate!.complete();
      await _settle();
      expect(c.read(chatControllerProvider).restoring, isFalse);
      expect(_users(c), <String>['첫 질문']);

      // 이제 응답이 시간 초과로 끝난다.
      repo.replyGate!.complete();
      final ChatSendResult r = await sending;
      await _settle();

      expect(r.outcome, ChatSendOutcome.failed);
      expect(_users(c), <String>['첫 질문']);
      expect(_showsFailure(c), isFalse);
      expect(c.read(chatControllerProvider).messages.last.content, '답 1');
      expect(repo.counted, 1);
    });

    test('시간 초과 뒤에 복원이 그 질문·답을 가져오면 실패 메시지를 그것으로 대신한다', () async {
      final _ServerLike repo = _ServerLike()
        ..historyAvailable = true
        ..loseResponses = 1
        ..laterHistoryFails = true
        ..restoreGate = Completer<void>();
      final ProviderContainer c = _container(repo);
      await _settle();

      final ChatSendResult r = await c
          .read(chatControllerProvider.notifier)
          .send('첫 질문');
      expect(r.outcome, ChatSendOutcome.failed);
      expect(_failed(c).content, '첫 질문');

      repo.restoreGate!.complete();
      await _settle();

      final List<ChatMessage> messages = c
          .read(chatControllerProvider)
          .messages;
      expect(_users(c), <String>['첫 질문']);
      expect(_showsFailure(c), isFalse);
      expect(messages.last.content, '답 1');
    });

    test('시간 초과 뒤 저장분 확인이 먼저 답을 붙여도 늦게 끝난 복원이 겹치지 않는다', () async {
      final _ServerLike repo = _ServerLike()
        ..historyAvailable = true
        ..loseResponses = 1
        ..restoreGate = Completer<void>();
      final ProviderContainer c = _container(repo);
      await _settle();

      await c.read(chatControllerProvider.notifier).send('첫 질문');
      expect(_showsFailure(c), isFalse);

      repo.restoreGate!.complete();
      await _settle();

      expect(_users(c), <String>['첫 질문']);
      expect(_showsFailure(c), isFalse);
      expect(
        c
            .read(chatControllerProvider)
            .messages
            .where((ChatMessage m) => m.content == '답 1'),
        hasLength(1),
      );
    });

    test('서버가 저장하지 않았으면 복원이 끝나도 실패로 남고 같은 키로 다시 보낸다', () async {
      final _ServerLike repo = _ServerLike()
        ..historyAvailable = true
        ..dropRequests = true
        ..restoreGate = Completer<void>();
      final ProviderContainer c = _container(repo);
      await _settle();
      final ChatController chat = c.read(chatControllerProvider.notifier);

      await chat.send('첫 질문');
      repo.restoreGate!.complete();
      await _settle();

      final String key = _failed(c).clientRequestId!;
      expect(_failed(c).content, '첫 질문');

      repo.dropRequests = false;
      final ChatSendResult r = await chat.retry(key);

      expect(r.outcome, ChatSendOutcome.sent);
      expect(repo.keys, <String?>[key, key]);
      expect(_users(c), <String>['첫 질문']);
      expect(_showsFailure(c), isFalse);
    });
  });

  group('답을 받으면 서버가 준 식별자를 붙인다 (#3352)', () {
    test('보낸 질문과 받은 답에 식별자·키가 남는다', () async {
      final _ServerLike repo = _ServerLike();
      final ProviderContainer c = _container(repo);
      await _settle();

      await c.read(chatControllerProvider.notifier).send('질문');

      final List<ChatMessage> messages = c
          .read(chatControllerProvider)
          .messages;
      final ChatMessage question = messages.firstWhere(
        (ChatMessage m) => m.isUser,
      );
      expect(question.id, 'q1');
      expect(question.at, repo.savedAt);
      expect(question.clientRequestId, repo.keys.single);
      expect(messages.last.id, 'a1');
      expect(messages.last.at, repo.savedAt);
    });

    test('식별자를 주지 않는 서버여도 지금처럼 답이 붙는다', () async {
      final MockAiCoachRepository mock = MockAiCoachRepository();
      final ProviderContainer c = _container(mock);
      await _settle();

      final ChatSendResult r = await c
          .read(chatControllerProvider.notifier)
          .send('질문');

      expect(r.outcome, ChatSendOutcome.sent);
      final List<ChatMessage> messages = c
          .read(chatControllerProvider)
          .messages;
      expect(messages.last.id, isNull);
      expect(messages.last.at, isNotNull);
      expect(messages.any((ChatMessage m) => m.pending), isFalse);
    });
  });

  group('같은 문장을 연달아 보낸 뒤의 복원 (#3352)', () {
    test('뒤의 것이 실패했으면 복원이 끝나도 실패 표시가 남는다', () async {
      final _ServerLike repo = _ServerLike()
        ..historyAvailable = true
        ..laterHistoryFails = true
        ..restoreGate = Completer<void>();
      final ProviderContainer c = _container(repo);
      await _settle();
      final ChatController chat = c.read(chatControllerProvider.notifier);

      await chat.send('네');
      repo.dropRequests = true;
      await chat.send('네');
      expect(_failed(c).content, '네');

      // 복원분에는 앞의 '네' 와 그 답만 있다.
      repo.restoreGate!.complete();
      await _settle();

      expect(_users(c), <String>['네', '네']);
      expect(_failed(c).clientRequestId, repo.keys.last);
      expect(
        c.read(chatControllerProvider).messages.last.notice,
        ChatNotice.failure,
      );
      expect(repo.counted, 1);
    });
  });

  group('서버가 아직 처리 중이라고 답하면 (#3352)', () {
    test('실패로 보지 않고 저장분을 다시 읽어 그 답을 붙인다', () async {
      final _ServerLike repo = _ServerLike()
        ..historyAvailable = true
        ..inProgressReplies = 1
        ..finishAfterReads = 2;
      final ProviderContainer c = _container(repo);
      await _settle();

      final ChatSendResult r = await c
          .read(chatControllerProvider.notifier)
          .send('질문');

      expect(r.outcome, ChatSendOutcome.sent);
      final ChatState state = c.read(chatControllerProvider);
      expect(state.sending, isFalse);
      expect(_showsFailure(c), isFalse);
      expect(_users(c), <String>['질문']);
      expect(state.messages.last.content, '답 1');
      expect(state.messages.last.id, 'a1');
      expect(state.messages.any((ChatMessage m) => m.pending), isFalse);
      // 다시 보내지 않았다 — 기다리며 저장분만 읽었다.
      expect(repo.keys, hasLength(1));
      expect(repo.counted, 1);
    });

    test('기다리는 동안에는 보내는 중으로 남는다', () async {
      final _ServerLike repo = _ServerLike()
        ..historyAvailable = true
        ..inProgressReplies = 1
        ..finishAfterReads = 4;
      final ProviderContainer c = _container(repo);
      await _settle();

      final Future<ChatSendResult> sending = c
          .read(chatControllerProvider.notifier)
          .send('질문');
      await Future<void>.delayed(Duration.zero);

      final ChatState waiting = c.read(chatControllerProvider);
      expect(waiting.sending, isTrue);
      expect(waiting.messages.last.pending, isTrue);
      expect(_showsFailure(c), isFalse);

      expect((await sending).outcome, ChatSendOutcome.sent);
    });

    test('다시 보내기가 처리 중에 걸려도 같은 질문이 한 번만 남는다', () async {
      // 첫 요청은 시간 초과로 끝났지만 서버는 아직 답을 만드는 중이다.
      final _ServerLike repo = _ServerLike()..dropRequests = true;
      final ProviderContainer c = _container(repo);
      await _settle();
      final ChatController chat = c.read(chatControllerProvider.notifier);
      await chat.send('질문');
      final String key = _failed(c).clientRequestId!;

      repo
        ..dropRequests = false
        ..historyAvailable = true
        ..inProgressReplies = 1
        ..finishAfterReads = repo.historyReads + 1;
      final ChatSendResult r = await chat.retry(key);

      expect(r.outcome, ChatSendOutcome.sent);
      expect(_users(c), <String>['질문']);
      expect(_showsFailure(c), isFalse);
      expect(c.read(chatControllerProvider).messages.last.content, '답 1');
    });

    test('끝내 저장되지 않으면 `보내지 못함` 으로 남고 같은 키로 다시 보낸다', () async {
      final _ServerLike repo = _ServerLike()
        ..historyAvailable = true
        ..inProgressReplies = 1;
      final ProviderContainer c = _container(repo);
      await _settle();
      final ChatController chat = c.read(chatControllerProvider.notifier);

      final ChatSendResult r = await chat.send('질문');

      expect(r.outcome, ChatSendOutcome.failed);
      expect(c.read(chatControllerProvider).sending, isFalse);
      final String key = _failed(c).clientRequestId!;
      expect(key, repo.keys.single);

      final ChatSendResult again = await chat.retry(key);

      expect(again.outcome, ChatSendOutcome.sent);
      expect(repo.keys, <String?>[key, key]);
      expect(_users(c), <String>['질문']);
    });

    test('저장분 읽기가 실패해도 던지지 않고 실패로 남는다', () async {
      final _ServerLike repo = _ServerLike()..inProgressReplies = 1;
      final ProviderContainer c = _container(repo);
      await _settle();

      final ChatSendResult r = await c
          .read(chatControllerProvider.notifier)
          .send('질문');

      expect(r.outcome, ChatSendOutcome.failed);
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

  group('기다리는 사이 컨트롤러가 버려지면 (#3096)', () {
    // 로그아웃·계정 전환 리셋이 `chatControllerProvider` 를 무효화한 뒤 답이 온다.
    Future<void> sendThenReset(
      _ServerLike repo,
      ChatSendOutcome expected,
    ) async {
      final ProviderContainer c = _container(repo);
      await _settle();
      final ChatController old = c.read(chatControllerProvider.notifier);
      repo.sendGate = Completer<void>();
      final Future<ChatSendResult> pending = old.send('질문');
      await _settle();

      c.invalidate(chatControllerProvider);
      final ChatController fresh = c.read(chatControllerProvider.notifier);
      expect(identical(fresh, old), isFalse);
      expect(old.mounted, isFalse);
      await _settle();
      final ChatState before = c.read(chatControllerProvider);

      repo.sendGate!.complete();
      final ChatSendResult r = await pending;

      expect(r.outcome, expected);
      // 새 계정의 대화에는 앞 계정의 질문·답이 섞이지 않는다.
      expect(c.read(chatControllerProvider).messages, before.messages);
      expect(_users(c), isNot(contains('질문')));
    }

    test('답이 와도 던지지 않고 아무것도 쓰지 않는다', () async {
      await sendThenReset(_ServerLike(), ChatSendOutcome.ignored);
    });

    test('한도 거절이 와도 던지지 않는다', () async {
      await sendThenReset(
        _ServerLike()
          ..blockWith = const AiChatBlocked(AiChatBlockReason.dailyLimit),
        ChatSendOutcome.ignored,
      );
    });

    test('망 오류가 와도 던지지 않는다', () async {
      await sendThenReset(
        _ServerLike()..dropRequests = true,
        ChatSendOutcome.ignored,
      );
    });
  });
}

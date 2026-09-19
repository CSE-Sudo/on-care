import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';

class _FakeCoachRepo implements AiCoachRepository {
  _FakeCoachRepo({
    this.stored = const <ChatMessage>[],
    this.historyFails = false,
  });

  /// 서버에 저장돼 있다고 가정할 이전 대화.
  final List<ChatMessage> stored;

  /// true 면 히스토리 조회가 실패한다(복원 실패해도 채팅은 살아 있어야 한다).
  final bool historyFails;

  @override
  Future<AiCoachState> fetchState() async =>
      const AiCoachState(greeting: '', suggestions: <AiSuggestion>[]);

  @override
  Future<void> dismissInsight(String messageId) async {}

  @override
  Future<ChatInsightHistory> fetchInsights() async =>
      const ChatInsightHistory();

  @override
  Future<List<ChatMessage>> fetchHistory() async {
    if (historyFails) throw Exception('history unavailable');
    return stored;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
  }) async => const ChatMessage(
    role: ChatRole.coach,
    content: '저염 식단이 도움이 됩니다.',
    sources: <String>['나트륨 줄이기'],
  );
}

void main() {
  test('starts with a single welcome message from the coach', () {
    final container = ProviderContainer(
      overrides: <Override>[
        aiCoachRepositoryProvider.overrideWithValue(_FakeCoachRepo()),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(chatControllerProvider);
    expect(state.messages.length, 1);
    expect(state.messages.single.role, ChatRole.coach);
    expect(state.sending, isFalse);
  });

  test('send() appends the user message and the coach reply', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        aiCoachRepositoryProvider.overrideWithValue(_FakeCoachRepo()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).send('나트륨 줄이는 법');

    final state = container.read(chatControllerProvider);
    expect(state.sending, isFalse);
    expect(
      state.messages.any(
        (ChatMessage m) => m.isUser && m.content == '나트륨 줄이는 법',
      ),
      isTrue,
    );
    expect(state.messages.last.role, ChatRole.coach);
    expect(state.messages.last.content, contains('저염'));
    expect(state.messages.last.sources, contains('나트륨 줄이기'));
    // 진행 중 표시(pending)는 응답 후 남아있지 않아야 한다.
    expect(state.messages.any((ChatMessage m) => m.pending), isFalse);
  });

  // ── 대화 복원(#274) ──────────────────────────────────────────────────────

  test('저장된 대화가 있으면 welcome 대신 그 대화를 보여준다', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        aiCoachRepositoryProvider.overrideWithValue(
          _FakeCoachRepo(
            stored: const <ChatMessage>[
              ChatMessage(role: ChatRole.user, content: '어제 물어본 것'),
              ChatMessage(
                role: ChatRole.coach,
                content: '어제 답변',
                sources: <String>['나트륨 줄이기'],
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(chatControllerProvider); // 컨트롤러 생성 → 복원 시작
    await Future<void>.delayed(Duration.zero);

    final state = container.read(chatControllerProvider);
    expect(state.messages.length, 2);
    expect(state.messages.first.content, '어제 물어본 것');
    // 근거도 함께 복원돼야 왜 그렇게 답했는지 되짚을 수 있다.
    expect(state.messages.last.sources, contains('나트륨 줄이기'));
  });

  test('저장된 대화가 없으면 지금처럼 welcome 하나로 시작한다', () async {
    // 목업/데모 모드가 이 경로다 — 화면이 이전과 같아야 한다.
    final container = ProviderContainer(
      overrides: <Override>[
        aiCoachRepositoryProvider.overrideWithValue(_FakeCoachRepo()),
      ],
    );
    addTearDown(container.dispose);

    container.read(chatControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(chatControllerProvider);
    expect(state.messages.length, 1);
    expect(state.messages.single.role, ChatRole.coach);
  });

  test('히스토리 조회가 실패해도 채팅은 그대로 쓸 수 있다', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        aiCoachRepositoryProvider.overrideWithValue(
          _FakeCoachRepo(historyFails: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(chatControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(chatControllerProvider).messages.length, 1);

    // 복원이 실패했어도 전송은 정상 동작한다.
    await container.read(chatControllerProvider.notifier).send('질문');
    final state = container.read(chatControllerProvider);
    expect(state.messages.last.role, ChatRole.coach);
    expect(state.sending, isFalse);
  });
}

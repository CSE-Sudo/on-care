import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';

/// 대화를 처음 열었을 때의 인사. 문구는 화면이 로케일에 맞춰 그린다(#847).
const ChatMessage _welcome = ChatMessage(
  role: ChatRole.coach,
  content: '',
  notice: ChatNotice.welcome,
);

class ChatState {
  const ChatState({
    this.messages = const <ChatMessage>[_welcome],
    this.sending = false,
  });

  final List<ChatMessage> messages;
  final bool sending;

  ChatState copyWith({List<ChatMessage>? messages, bool? sending}) => ChatState(
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
  );
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._repo) : super(const ChatState()) {
    _restore();
  }

  final AiCoachRepository _repo;

  /// 서버에 저장된 이전 대화를 불러온다(재접속·다른 기기에서 대화 잇기).
  ///
  /// 실패해도 조용히 넘어간다. 히스토리를 못 불러온 것 때문에 채팅을 못 쓰게
  /// 만들 이유가 없고, 화면은 welcome 메시지로 정상 동작한다. 목업 모드는 항상
  /// 빈 목록이라 지금과 똑같이 welcome 하나로 시작한다.
  Future<void> _restore() async {
    try {
      final stored = await _repo.fetchHistory();
      if (stored.isEmpty || !mounted) return;
      // 복원한 대화가 있으면 welcome 대신 그것을 보여준다 — 이어 하는 대화에
      // 매번 인사가 끼어들면 맥락이 끊긴다.
      state = state.copyWith(messages: stored);
    } catch (_) {
      // 무시: welcome 메시지 상태 유지
    }
  }

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.sending) return;

    // 현재까지의 대화를 history 로 전달한다. 진행 중 placeholder 와 앱이 스스로
    // 띄운 말풍선(인사·실패 안내)은 뺀다 — 우리가 쓴 말을 서버에 대화로 되돌려
    // 줄 이유가 없고, 문구가 비어 있어 보내 봐야 빈 턴이 된다.
    final history = state.messages
        .where((ChatMessage m) => !m.pending && m.notice == null)
        .toList();

    // 방금 주고받는 것은 지금 시각이다 — 서버가 저장 시각을 따로 돌려주지
    // 않으므로 여기서 찍는다(#1918).
    final DateTime now = nowKst();
    state = state.copyWith(
      messages: <ChatMessage>[
        ...history,
        ChatMessage(role: ChatRole.user, content: message, at: now),
        const ChatMessage(role: ChatRole.coach, content: '', pending: true),
      ],
      sending: true,
    );

    try {
      final reply = await _repo.sendMessage(message: message, history: history);
      // 답에 실려 온 감지 결과는 **방금 보낸 회원 메시지**에 붙인다(#1824).
      final List<ChatMessage> next = _replacePending(reply.withTime(nowKst()));
      final int mine = next.lastIndexWhere((ChatMessage m) => m.isUser);
      if (mine >= 0 && reply.replyToInsight != null) {
        next[mine] = next[mine].withInsight(reply.replyToInsight);
      }
      state = state.copyWith(messages: next, sending: false);
    } catch (_) {
      state = state.copyWith(
        messages: _replacePending(
          const ChatMessage(
            role: ChatRole.coach,
            content: '',
            notice: ChatNotice.failure,
          ),
        ),
        sending: false,
      );
    }
  }

  List<ChatMessage> _replacePending(ChatMessage reply) => <ChatMessage>[
    ...state.messages.where((ChatMessage m) => !m.pending),
    reply,
  ];
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
  (ref) => ChatController(ref.watch(aiCoachRepositoryProvider)),
  name: 'chatController',
);

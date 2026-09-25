import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/core/utils/request_id.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
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
    this.quota,
  });

  final List<ChatMessage> messages;
  final bool sending;

  /// 오늘 남은 대화(#2145). 읽기 전이거나 읽지 못했으면 null 이고, 그때는 서버의
  /// 판단에 맡긴다.
  final AiChatQuota? quota;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    AiChatQuota? quota,
  }) => ChatState(
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
    quota: quota ?? this.quota,
  );
}

/// [ChatController.send] 가 한 일. 보내지 못했으면 화면이 까닭에 맞게 안내한다.
enum ChatSendOutcome {
  /// 보냈다(답을 받았거나 실패 안내를 띄웠다).
  sent,

  /// 빈 글이거나 이미 보내는 중이라 아무것도 하지 않았다.
  ignored,

  /// 무료를 다 써서 포인트로 보내려면 동의가 필요하다 — 확인창을 띄운다.
  needsConsent,

  /// 오늘 대화를 다 썼다.
  dailyLimit,

  /// 포인트가 모자라다. 모자란 값은 [ChatSendResult.shortfall].
  insufficientPoints,
}

typedef ChatSendResult = ({ChatSendOutcome outcome, int shortfall});

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._repo) : super(const ChatState()) {
    _restore();
  }

  final AiCoachRepository _repo;

  /// 오늘 한도를 다시 읽는다. 실패해도 대화는 막지 않는다 — 판단은 서버가 한다.
  Future<void> refreshQuota() async {
    try {
      final AiChatQuota quota = await _repo.fetchQuota();
      if (mounted) state = state.copyWith(quota: quota);
    } catch (_) {
      // 무시: 입력칸 위 줄만 비고, 보낼 때 서버가 판단한다.
    }
  }

  /// 서버에 저장된 이전 대화를 불러온다(재접속·다른 기기에서 대화 잇기).
  ///
  /// 실패해도 조용히 넘어간다. 히스토리를 못 불러온 것 때문에 채팅을 못 쓰게
  /// 만들 이유가 없고, 화면은 welcome 메시지로 정상 동작한다. 목업 모드는 항상
  /// 빈 목록이라 지금과 똑같이 welcome 하나로 시작한다.
  Future<void> _restore() async {
    await refreshQuota();
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

  /// [text] 를 보낸다. 오늘 무료를 다 썼으면 포인트로 보내는데, **보낼 때마다**
  /// 먼저 [ChatSendOutcome.needsConsent] 를 돌려주고 보내지 않는다 — 화면이
  /// 확인창을 띄우고 [payWithPoints] 를 켜서 다시 부른다(#2217). 포인트가 나가는
  /// 일을 한 번 동의로 하루 내내 묶어 두지 않는다.
  Future<ChatSendResult> send(String text, {bool payWithPoints = false}) async {
    final message = text.trim();
    if (message.isEmpty || state.sending) {
      return (outcome: ChatSendOutcome.ignored, shortfall: 0);
    }
    final AiChatQuota? quota = state.quota;
    if (quota != null) {
      if (quota.next == AiChatNext.exhausted) {
        return (outcome: ChatSendOutcome.dailyLimit, shortfall: 0);
      }
      if (quota.next == AiChatNext.paid) {
        if (!payWithPoints) {
          return (outcome: ChatSendOutcome.needsConsent, shortfall: 0);
        }
        if (quota.short) {
          return (
            outcome: ChatSendOutcome.insufficientPoints,
            shortfall: quota.cost - quota.balance,
          );
        }
      }
    }

    // 현재까지의 대화를 history 로 전달한다. 진행 중 placeholder 와 앱이 스스로
    // 띄운 말풍선(인사·실패 안내)은 뺀다 — 우리가 쓴 말을 서버에 대화로 되돌려
    // 줄 이유가 없고, 문구가 비어 있어 보내 봐야 빈 턴이 된다.
    final history = state.messages
        .where((ChatMessage m) => !m.pending && m.notice == null)
        .toList();

    // 한도에 걸려 보내지 못하면 이 모습으로 되돌린다(#2145).
    final List<ChatMessage> before = state.messages;

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
      final reply = await _repo.sendMessage(
        message: message,
        history: history,
        // 무료가 남았으면 서버가 보지 않는다. 이번 전송에 동의했으면 무료를
        // 넘겨도 보낸다.
        payWithPoints: payWithPoints,
        clientRequestId: newClientRequestId(),
      );
      // 답에 실려 온 감지 결과는 **방금 보낸 회원 메시지**에 붙인다(#1824).
      final List<ChatMessage> next = _replacePending(reply.withTime(nowKst()));
      final int mine = next.lastIndexWhere((ChatMessage m) => m.isUser);
      if (mine >= 0 && reply.replyToInsight != null) {
        next[mine] = next[mine].withInsight(reply.replyToInsight);
      }
      state = state.copyWith(
        messages: next,
        sending: false,
        quota: reply.replyQuota,
      );
      if (reply.replyQuota == null) await refreshQuota();
    } on AiChatBlocked catch (blocked) {
      // 보내지 않은 말이다 — 방금 띄운 말풍선을 거두고 화면이 까닭을 안내한다.
      state = state.copyWith(messages: before, sending: false);
      await refreshQuota();
      return (
        outcome: switch (blocked.reason) {
          AiChatBlockReason.pointsRequired => ChatSendOutcome.needsConsent,
          AiChatBlockReason.dailyLimit => ChatSendOutcome.dailyLimit,
          AiChatBlockReason.insufficientPoints =>
            ChatSendOutcome.insufficientPoints,
        },
        shortfall: blocked.shortfall,
      );
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
    return (outcome: ChatSendOutcome.sent, shortfall: 0);
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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_core/request_id.dart';

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
    this.restoring = false,
    this.quota,
  });

  final List<ChatMessage> messages;
  final bool sending;

  /// 서버에 저장된 이전 대화를 불러오는 중인가(#2642). 화면은 이 동안 빠른
  /// 질문과 전송을 잠깐 막는다 — 복원 전에 보낸 질문은 이전 대화의 맥락 없이
  /// 서버로 간다.
  final bool restoring;

  /// 오늘 남은 대화(#2145). 읽기 전이거나 읽지 못했으면 null 이고, 그때는 서버의
  /// 판단에 맡긴다.
  final AiChatQuota? quota;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    bool? restoring,
    AiChatQuota? quota,
  }) => ChatState(
    messages: messages ?? this.messages,
    sending: sending ?? this.sending,
    restoring: restoring ?? this.restoring,
    quota: quota ?? this.quota,
  );
}

/// 저장분의 회원 메시지 시각이 보낸 시각보다 이만큼까지 앞서도 같은 요청으로
/// 본다 — 서버와 기기 시계의 차이다. 서버는 받은 뒤에 저장하므로 원래는 늘 뒤다.
const Duration kChatSavedClockSkew = Duration(seconds: 30);

/// 저장분 [stored] 에서 [question] 과 같은 글의 회원 메시지 가운데, 보낸 시각
/// [sentAt] 이후에 저장됐고 바로 뒤에 코치 답이 있는 첫 위치. [claimed] 에 든
/// 위치는 이미 다른 메시지와 짝지었으므로 건너뛴다. 없으면 -1.
int _storedPairOf(
  List<ChatMessage> stored,
  ChatMessage question,
  DateTime sentAt,
  Set<int> claimed,
) {
  final String text = question.content.trim();
  for (int i = 0; i + 1 < stored.length; i++) {
    final ChatMessage q = stored[i];
    final DateTime? savedAt = q.at;
    if (claimed.contains(i) ||
        !q.isUser ||
        stored[i + 1].isUser ||
        q.content.trim() != text ||
        savedAt == null ||
        savedAt.isBefore(sentAt.subtract(kChatSavedClockSkew))) {
      continue;
    }
    return i;
  }
  return -1;
}

/// 복원한 대화 [stored] 와, 복원하는 동안 화면에 쌓인 [current] 를 합친다.
/// (#2642)
///
/// 복원분이 앞, 복원 중에 생긴 말이 뒤다. 앱이 띄운 인사 말풍선만 복원분으로
/// 대신한다 — 이어 하는 대화에 인사가 끼어들면 맥락이 끊긴다. 예전에는
/// 복원분으로 목록을 통째로 바꿔, 복원 전에 보낸 질문과 `답 생성 중` 말풍선이
/// 사라지고 뒤이어 온 답만 남았다.
///
/// 복원 중에 보낸 질문이 그 사이 서버에 저장돼 복원분에도 들어 있으면 한 번만
/// 남긴다(#2846). 보낸 질문은 멱등키로 [sentAtOf] 에서 보낸 시각을 찾아, 복원분에
/// 같은 글이 그 시각 이후로 답과 함께 있으면 같은 요청으로 본다(저장된 대화는
/// 키를 주지 않는다). 그 질문이 `보내지 못함` 이면 실패 표시와 안내를 거두고
/// 복원된 질문·답을 남기며, 보내는 중이거나 이미 답을 받았으면 복원분 쪽 쌍을
/// 뺀다. 저장분 한 쌍은 한 메시지하고만 짝짓는다 — 같은 글을 일부러 두 번
/// 보냈으면 둘 다 남는다.
List<ChatMessage> mergeRestoredChat(
  List<ChatMessage> stored,
  List<ChatMessage> current, {
  DateTime? Function(String clientRequestId)? sentAtOf,
}) {
  if (stored.isEmpty) return current;
  final List<ChatMessage> added = <ChatMessage>[
    for (final ChatMessage m in current)
      if (m.notice != ChatNotice.welcome) m,
  ];
  if (sentAtOf == null) return <ChatMessage>[...stored, ...added];
  final Set<int> claimed = <int>{};
  final Set<int> dropStored = <int>{};
  final Set<int> dropAdded = <int>{};
  for (int j = 0; j < added.length; j++) {
    final ChatMessage m = added[j];
    final String? key = m.clientRequestId;
    if (!m.isUser || key == null) continue;
    final DateTime? sentAt = sentAtOf(key);
    if (sentAt == null) continue;
    final int i = _storedPairOf(stored, m, sentAt, claimed);
    if (i < 0) continue;
    claimed.add(i);
    if (m.failed) {
      dropAdded.add(j);
      if (j + 1 < added.length && added[j + 1].notice == ChatNotice.failure) {
        dropAdded.add(j + 1);
      }
    } else {
      dropStored
        ..add(i)
        ..add(i + 1);
    }
  }
  return <ChatMessage>[
    for (int i = 0; i < stored.length; i++)
      if (!dropStored.contains(i)) stored[i],
    for (int j = 0; j < added.length; j++)
      if (!dropAdded.contains(j)) added[j],
  ];
}

/// [ChatController.send] 가 한 일. 보내지 못했으면 화면이 까닭에 맞게 안내한다.
enum ChatSendOutcome {
  /// 보냈다(답을 받았다).
  sent,

  /// 망 오류·시간 초과로 답을 받지 못했다(#2846). 보낸 메시지는 `보내지 못함` 으로
  /// 남고 같은 키로 다시 보낼 수 있다 — 화면은 입력칸을 되살리지 않는다(새로 쓰면
  /// 새 키라 서버가 이미 처리한 질문이 두 번 세질 수 있다).
  failed,

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
  ChatController(this._repo, {DateTime Function()? wallClock})
    : _wallClock = wallClock ?? DateTime.now,
      super(const ChatState(restoring: true)) {
    _restore();
  }

  final AiCoachRepository _repo;

  /// 저장분 시각(서버 시각을 기기 시간대로 바꾼 값)과 견줄 지금. 테스트가 고정한다.
  final DateTime Function() _wallClock;

  /// 멱등키별로 처음 보낸 시각([_wallClock] 기준). 저장분의 같은 글이 이 요청의
  /// 것인지 가르는 데 쓴다 — 저장된 대화는 키를 주지 않는다. (#2846)
  final Map<String, DateTime> _sentAt = <String, DateTime>{};

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
  ///
  /// 복원하는 동안 보낸 질문은 덮어쓰지 않고 복원분 뒤에 남긴다(#2642).
  Future<void> _restore() async {
    try {
      await refreshQuota();
      final stored = await _repo.fetchHistory();
      if (!mounted) return;
      // 복원한 대화가 있으면 welcome 대신 그것을 보여준다 — 이어 하는 대화에
      // 매번 인사가 끼어들면 맥락이 끊긴다. 그 사이 쌓인 말은 뒤에 둔다.
      state = state.copyWith(
        messages: mergeRestoredChat(
          stored,
          state.messages,
          sentAtOf: (String key) => _sentAt[key],
        ),
        restoring: false,
      );
    } catch (_) {
      // 무시: welcome 메시지 상태 유지
      if (mounted) state = state.copyWith(restoring: false);
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
    final ChatSendResult? blocked = _precheck(payWithPoints);
    if (blocked != null) return blocked;
    return _deliver(
      message,
      payWithPoints: payWithPoints,
      clientRequestId: newClientRequestId(),
    );
  }

  /// 보내지 못한 메시지를 **처음 쓴 키로** 다시 보낸다. (#2846)
  ///
  /// 첫 요청이 서버에서 끝나 있었다면 서버가 저장한 답을 그대로 돌려주고 다시
  /// 세거나 차감하지 않는다. 그래서 앱이 아는 한도로 미리 막지 않는다 — 첫 요청이
  /// 무료 한 번을 썼다면 앱의 한도는 이미 "포인트" 로 보일 수 있다. 판단은 서버가
  /// 하고, 서버가 동의를 요구하면 [ChatSendOutcome.needsConsent] 로 돌아온다.
  /// [payWithPoints] 를 주지 않으면 처음 보낼 때의 값을 쓴다.
  Future<ChatSendResult> retry(
    String clientRequestId, {
    bool? payWithPoints,
  }) async {
    if (state.sending) return (outcome: ChatSendOutcome.ignored, shortfall: 0);
    final int index = state.messages.indexWhere(
      (ChatMessage m) => m.failed && m.clientRequestId == clientRequestId,
    );
    if (index < 0) return (outcome: ChatSendOutcome.ignored, shortfall: 0);
    final ChatMessage failed = state.messages[index];
    final List<ChatMessage> before = state.messages;
    state = state.copyWith(messages: _without(before, index));
    return _deliver(
      failed.content,
      payWithPoints: payWithPoints ?? failed.paidAttempt,
      clientRequestId: clientRequestId,
      restoreOnBlock: before,
    );
  }

  /// 보내지 못한 메시지를 대화에서 거둔다 — 회원이 고쳐 쓰려고 입력칸으로 되돌릴
  /// 때다(#2846). 거둔 메시지를 돌려준다. 고쳐 쓴 글은 새 질문이라 새 키로 간다.
  ChatMessage? discardFailed(String clientRequestId) {
    final int index = state.messages.indexWhere(
      (ChatMessage m) => m.failed && m.clientRequestId == clientRequestId,
    );
    if (index < 0 || state.sending) return null;
    final ChatMessage failed = state.messages[index];
    state = state.copyWith(messages: _without(state.messages, index));
    return failed;
  }

  /// [index] 의 실패 메시지와 바로 뒤의 실패 안내를 뺀 목록.
  static List<ChatMessage> _without(List<ChatMessage> messages, int index) {
    final bool noticeFollows =
        index + 1 < messages.length &&
        messages[index + 1].notice == ChatNotice.failure;
    return <ChatMessage>[
      for (int i = 0; i < messages.length; i++)
        if (i != index && !(noticeFollows && i == index + 1)) messages[i],
    ];
  }

  /// 앱이 아는 오늘 한도로 보내기 전에 막을지. 막지 않으면 null.
  ChatSendResult? _precheck(bool payWithPoints) {
    final AiChatQuota? quota = state.quota;
    if (quota == null) return null;
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
    return null;
  }

  /// [message] 를 [clientRequestId] 로 서버에 보낸다. 한도에 걸리면 방금 띄운 말풍선을
  /// 거두고(다시 보내기였다면 [restoreOnBlock] 으로 되돌리고), 망 오류면 메시지를
  /// `보내지 못함` 으로 남긴다.
  Future<ChatSendResult> _deliver(
    String message, {
    required bool payWithPoints,
    required String clientRequestId,
    List<ChatMessage>? restoreOnBlock,
  }) async {
    // 현재까지의 대화를 history 로 전달한다. 진행 중 placeholder 와 앱이 스스로
    // 띄운 말풍선(인사·실패 안내)은 뺀다 — 우리가 쓴 말을 서버에 대화로 되돌려
    // 줄 이유가 없고, 문구가 비어 있어 보내 봐야 빈 턴이 된다. 보내지 못한
    // 메시지는 남겨 두되 history 로는 보내지 않는다(#2846) — 서버가 받았는지 모른다.
    final List<ChatMessage> shown = state.messages
        .where((ChatMessage m) => !m.pending)
        .toList();
    final List<ChatMessage> history = <ChatMessage>[
      for (final ChatMessage m in shown)
        if (m.notice == null && !m.failed) m,
    ];

    // 방금 주고받는 것은 지금 시각이다 — 서버가 저장 시각을 따로 돌려주지
    // 않으므로 여기서 찍는다(#1918).
    final DateTime now = nowKst();
    // 다시 보내기면 처음 보낸 시각을 그대로 둔다 — 서버는 그 뒤에 저장한다.
    _sentAt.putIfAbsent(clientRequestId, _wallClock);
    // 키를 달아 둔다 — 복원분과 합칠 때 같은 요청인지 가른다.
    final ChatMessage mine = ChatMessage(
      role: ChatRole.user,
      content: message,
      at: now,
      clientRequestId: clientRequestId,
    );
    // 한도에 걸려 보내지 못하면 방금 띄운 두 말풍선만 거둔다(#2145). 보내기 전
    // 목록으로 통째로 되돌리면, 그 사이 끝난 복원분까지 함께 사라진다(#2642).
    // 인사는 대화가 시작되면 빠진다. 보내지 못한 메시지와 그 안내는 남긴다.
    final List<ChatMessage> before = state.messages;
    state = state.copyWith(
      messages: <ChatMessage>[
        for (final ChatMessage m in shown)
          if (m.notice != ChatNotice.welcome) m,
        mine,
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
        clientRequestId: clientRequestId,
      );
      // 답에 실려 온 감지 결과는 **방금 보낸 회원 메시지**에 붙인다(#1824).
      final List<ChatMessage> next = _replacePending(reply.withTime(nowKst()));
      final int mineAt = next.lastIndexWhere((ChatMessage m) => m.isUser);
      if (mineAt >= 0 && reply.replyToInsight != null) {
        next[mineAt] = next[mineAt].withInsight(reply.replyToInsight);
      }
      state = state.copyWith(
        messages: next,
        sending: false,
        quota: reply.replyQuota,
      );
      if (reply.replyQuota == null) await refreshQuota();
      return (outcome: ChatSendOutcome.sent, shortfall: 0);
    } on AiChatBlocked catch (blocked) {
      // 보내지 않은 말이다 — 방금 띄운 말풍선을 거두고 화면이 까닭을 안내한다.
      // 다시 보내기였다면 실패 메시지를 그대로 되돌려 둔다.
      state = state.copyWith(
        messages: restoreOnBlock != null && !state.restoring
            ? restoreOnBlock
            : _withdraw(mine, before),
        sending: false,
      );
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
      // 답을 받지 못했다. 회원이 쓴 말은 지우지 않고 `보내지 못함` 으로 남기고,
      // 처음 쓴 키를 함께 둔다 — 다시 보내면 같은 키로 간다(#2846).
      state = state.copyWith(
        messages: <ChatMessage>[
          for (final ChatMessage m in state.messages)
            if (identical(m, mine))
              m.asFailed(
                clientRequestId: clientRequestId,
                paidAttempt: payWithPoints,
              )
            else if (!m.pending)
              m,
          const ChatMessage(
            role: ChatRole.coach,
            content: '',
            notice: ChatNotice.failure,
          ),
        ],
        sending: false,
      );
      // 시간 초과여도 서버는 답을 저장했을 수 있다. 저장분에 이 질문의 답이
      // 있으면 실패 안내를 그 답으로 바꾼다.
      await _recoverFromHistory(clientRequestId);
      return (outcome: ChatSendOutcome.failed, shortfall: 0);
    }
  }

  /// 저장된 대화에 이 실패한 질문과 그 답이 있으면, 실패 메시지와 안내를 그 두
  /// 말로 바꾼다. (#2846)
  ///
  /// 확신할 수 없으면 바꾸지 않는다 — 실패로 남아도 `다시 보내기` 가 같은 키로 가서
  /// 서버가 저장한 답을 돌려주므로 안전하다. 저장된 대화는 키를 주지 않으므로, 같은
  /// 글의 회원 메시지가 이 질문을 보낸 시각 이후에 저장됐고 바로 뒤에 코치 답이
  /// 있을 때만 이 질문의 것으로 본다. 앞서 같은 글을 보내 답을 받은 질문이 있으면
  /// 저장분의 쌍을 그 질문부터 차례로 짝지어 둔다 — 같은 글을 일부러 두 번
  /// 보냈으면 앞의 것의 답을 뒤의 것에 붙이지 않는다.
  ///
  /// 그 쌍이 이미 화면에 있으면(보내는 사이 끝난 복원이 먼저 가져왔다) 실패 메시지와
  /// 안내만 거둔다 — 같은 질문·답을 두 번 두지 않는다.
  Future<void> _recoverFromHistory(String clientRequestId) async {
    final List<ChatMessage> stored;
    try {
      stored = await _repo.fetchHistory();
    } catch (_) {
      return;
    }
    if (!mounted || state.sending || stored.length < 2) return;
    final int index = state.messages.indexWhere(
      (ChatMessage m) => m.failed && m.clientRequestId == clientRequestId,
    );
    if (index < 0) return;
    final ChatMessage failed = state.messages[index];
    final DateTime? sentAt = _sentAt[clientRequestId];
    if (sentAt == null) return;
    final String text = failed.content.trim();

    // 앞서 이 화면에서 같은 글을 보내 답을 받은 질문이 먼저 제 쌍을 가져간다.
    final Set<int> claimed = <int>{};
    for (final ChatMessage m in state.messages.take(index)) {
      final String? key = m.clientRequestId;
      if (!m.isUser || m.failed || key == null) continue;
      if (m.content.trim() != text) continue;
      final DateTime? earlier = _sentAt[key];
      if (earlier == null) return; // 가를 수 없다 — 실패로 남긴다.
      final int i = _storedPairOf(stored, m, earlier, claimed);
      if (i >= 0) claimed.add(i);
    }
    final int at = _storedPairOf(stored, failed, sentAt, claimed);
    if (at < 0) return;
    final ChatMessage question = stored[at];
    final ChatMessage answer = stored[at + 1];

    // 복원이 먼저 가져와 화면에 있는 그 쌍 — 저장분과 글·시각이 같다.
    final bool shown = state.messages.any(
      (ChatMessage m) =>
          m.isUser &&
          !m.failed &&
          m.clientRequestId == null &&
          m.content.trim() == text &&
          m.at == question.at,
    );
    final List<ChatMessage> rest = _without(state.messages, index);
    state = state.copyWith(
      messages: shown
          ? rest
          : <ChatMessage>[
              ...rest.take(index),
              ChatMessage(
                role: ChatRole.user,
                content: failed.content,
                insight: question.insight,
                at: failed.at,
                clientRequestId: clientRequestId,
              ),
              answer.withTime(nowKst()),
              ...rest.skip(index),
            ],
    );
    await refreshQuota();
  }

  /// 보내지 못한 [mine] 과 대기 말풍선을 거둔다. 복원이 그 사이 끝나지 않았다면
  /// 보내기 전 모습 [before] 로 돌아간다 — 인사 말풍선도 함께 돌아온다.
  List<ChatMessage> _withdraw(ChatMessage mine, List<ChatMessage> before) {
    if (state.restoring) return before;
    final List<ChatMessage> rest = <ChatMessage>[
      for (final ChatMessage m in state.messages)
        if (!identical(m, mine) && !m.pending) m,
    ];
    return rest.isEmpty ? before : rest;
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

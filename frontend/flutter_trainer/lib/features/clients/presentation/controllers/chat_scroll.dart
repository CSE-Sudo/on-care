/// 회원 메시지가 새로 그려질 때 스크롤을 어떻게 할지 정하는 규칙. (#2749)
///
/// 예전에는 메시지 수가 바뀌기만 하면 맨 아래로 내렸다. 그러면 이전 쪽이
/// **앞에** 붙어도 맨 아래로 튀어, 방금 올려 읽던 자리를 잃는다. 무엇이
/// 바뀌었는지 — 맨 뒤인가, 맨 앞인가 — 로 가른다.
///
/// 회원 앱 `coach_chat_scroll.dart` 와 같은 규칙이다.
library;

/// 그린 대화의 양 끝과 길이.
class ChatEdges {
  /// Creates the edges.
  const ChatEdges({
    required this.oldestId,
    required this.newestId,
    required this.count,
  });

  /// 가장 오래된 메시지 id. 대화가 비었으면 null.
  final String? oldestId;

  /// 가장 새 메시지 id. 비었으면 null.
  final String? newestId;

  /// 그린 메시지 수.
  final int count;
}

/// 새로 그릴 때의 스크롤.
enum ChatScrollAction {
  /// 그대로 둔다 — 바뀐 것이 없다.
  none,

  /// 맨 아래로 — 처음 열었거나 새 메시지가 뒤에 붙었다.
  toBottom,

  /// 보던 자리를 지킨다 — 이전 메시지가 앞에만 붙었다.
  keepPosition,
}

/// [previous] 에서 [next] 로 바뀔 때의 스크롤. [previous] 가 null 이면 처음이다.
ChatScrollAction chatScrollAction(ChatEdges? previous, ChatEdges next) {
  if (previous == null) return ChatScrollAction.toBottom;
  final bool sameEnds =
      previous.oldestId == next.oldestId && previous.newestId == next.newestId;
  if (sameEnds && previous.count == next.count) return ChatScrollAction.none;
  // 맨 뒤가 바뀌었으면 새 말이 왔다 — 앞이 함께 바뀌었어도 새 말을 보여 준다.
  if (previous.newestId != next.newestId) return ChatScrollAction.toBottom;
  // 뒤는 그대로인데 앞이 바뀌었다 — 이전 쪽이 붙었다.
  if (previous.oldestId != next.oldestId) {
    return previous.oldestId == null
        ? ChatScrollAction.toBottom
        : ChatScrollAction.keepPosition;
  }
  // 양 끝은 그대로인데 가운데 수만 달라졌다(틈을 메운 경우 등). 읽던 자리를
  // 흔들지 않는다.
  return ChatScrollAction.keepPosition;
}

/// 안읽음 합계 — **현재 명단에 있는 회원만** 더한다. (#2868)
///
/// 사이드바 `메시지` 배지, 메시지 탭 `안 읽음 N` 칩, 대시보드 `답장 필요` 가 같은
/// 규칙으로 센다. 예전에는 사이드바·메시지 칩이 안읽음 맵 전체를 더하고
/// 대시보드만 명단을 돌며 더해서, 담당 해제·동의 철회 회원 몫이 앞의 두 곳에만
/// 남았다 — 그 회원은 목록에 없어 열어 읽을 수도 없으니 배지가 0 이 되지 않았다.
///
/// 서버(`GET /trainer/chat/unread`)도 같은 회원을 빼지만, 서버가 고쳐지기 전
/// 배포나 데모 저장소에서도 화면끼리 같은 숫자를 보이도록 화면 쪽에서 한 번 더
/// 명단으로 거른다.
class RosterUnread {
  const RosterUnread({required this.messages, required this.conversations});

  /// 명단 회원의 안읽음 메시지 수 합계 — 사이드바 배지.
  final int messages;

  /// 안읽음이 하나 이상 있는 명단 회원 수 — 메시지 `안 읽음` 칩·대시보드.
  final int conversations;

  static const RosterUnread none = RosterUnread(messages: 0, conversations: 0);

  @override
  bool operator ==(Object other) =>
      other is RosterUnread &&
      other.messages == messages &&
      other.conversations == conversations;

  @override
  int get hashCode => Object.hash(messages, conversations);

  @override
  String toString() =>
      'RosterUnread(messages: $messages, conversations: $conversations)';
}

/// [unread] 중 [rosterIds] 에 든 회원 몫만 센다. 0 이하 값은 세지 않는다.
///
/// 같은 id 가 명단에 두 번 들어와도 한 번만 센다.
RosterUnread rosterUnreadOf({
  required Iterable<String> rosterIds,
  required Map<String, int> unread,
}) {
  var messages = 0;
  var conversations = 0;
  for (final id in rosterIds.toSet()) {
    final pending = unread[id] ?? 0;
    if (pending <= 0) continue;
    messages += pending;
    conversations++;
  }
  return RosterUnread(messages: messages, conversations: conversations);
}

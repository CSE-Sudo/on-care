/// 회원 대화를 쪽 단위로 받고 합치는 규칙. (#2749)
///
/// 서버(`GET /trainer/clients/{id}/chat`)는 대화를 한 번에 최신 [chatPageSize]
/// 건만 주고, 그 앞은 가장 오래된 메시지의 (`created_at`, `id`) 를
/// (`before`, `before_id`) 커서로 넘겨 받는다. 쪽을 여럿 받으면 그 사이가
/// 겹치거나 비지 않게 합쳐야 하는데, 이 일을 저장소·provider·화면마다 따로 하면
/// 규칙이 갈라진다. 그래서 여기 순수 함수로 모은다.
///
/// 회원 앱 `features/member_coach/domain/coach_chat_thread.dart` 와 같은 규칙이다
/// — 같은 대화를 두 앱이 같은 방식으로 이어 받는다.
library;

import 'package:oncare_trainer/shared/models/client_chat_message.dart';

/// 서버가 한 번에 주는 메시지 수. 서버 `limit` 기본값(50)과 같다.
///
/// 받은 쪽이 이보다 적으면 그 앞에는 메시지가 없다.
const int chatPageSize = 50;

/// 대화 순서 — 시각이 먼저, 같은 시각이면 id.
///
/// 서버 커서도 같은 짝(`created_at`, `id`)으로 가른다. 같은 초에 들어온 두
/// 메시지를 시각만으로 가르면 경계에서 하나가 빠지거나 두 번 온다.
int compareChatMessages(ClientChatMessage first, ClientChatMessage second) {
  final int byTime = first.createdAt.compareTo(second.createdAt);
  return byTime != 0 ? byTime : first.id.compareTo(second.id);
}

/// [older] 와 [newer] 를 id 로 합쳐 오래된→최신으로 돌려준다.
///
/// 같은 id 가 양쪽에 있으면 [newer] 쪽을 쓴다 — 나중에 받은 것이 서버의
/// 지금 모습이다(첨부가 채워졌거나 글이 바뀐 경우). 순서는 받은 차례가 아니라
/// [compareChatMessages] 로 정한다.
List<ClientChatMessage> mergeChatThread(
  Iterable<ClientChatMessage> older,
  Iterable<ClientChatMessage> newer,
) {
  final Map<String, ClientChatMessage> byId = <String, ClientChatMessage>{
    for (final ClientChatMessage m in older) m.id: m,
  };
  for (final ClientChatMessage m in newer) {
    byId[m.id] = m;
  }
  return byId.values.toList()..sort(compareChatMessages);
}

/// [all] 에서 서버가 줄 한 쪽을 잘라 준다 — [before] 보다 앞선 것 중 최신
/// [size] 건(오래된→최신). [before] 가 없으면 대화의 최신 쪽이다.
///
/// 데모 저장소와 테스트 대역이 서버와 **같은 쪽**을 주게 하려고 둔다. 데모가
/// 언제나 전부를 주면 쪽 사이의 경계가 데모에서만 없어 보인다.
List<ClientChatMessage> pageChatThread(
  Iterable<ClientChatMessage> all, {
  ClientChatMessage? before,
  int size = chatPageSize,
}) {
  final List<ClientChatMessage> sorted = all.toList()
    ..sort(compareChatMessages);
  final List<ClientChatMessage> earlier = before == null
      ? sorted
      : <ClientChatMessage>[
          for (final ClientChatMessage m in sorted)
            if (compareChatMessages(m, before) < 0) m,
        ];
  final int start = earlier.length > size ? earlier.length - size : 0;
  return earlier.sublist(start);
}

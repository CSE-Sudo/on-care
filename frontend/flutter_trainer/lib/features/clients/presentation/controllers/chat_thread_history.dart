/// 회원 메시지의 이전 쪽을 들고 있는 상태. (#2749)
///
/// 서버는 대화를 한 번에 최신 [chatPageSize] 건만 주고, 폴링
/// ([chatThreadProvider])도 언제나 그 최신 쪽만 다시 받는다. 위로 올려 손으로 더
/// 받은 옛 쪽을 폴링 결과에 담아 두면 3초 뒤 다음 폴링이 그것을 지운다. 그래서
/// 옛 쪽은 여기 따로 두고, 화면이 둘을 [mergeChatThread] 로 합쳐 그린다.
///
/// 회원 앱 `CoachChatHistory`(member_coach_providers.dart)와 같은 규칙이다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/clients/domain/chat_thread_paging.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

/// 틈을 메우러 거슬러 받을 쪽 수의 상한 — 커서가 앞으로 나가지 않는 서버를
/// 만나도 멈추게 한다.
const int maxChatGapFillPages = 20;

/// [ChatThreadHistory] 가 들고 있는 것.
class ChatThreadHistoryState {
  const ChatThreadHistoryState({
    this.messages = const <ClientChatMessage>[],
    this.loading = false,
    this.exhausted = false,
    this.failed = false,
  });

  /// 받아 둔 메시지(오래된→최신). 손으로 더 받아 온 옛 쪽과, 그 뒤로 폴링이
  /// 준 최신 쪽이 id 로 합쳐져 있다. 옛 쪽을 받기 전에는 비어 있다.
  final List<ClientChatMessage> messages;

  /// 지금 한 쪽을 받고 있는가.
  final bool loading;

  /// 더 받을 것이 없다 — 마지막으로 받은 쪽이 다 차지 않았다.
  final bool exhausted;

  /// 마지막 시도가 실패했다. 다시 누르면 같은 쪽을 다시 받는다.
  final bool failed;

  ChatThreadHistoryState copyWith({
    List<ClientChatMessage>? messages,
    bool? loading,
    bool? exhausted,
    bool? failed,
  }) => ChatThreadHistoryState(
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    exhausted: exhausted ?? this.exhausted,
    failed: failed ?? this.failed,
  );
}

/// 한 회원 대화의 이전 쪽. 인자는 회원 id 다.
class ChatThreadHistory
    extends AutoDisposeFamilyNotifier<ChatThreadHistoryState, String> {
  @override
  ChatThreadHistoryState build(String clientId) {
    // 저장소가 바뀌면(계정 전환·데모 전환) 받아 둔 옛 쪽도 버린다.
    ref
      ..watch(chatRepositoryProvider)
      ..listen<AsyncValue<List<ClientChatMessage>>>(
        chatThreadProvider(clientId),
        (_, AsyncValue<List<ClientChatMessage>> next) {
          final List<ClientChatMessage>? latest = next.valueOrNull;
          if (latest != null) absorbLatest(latest);
        },
      );
    return const ChatThreadHistoryState();
  }

  /// [oldest] 앞의 한 쪽을 더 받는다. [oldest] 는 지금 화면에 있는 가장 오래된
  /// 메시지다 — 화면이 합쳐 그리므로 커서는 화면이 안다.
  ///
  /// 이미 받는 중이거나 처음 메시지까지 받았으면 아무것도 하지 않는다.
  Future<void> loadOlder(ClientChatMessage oldest) async {
    if (state.loading || state.exhausted) return;
    state = state.copyWith(loading: true, failed: false);
    try {
      final List<ClientChatMessage> older = await ref
          .read(chatRepositoryProvider)
          .fetchOlder(arg, before: oldest);
      // 처음 옛 쪽을 받는 때에는 지금 보이는 최신 쪽도 함께 붙잡아 둔다 — 그래야
      // 다음 폴링이 앞으로 밀려도 경계가 남는다.
      final List<ClientChatMessage> latest =
          ref.read(chatThreadProvider(arg)).valueOrNull ??
          const <ClientChatMessage>[];
      state = ChatThreadHistoryState(
        messages: mergeChatThread(
          older,
          mergeChatThread(state.messages, latest),
        ),
        // 한 쪽이 다 차지 않았으면 그 앞에는 없다.
        exhausted: older.length < chatPageSize,
      );
    } on Object {
      // 못 받아 왔다고 받아 둔 것을 버리지 않는다 — 다시 누르면 된다.
      state = state.copyWith(loading: false, failed: true);
    }
  }

  /// 폴링이 준 최신 쪽 [latest] 를 받아 둔 것에 합친다.
  ///
  /// 옛 쪽을 받기 전에는 아무것도 하지 않는다 — 그때는 최신 쪽만으로 온전하다.
  ///
  /// 옛 쪽을 받은 뒤로는 폴링한 최신 쪽도 여기 모아 둔다. 폴링은 언제나 최신
  /// 50건만 주므로, 옛 쪽을 m[k] 앞까지 받아 둔 채 새 메시지가 오면 최신 쪽이
  /// m[k+1..] 로 밀려 경계의 m[k] 가 어느 쪽에도 없게 된다. 받은 쪽을 모두 id 로
  /// 합쳐 들고 있으면 폴링끼리 겹치는 한 틈이 생기지 않는다. 폴링 사이에 한 쪽이
  /// 넘게 와서 겹침이 끊기면 그 틈을 커서로 다시 받아 메운다.
  void absorbLatest(List<ClientChatMessage> latest) {
    if (state.messages.isEmpty || latest.isEmpty) return;
    final Set<String> known = <String>{
      for (final ClientChatMessage m in state.messages) m.id,
    };
    final bool overlaps = latest.any(
      (ClientChatMessage m) => known.contains(m.id),
    );
    state = state.copyWith(messages: mergeChatThread(state.messages, latest));
    // 겹치는 것이 하나도 없고 최신 쪽이 꽉 찼다면 그 사이에 받지 못한 것이
    // 있을 수 있다. 덜 찼다면 최신 쪽이 곧 대화 전체의 끝부분이라 틈이 없다.
    if (!overlaps && latest.length >= chatPageSize) {
      unawaited(_fillGap(latest.first, known));
    }
  }

  /// [from] 앞을 거슬러 받아, 이미 가진 [known] 에 닿을 때까지 채운다.
  Future<void> _fillGap(ClientChatMessage from, Set<String> known) async {
    ClientChatMessage cursor = from;
    for (int i = 0; i < maxChatGapFillPages; i++) {
      final List<ClientChatMessage> page;
      try {
        page = await ref
            .read(chatRepositoryProvider)
            .fetchOlder(arg, before: cursor);
      } on Object {
        // 채우지 못했다고 받아 둔 것을 버리지 않는다. 다음 폴링이 다시 본다.
        return;
      }
      if (page.isEmpty) return;
      state = state.copyWith(messages: mergeChatThread(state.messages, page));
      if (page.any((ClientChatMessage m) => known.contains(m.id)) ||
          page.length < chatPageSize) {
        return;
      }
      cursor = page.first;
    }
  }
}

/// 회원 대화의 이전 쪽 — 회원 id 별.
final chatThreadHistoryProvider = NotifierProvider.autoDispose
    .family<ChatThreadHistory, ChatThreadHistoryState, String>(
      ChatThreadHistory.new,
    );

/// 화면에 그릴 대화 — 받아 둔 이전 쪽과 폴링한 최신 쪽을 합친 것.
List<ClientChatMessage> visibleChatThread(
  ChatThreadHistoryState history,
  List<ClientChatMessage> latest,
) => history.messages.isEmpty
    ? latest
    : mergeChatThread(history.messages, latest);

/// 맨 위에서 이전 쪽을 더 받을 수 있는가.
///
/// 최신 쪽이 덜 찼다면 그 앞에는 없다. 한 번이라도 덜 찬 쪽을 받았다면
/// 처음 메시지까지 받은 것이다.
bool canLoadOlderChat(
  ChatThreadHistoryState history,
  List<ClientChatMessage> latest,
) => !history.exhausted && latest.length >= chatPageSize;

/// 서버처럼 쪽 단위로 답하는 채팅 저장소 대역. (#2749)
///
/// 폴링([watchThread])은 최신 [chatPageSize] 건만, [fetchOlder] 는 커서 앞의
/// 한 쪽만 준다. [thread] 를 바꾼 뒤 [poll] 을 부르면 다음 폴링 결과가 흐른다.
library;

import 'dart:async';

import 'package:oncare_trainer/features/clients/domain/chat_thread_paging.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

/// [count] 건짜리 대화. id 는 `m000`… 순서대로, 1분 간격이다.
List<ClientChatMessage> pagedChatThread(
  int count, {
  int startMinute = 0,
}) => <ClientChatMessage>[
  for (int i = startMinute; i < startMinute + count; i++) pagedChatMessage(i),
];

/// [i] 번째 메시지 — 본문은 `body-mNNN`.
ClientChatMessage pagedChatMessage(int i) {
  final String id = 'm${i.toString().padLeft(3, '0')}';
  return ClientChatMessage(
    id: id,
    sender: i.isEven ? ChatSender.client : ChatSender.trainer,
    body: 'body-$id',
    timeLabel: '10:00',
    createdAt: DateTime.utc(2026, 9, 14, 1).add(Duration(minutes: i)),
  );
}

class PagedChatRepository implements ChatRepository {
  PagedChatRepository(this.thread);

  /// 서버에 있는 대화 전체.
  List<ClientChatMessage> thread;

  /// [fetchOlder] 에 넘어온 커서들.
  final List<ClientChatMessage> olderCursors = <ClientChatMessage>[];

  /// 다음 [fetchOlder] 들을 실패시킨다.
  bool failOlder = false;

  /// 값이 있으면 [fetchOlder] 가 이것이 끝날 때까지 기다린다.
  Completer<void>? olderGate;

  final StreamController<List<ClientChatMessage>> _polls =
      StreamController<List<ClientChatMessage>>.broadcast();

  /// 폴링 한 번 — 지금 [thread] 의 최신 쪽을 흘린다.
  void poll() => _polls.add(pageChatThread(thread));

  Future<void> close() => _polls.close();

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) async* {
    yield pageChatThread(thread);
    yield* _polls.stream;
  }

  @override
  Future<List<ClientChatMessage>> fetchOlder(
    String clientId, {
    required ClientChatMessage before,
  }) async {
    olderCursors.add(before);
    final Completer<void>? gate = olderGate;
    if (gate != null) await gate.future;
    if (failOlder) throw StateError('older page failed');
    return pageChatThread(thread, before: before);
  }

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {}

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream<Map<String, int>>.value(const <String, int>{});

  @override
  Future<void> markThreadRead(String clientId) async {}
}

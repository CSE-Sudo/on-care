import 'package:dio/dio.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/core/utils/request_id.dart';
import 'package:oncare_trainer/features/clients/data/dtos/chat_dtos.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

/// Trainer↔member chat against the FastAPI backend. The thread is the same
/// row set the member app reads via `/me/coach/chat`, so a trainer message
/// is received in the member app and vice versa.
///
/// The thread is polled only while its screen is subscribed and the app is in
/// the foreground. Selected when `USE_MOCK_API=false` (see
/// [chatRepositoryProvider]).
class DioChatRepository implements ChatRepository {
  DioChatRepository(
    this._dio, {
    this.pollInterval = const Duration(seconds: 3),
    this.unreadPollInterval = badgePollInterval,
    this.requestIdFactory = newClientRequestId,
  });

  final Dio _dio;
  final Duration pollInterval;

  /// 안읽음 배지를 다시 세는 주기. 열려 있는 스레드보다 느슨하다 — 배지는
  /// '몇 초 안에' 가 아니라 '놓치지 않게' 가 목적이고, 한 번 읽을 때마다
  /// 담당 회원 전체를 세는 요청이다.
  final Duration unreadPollInterval;
  final String Function() requestIdFactory;
  final Map<({String clientId, String text}), String> _pendingRequestIds =
      <({String clientId, String text}), String>{};

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      activePollingStream<List<ClientChatMessage>>(
        load: () => _fetchThread(clientId),
        interval: pollInterval,
      );

  Future<List<ClientChatMessage>> _fetchThread(String clientId) async {
    final encodedId = Uri.encodeComponent(clientId);
    try {
      final res = await _dio.get<List<dynamic>>(
        '/trainer/clients/$encodedId/chat',
      );
      final data = res.data ?? const <dynamic>[];
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException(
                'Expected an object in the trainer chat response.',
              );
            }
            return chatMessageFromJson(item);
          })
          .toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {
    // reportWeekStart는 데모/드리프트 전용이다 — 실서버는 `/report/send-pdf`가
    // 첨부 메타데이터를 직접 붙이므로 이 경로로 오지 않는다.
    final trimmed = text.trim();
    if (trimmed.isEmpty && emoteId == null) return;
    final encodedId = Uri.encodeComponent(clientId);
    final payload = (clientId: clientId, text: trimmed);
    // 같은 이모티콘을 연달아 보내는 것은 흔한 일이라, 멱등키를 글로만 묶으면
    // 두 번째가 재시도로 접힌다. 이모티콘은 누를 때마다 새 키를 만든다.
    final requestId = emoteId != null
        ? requestIdFactory()
        : _pendingRequestIds.putIfAbsent(payload, requestIdFactory);
    try {
      await _dio.post<Map<String, Object?>>(
        '/trainer/clients/$encodedId/chat',
        data: <String, Object?>{
          'text': trimmed,
          'client_request_id': requestId,
          'emote_id': ?emoteId,
        },
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
    if (_pendingRequestIds[payload] == requestId) {
      _pendingRequestIds.remove(payload);
    }
  }

  /// 안읽음 수를 주기적으로 다시 센다.
  ///
  /// 한 번만 읽고 끝내면 트레이너가 채팅을 열기 전까지 배지가 처음 센 숫자에
  /// 멈춰, 회원이 보낸 새 메시지가 사이드바에도 대시보드 '답장 필요' 에도
  /// 나타나지 않는다 — 콘솔을 하루 종일 띄워 두는 화면에서 놓치는 경로가
  /// 된다(#917). 쓰기 직후의 즉시 반영은 지금처럼 provider invalidate 가
  /// 맡고, 여기서는 회원 쪽에서 일어난 변화를 따라잡는다.
  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      activePollingStream<Map<String, int>>(
        load: _fetchUnread,
        interval: unreadPollInterval,
      );

  Future<Map<String, int>> _fetchUnread() async {
    try {
      final res = await _dio.get<Map<String, Object?>>('/trainer/chat/unread');
      final data = res.data ?? const <String, Object?>{};
      return <String, int>{
        for (final entry in data.entries)
          // Fail loud on a non-numeric count instead of silently dropping
          // it, matching every other response parser in this class —
          // a malformed entry here previously vanished from the roster
          // badges with no signal (review).
          entry.key: switch (entry.value) {
            final num n => n.toInt(),
            _ => throw FormatException(
              'Expected a numeric unread count for "${entry.key}".',
            ),
          },
      };
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> markThreadRead(String clientId) async {
    final encodedId = Uri.encodeComponent(clientId);
    try {
      await _dio.post<Map<String, Object?>>(
        '/trainer/clients/$encodedId/chat/read',
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

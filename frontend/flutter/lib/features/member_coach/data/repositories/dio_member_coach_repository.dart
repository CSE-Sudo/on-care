import 'package:dio/dio.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/utils/active_polling_stream.dart';
import 'package:oncare/core/utils/request_id.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';

/// Reads the member's coach + received routines + chat from the FastAPI
/// backend. The chat thread is the same one the trainer app writes to, so
/// messages and routines flow both ways.
class DioMemberCoachRepository implements MemberCoachRepository {
  DioMemberCoachRepository(
    this._dio, {
    this.pollInterval = const Duration(seconds: 3),
    String Function() requestIdFactory = newClientRequestId,
  }) : _requestIdFactory = requestIdFactory;

  final Dio _dio;
  final Duration pollInterval;
  final String Function() _requestIdFactory;
  final Map<String, String> _pendingRequestIds = <String, String>{};

  @override
  Future<MemberCoach?> fetchCoach() async {
    try {
      final res = await _dio.get<Map<String, Object?>>('/me/coach');
      final data = res.data;
      return data == null ? null : memberCoachFromJson(data);
    } on DioException catch (e) {
      // No assigned coach yet → 404 is an expected empty state, not an error.
      if (e.response?.statusCode == 404) return null;
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<CoachRoutine>> fetchRoutines() =>
      _getList('/me/coach/routines', coachRoutineFromJson);

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    required int minutes,
    String intensity = 'moderate',
  }) async {
    try {
      final Response<Map<String, Object?>> response = await _dio.post(
        '/me/coach/routines/$routineId/complete',
        data: <String, Object?>{'minutes': minutes, 'intensity': intensity},
      );
      final Map<String, Object?>? data = response.data;
      if (data == null) {
        throw const FormatException('Missing completed routine.');
      }
      return coachRoutineFromJson(data);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<CoachRoutine> uncompleteRoutine(String routineId) async {
    try {
      final Response<Map<String, Object?>> response = await _dio.delete(
        '/me/coach/routines/$routineId/complete',
      );
      final Map<String, Object?>? data = response.data;
      if (data == null) {
        throw const FormatException('Missing routine.');
      }
      return coachRoutineFromJson(data);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> deleteRoutine(String routineId) async {
    try {
      await _dio.delete<void>('/me/coach/routines/$routineId');
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<CoachSession>> fetchSessions() =>
      _getList('/me/coach/sessions', coachSessionFromJson);

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async {
    final List<CoachMessage> messages = await _getList(
      '/me/coach/chat',
      coachMessageFromJson,
      // 커서는 시각과 id 를 함께 넘긴다 — 같은 초에 들어온 메시지가 둘이면
      // 시각만으로는 경계가 갈리지 않는다(서버도 같은 짝으로 본다).
      query: before == null
          ? null
          : <String, Object?>{
              'before': before.createdAt.toUtc().toIso8601String(),
              'before_id': before.id,
            },
    );
    messages.sort((CoachMessage first, CoachMessage second) {
      final int createdAtOrder = first.createdAt.compareTo(second.createdAt);
      if (createdAtOrder != 0) return createdAtOrder;
      return first.id.compareTo(second.id);
    });
    return messages;
  }

  @override
  Stream<List<CoachMessage>> watchChat() =>
      activePollingStream<List<CoachMessage>>(
        load: fetchChat,
        interval: pollInterval,
      );

  @override
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final requestId = _pendingRequestIds.putIfAbsent(
      trimmed,
      _requestIdFactory,
    );
    try {
      await _dio.post<Map<String, Object?>>(
        '/me/coach/chat',
        data: <String, Object?>{
          'text': trimmed,
          'client_request_id': requestId,
        },
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
    if (_pendingRequestIds[trimmed] == requestId) {
      _pendingRequestIds.remove(trimmed);
    }
  }

  @override
  Future<void> markRead() async {
    try {
      await _dio.post<Map<String, Object?>>('/me/coach/chat/read');
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<int> unreadCount() async {
    try {
      final res = await _dio.get<Map<String, Object?>>('/me/coach/chat/unread');
      final Object? unread = res.data?['unread'];
      if (unread is! int || unread < 0) {
        throw const FormatException('Invalid unread message count.');
      }
      return unread;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return 0;
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<CoachInvite>> fetchInvites() =>
      _getList('/me/coach/invites', coachInviteFromJson);

  @override
  Future<void> acceptInvite(
    String inviteId, {
    required bool dataSharingConsent,
  }) => _decideInvite(
    inviteId,
    'accept',
    body: <String, Object?>{'data_sharing_consent': dataSharingConsent},
  );

  @override
  Future<void> rejectInvite(String inviteId) =>
      _decideInvite(inviteId, 'reject');

  Future<void> _decideInvite(
    String inviteId,
    String action, {
    Map<String, Object?>? body,
  }) async {
    try {
      await _dio.post<Map<String, Object?>>(
        '/me/coach/invites/${Uri.encodeComponent(inviteId)}/$action',
        data: body,
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  Future<List<T>> _getList<T>(
    String path,
    T Function(Map<String, Object?>) fromJson, {
    Map<String, Object?>? query,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        path,
        queryParameters: query,
      );
      final data = res.data ?? const <dynamic>[];
      return data
          .map((dynamic item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid member coach list item.');
            }
            return fromJson(item);
          })
          .toList(growable: false);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return <T>[];
      throw AppError.fromDio(e);
    }
  }
}

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/network/request_timeouts.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare_core/active_polling_stream.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_core/request_id.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Reads the member's coach + received routines + chat from the FastAPI
/// backend. The chat thread is the same one the trainer app writes to, so
/// messages and routines flow both ways.
class DioMemberCoachRepository implements MemberCoachRepository {
  DioMemberCoachRepository(
    this._dio, {
    this.pollInterval = const Duration(seconds: 3),
    String Function() requestIdFactory = newClientRequestId,
    DateTime Function() now = nowKst,
  }) : _requestIdFactory = requestIdFactory,
       _now = now;

  /// 응답을 받지 못한 글 전송의 키를 붙들어 두는 시간. (#3346)
  ///
  /// 재시도는 실패 직후에 한다. 한참 뒤 같은 문장을 또 쓰면 그건 새 메시지인데,
  /// 옛 키로 가면 서버가 먼저 받은 메시지를 돌려주고 새 글은 저장하지 않는다.
  static const Duration pendingRequestTtl = Duration(minutes: 5);

  final Dio _dio;
  final Duration pollInterval;
  final String Function() _requestIdFactory;
  final DateTime Function() _now;

  /// 보낸 글 → 응답을 아직 못 받은 전송 키.
  final Map<String, _PendingSend> _pendingRequestIds = <String, _PendingSend>{};

  /// 마지막으로 읽은 대화(최신 쪽)의 메시지 id. 전송 키를 만들 때 이미 있던
  /// 메시지와, 그 뒤에 저장된 메시지를 가른다.
  Set<String> _threadIds = const <String>{};

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
  Future<List<CoachRoutine>> fetchRoutinesOn(DateTime day) => _getList(
    '/me/coach/routines',
    coachRoutineFromJson,
    // 서버가 KST 날짜로 읽는다(`YYYY-MM-DD`).
    query: <String, Object?>{'date': wireDate(day)},
  );

  @override
  Future<UpcomingRoutines?> fetchUpcomingRoutines() async {
    try {
      final Response<Map<String, Object?>> res = await _dio
          .get<Map<String, Object?>>('/me/coach/routines/upcoming');
      final Map<String, Object?>? data = res.data;
      return data == null ? null : upcomingRoutinesFromJson(data);
    } on DioException catch (e) {
      // 담당이 없으면 예정도 없다 — 목록처럼 빈 상태로 둔다.
      if (e.response?.statusCode == 404) return null;
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    int? minutes,
    int? durationSeconds,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String intensity = 'moderate',
    DateTime? day,
  }) async {
    try {
      final Response<Map<String, Object?>> response = await _dio.post(
        '/me/coach/routines/$routineId/complete',
        // 지난 날짜만 싣는다(#2506) — 없으면 서버가 오늘로 적는다.
        queryParameters: day == null
            ? null
            : <String, Object?>{'date': wireDate(day)},
        data: <String, Object?>{
          // 분을 모르면 싣지 않는다 — 서버가 세트 수·초·배정 시간에서 채운다.
          // 0 이하는 서버가 거절해(422) 그때도 뺀다(#3364).
          if (minutes != null && minutes > 0) 'minutes': minutes,
          // 서버는 0 이하를 거절한다(422) — 초가 없거나 0 이면 키를 싣지 않고
          // 분만 보낸다(#2221).
          if (durationSeconds != null && durationSeconds > 0)
            'duration_seconds': durationSeconds,
          // 근력 완료의 실제 값(#3364). 비운 값은 서버가 배정 값으로 남긴다.
          // 한 세트는 회로든 초로든 한 번만 잰다 — 초가 있으면 횟수를 뺀다.
          if (sets != null && sets > 0) 'sets': sets,
          if (holdSeconds != null && holdSeconds > 0)
            'hold_seconds': holdSeconds
          else if (reps != null && reps > 0)
            'reps': reps,
          if (weight != null && weight >= 0) 'weight': weight,
          'intensity': intensity,
        },
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
  Future<CoachRoutine> uncompleteRoutine(
    String routineId, {
    DateTime? day,
  }) async {
    try {
      final Response<Map<String, Object?>> response = await _dio.delete(
        '/me/coach/routines/$routineId/complete',
        queryParameters: day == null
            ? null
            : <String, Object?>{'date': wireDate(day)},
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
      // 대화의 404 는 "기록 없음" 이 아니라 담당 해제다(#2843).
      notFoundMeansUnassigned: true,
      // 커서는 시각과 id 를 함께 넘긴다 — 같은 초에 들어온 메시지가 둘이면
      // 시각만으로는 경계가 갈리지 않는다(서버도 같은 짝으로 본다).
      query: before == null
          ? null
          : <String, Object?>{
              'before': kstWallToUtc(before.createdAt).toIso8601String(),
              'before_id': before.id,
            },
    );
    messages.sort((CoachMessage first, CoachMessage second) {
      final int createdAtOrder = first.createdAt.compareTo(second.createdAt);
      if (createdAtOrder != 0) return createdAtOrder;
      return first.id.compareTo(second.id);
    });
    if (before == null) _settlePendingSends(messages);
    return messages;
  }

  /// 대화에 저장이 확인된 글의 전송 키를 버린다. (#3346)
  ///
  /// 응답만 끊기고 서버는 받은 글이 여기 해당한다 — 키를 만든 뒤에 생긴 내
  /// 메시지 가운데 같은 글이 있으면 그 전송은 끝난 것이다. 남겨 두면 같은
  /// 문장을 다음에 보낼 때 그 키가 다시 쓰여 새 글이 가지 않는다.
  void _settlePendingSends(List<CoachMessage> latest) {
    if (_pendingRequestIds.isNotEmpty) {
      _pendingRequestIds.removeWhere(
        (String text, _PendingSend pending) => latest.any(
          (CoachMessage m) =>
              m.fromMe &&
              m.emoteId == null &&
              m.body.trim() == text &&
              !pending.knownIds.contains(m.id),
        ),
      );
    }
    _threadIds = <String>{for (final CoachMessage m in latest) m.id};
  }

  /// [text] 를 보낼 전송 키. 응답을 못 받은 같은 글의 키가 살아 있으면 그것을
  /// 다시 쓰고, 수명이 지났으면 새로 만든다.
  String _requestIdFor(String text) {
    final DateTime now = _now();
    _pendingRequestIds.removeWhere(
      (_, _PendingSend pending) =>
          now.difference(pending.createdAt) >= pendingRequestTtl,
    );
    return _pendingRequestIds
        .putIfAbsent(
          text,
          () => _PendingSend(
            id: _requestIdFactory(),
            createdAt: now,
            knownIds: _threadIds,
          ),
        )
        .id;
  }

  /// 전송 실패를 원인별 값으로 옮긴다 — 글·이모티콘·사진·주간 피드백이 같은
  /// 매핑을 쓴다. 서버가 분명히 거절한 것만 [CoachSendRejected] 다. (#3346)
  static Object _sendError(DioException e) =>
      CoachSendRejected.fromStatus(
        e.type == DioExceptionType.badResponse ? e.response?.statusCode : null,
      ) ??
      AppError.fromDio(e);

  @override
  Future<ReceivedReportsPage> fetchReceivedReports({DateTime? before}) async {
    try {
      final Response<Map<String, Object?>> res = await _dio
          .get<Map<String, Object?>>(
            '/me/coach/reports',
            // 커서는 앞 쪽 마지막 줄의 주(월요일)다.
            queryParameters: before == null
                ? null
                : <String, Object?>{'before': wireDate(before)},
          );
      final Map<String, Object?>? data = res.data;
      if (data == null) {
        throw const FormatException('Invalid received reports.');
      }
      return receivedReportsPageFromJson(data);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Stream<List<CoachMessage>> watchChat() =>
      activePollingStream<List<CoachMessage>>(
        load: fetchChat,
        interval: pollInterval,
        // 해제는 잠깐의 실패가 아니다 — 받아 둔 대화가 있어도 알린다.
        surfaceError: (Object error) => error is CoachUnassignedException,
      );

  @override
  Future<void> sendMessage(String text, {String? emoteId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && emoteId == null) return;
    // 같은 이모티콘을 연달아 보내는 것은 흔한 일이라, 멱등키를 글로만 묶으면
    // 두 번째가 재시도로 접힌다. 이모티콘은 누를 때마다 새 키를 만든다.
    final String requestId = emoteId != null
        ? _requestIdFactory()
        : _requestIdFor(trimmed);
    try {
      await _dio.post<Map<String, Object?>>(
        '/me/coach/chat',
        data: <String, Object?>{
          'text': trimmed,
          'client_request_id': requestId,
          'emote_id': ?emoteId,
        },
      );
    } on DioException catch (e) {
      final Object error = _sendError(e);
      // 거절된 키는 다시 보내도 같은 답이다 — 버려서 다음 전송이 새 키로 간다.
      if (error is CoachSendRejected) _forgetPendingSend(trimmed, requestId);
      throw error;
    }
    _forgetPendingSend(trimmed, requestId);
  }

  void _forgetPendingSend(String text, String requestId) {
    if (_pendingRequestIds[text]?.id == requestId) {
      _pendingRequestIds.remove(text);
    }
  }

  @override
  Future<CoachMessage> sendPhoto(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String clientRequestId,
    String text = '',
  }) async {
    try {
      final Response<Map<String, Object?>> res = await _dio
          .post<Map<String, Object?>>(
            '/me/coach/chat/image',
            data: FormData.fromMap(<String, Object?>{
              'image': MultipartFile.fromBytes(
                bytes,
                filename: fileName,
                contentType: DioMediaType.parse(mimeType),
              ),
              'message': text.trim(),
              'client_request_id': clientRequestId,
            }),
            // 느린 회선에서도 사진을 끝까지 올리도록 보내기 한도만 늘린다(#3141).
            // 서버는 받은 사진을 저장만 하므로 응답 대기는 전역 한도 그대로다.
            options: Options(sendTimeout: photoUploadSendTimeout),
          );
      final Map<String, Object?>? data = res.data;
      if (data == null) {
        throw const FormatException('Missing sent chat photo.');
      }
      return coachMessageFromJson(data);
    } on DioException catch (e) {
      throw _sendError(e);
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
  Future<MemberWeeklyFeedback> fetchWeeklyFeedback({
    DateTime? weekStart,
  }) async {
    try {
      final Response<Map<String, Object?>> res = await _dio.get(
        '/me/coach/weekly-feedback',
        // 비워 두면 서버가 지난 주로 읽는다 — 주 경계 계산을 앱과 서버 두 곳에
        // 두면 한쪽만 틀리는 날이 온다(#2232).
        queryParameters: weekStart == null
            ? null
            : <String, Object?>{'week_start': wireDate(weekStart)},
      );
      final Map<String, Object?>? data = res.data;
      if (data == null) {
        throw const FormatException('Missing weekly feedback.');
      }
      return memberWeeklyFeedbackFromJson(data);
    } on DioException catch (e) {
      // 담당 트레이너가 없으면 404 다. 그건 오류가 아니라 이 기능이 없는
      // 상태라, 화면이 칸을 통째로 숨기면 된다.
      if (e.response?.statusCode == 404) {
        return MemberWeeklyFeedback.empty(weekStart ?? manualFeedbackWeek());
      }
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<MemberWeeklyFeedback> saveWeeklyFeedback({
    required DateTime weekStart,
    required WeekCondition condition,
    required WeekIntensity intensity,
    String painArea = '',
    DateTime? painOn,
    String note = '',
  }) async {
    try {
      final Response<Map<String, Object?>> res = await _dio.put(
        '/me/coach/weekly-feedback',
        data: <String, Object?>{
          'week_start': wireDate(weekStart),
          'condition': condition.wire,
          'intensity': intensity.wire,
          'pain_area': painArea.trim(),
          // 아픈 곳을 안 적었으면 날짜도 보내지 않는다 — 서버가 같은 규칙으로
          // 지우지만, 보내는 쪽에서 이미 맞춰 둔다.
          'pain_on': painArea.trim().isEmpty || painOn == null
              ? ''
              : wireDate(painOn),
          'note': note.trim(),
        },
      );
      final Map<String, Object?>? data = res.data;
      if (data == null) {
        throw const FormatException('Missing saved weekly feedback.');
      }
      return memberWeeklyFeedbackFromJson(data);
    } on DioException catch (e) {
      throw _sendError(e);
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
    bool notFoundMeansUnassigned = false,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(path, queryParameters: query);
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
      if (e.response?.statusCode == 404) {
        if (notFoundMeansUnassigned) throw const CoachUnassignedException();
        return <T>[];
      }
      throw AppError.fromDio(e);
    }
  }
}

/// 응답을 아직 못 받은 글 전송 하나. (#3346)
class _PendingSend {
  const _PendingSend({
    required this.id,
    required this.createdAt,
    required this.knownIds,
  });

  /// 전송 키(`client_request_id`).
  final String id;

  /// 키를 만든 때 — 수명을 잰다.
  final DateTime createdAt;

  /// 키를 만들 때 이미 대화에 있던 메시지 id. 같은 글이 전에도 있었다면 그것을
  /// 이 전송의 저장으로 잘못 읽지 않는다.
  final Set<String> knownIds;
}

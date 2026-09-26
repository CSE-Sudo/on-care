import 'dart:async';

import 'package:dio/dio.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/request_id.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_recurrence.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';

typedef _ScheduleCreatePayload = ({
  String date,
  String clientName,
  String? clientId,
  String time,
  String type,
  int durationMinutes,
  String note,
});

/// The trainer's timeline against the FastAPI backend
/// (`/v1/trainer/schedule*`). Selected when `USE_MOCK_API=false`.
///
/// The drift source is reactive — a booking written in one tab shows up
/// in another because both watch the same table. HTTP has no such
/// channel, so this keeps a broadcast "revision" tick: every mutation
/// bumps it, and every read re-fetches. That reproduces the behaviour the
/// screens already rely on (add a session → the timeline updates itself)
/// without each of them having to remember to invalidate providers.
class DioScheduleRepository implements ScheduleRepository {
  /// Creates the repository over [_dio].
  DioScheduleRepository(
    this._dio, {
    this.pollInterval = const Duration(seconds: 5),
    this.requestIdFactory = newClientRequestId,
  });

  final Dio _dio;
  final Duration pollInterval;
  final String Function() requestIdFactory;
  final Map<_ScheduleCreatePayload, String> _pendingRequestIds =
      <_ScheduleCreatePayload, String>{};

  final StreamController<void> _revisions = StreamController<void>.broadcast();

  /// Emits once on listen, after every successful local mutation, and on a
  /// short interval while a schedule consumer is visible. The periodic read
  /// is what picks up reservations and cancellations written by the member
  /// app; [_revisions] keeps trainer-side writes immediate.
  Stream<T> _live<T>(Future<T> Function() read, {bool pollExternal = false}) =>
      activePollingStream<T>(
        load: read,
        interval: pollExternal ? pollInterval : null,
        refreshes: _revisions.stream,
      );

  void _bump() {
    if (!_revisions.isClosed) _revisions.add(null);
  }

  /// Closes the revision channel. Called by the provider's `onDispose`.
  void dispose() => unawaited(_revisions.close());

  @override
  Stream<List<ScheduleSession>> watchToday() => watchDate(ymd(nowKst()));

  @override
  Stream<List<ScheduleSession>> watchDate(String date) =>
      _live(() => _fetch(<String, String>{'date': date}));

  @override
  Stream<List<ScheduleSession>> watchRange(String fromDate, String toDate) =>
      _live(
        () => _fetch(<String, String>{'from': fromDate, 'to': toDate}),
        pollExternal: true,
      );

  /// `member_id` on its own means "every session for this client" — no
  /// date bounds. Standing in for that with a wide range would silently
  /// drop anything older than the range, and the screen reads a missing
  /// row as "no record" rather than "not fetched".
  /// Newest first, to match the drift source's ordering.
  @override
  Stream<List<ScheduleSession>> watchClientSessions(ScheduleClientKey client) {
    return _live(() async {
      final sessions = await _fetch(<String, String>{'member_id': client.id});
      return sessions.reversed.toList();
    });
  }

  /// 그날 타임라인을 한 번 읽어 이 회원 몫만 남긴다(#1581). 서버가 시간순으로
  /// 준다.
  @override
  Future<List<ScheduleSession>> fetchClientSessionsOn(
    ScheduleClientKey client,
    String date,
  ) async {
    final sessions = await _fetch(<String, String>{'date': date});
    return <ScheduleSession>[
      for (final session in sessions)
        if (session.clientId == client.id && !session.isGap) session,
    ];
  }

  /// Booked dates come from their own endpoint (a 90-day window server
  /// side), so this doesn't page the whole timeline to find them.
  @override
  Stream<Set<String>> watchBookedDates() {
    return _live(() async {
      try {
        final res = await _dio.get<List<dynamic>>(
          '/trainer/schedule/booked-dates',
        );
        return <String>{
          for (final d in res.data ?? const <dynamic>[])
            if (d is String) d,
        };
      } on DioException catch (e) {
        throw AppError.fromDio(e);
      }
    }, pollExternal: true);
  }

  @override
  Future<void> addSession({
    required String date,
    required String clientName,
    String? clientId,
    required String time,
    required String type,
    required int durationMinutes,
    String note = '',
  }) async {
    final payload = (
      date: date,
      clientName: clientName,
      clientId: clientId,
      time: time,
      type: type,
      durationMinutes: durationMinutes,
      note: note,
    );
    final requestId = _pendingRequestIds.putIfAbsent(payload, requestIdFactory);
    await _mutate(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/schedule',
        data: <String, Object?>{
          'date': date,
          'time': time,
          'client_name': clientName,
          'member_id': ?clientId,
          'type': type,
          'duration_minutes': durationMinutes,
          'note': note,
          'client_request_id': requestId,
        },
      ),
    );
    if (_pendingRequestIds[payload] == requestId) {
      _pendingRequestIds.remove(payload);
    }
  }

  @override
  Future<void> updateSession(
    String id, {
    String? date,
    required String clientName,
    String? clientId,
    required String time,
    required String type,
    required int durationMinutes,
    required String note,
  }) async {
    await _mutate(
      () => _dio.put<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}',
        data: <String, Object?>{
          'date': ?date,
          'client_name': clientName,
          'member_id': ?clientId,
          'time': time,
          'type': type,
          'duration_minutes': durationMinutes,
          'note': note,
        },
      ),
    );
  }

  @override
  Future<void> reopenSession(String id, {required String date}) async {
    await _mutate(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}/reopen',
        data: <String, Object?>{'date': date},
      ),
    );
  }

  /// Sends only `program`/`note` — the update endpoint is partial, so
  /// omitting the booking fields leaves them untouched.
  @override
  Future<void> updateProgram(
    String id, {
    required List<ProgramItem> program,
    required String note,
  }) async {
    await _mutate(
      () => _dio.put<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}',
        data: <String, Object?>{
          'program': programToJson(program),
          'note': note,
        },
      ),
    );
  }

  @override
  Future<bool> registerProgramSchedule({
    required String date,
    required String clientId,
    required String clientName,
    required String time,
    required int durationMinutes,
    required Map<String, Object?> assignment,
    required List<ProgramItem> program,
    String? sessionId,
    List<RoutineExercise> personalRoutines = const <RoutineExercise>[],
  }) async {
    late bool attachedToExisting;
    final memberId = Uri.encodeComponent(clientId);
    await _mutate(() async {
      final Response<Map<String, dynamic>> response;
      try {
        response = await _dio.post<Map<String, dynamic>>(
          '/trainer/clients/$memberId/program-schedule',
          data: programScheduleToJson(
            assignment: assignment,
            date: date,
            time: time,
            durationMinutes: durationMinutes,
            clientName: clientName,
            sessionId: sessionId,
            personalRoutines: personalRoutinesToJson(personalRoutines),
          ),
        );
      } on DioException catch (e) {
        // 연결할 회차를 정할 수 없다는 409 는 후보를 함께 싣는다(#1581) — 멱등키
        // 충돌 같은 다른 409 와 구분해 화면이 다시 고르게 안내할 수 있게 한다.
        if (_isAttachConflict(e)) throw const ProgramAttachConflictError();
        rethrow;
      }
      final attached = response.data?['attached_to_existing'];
      if (attached is! bool) {
        throw const FormatException(
          'program-schedule response is missing attached_to_existing',
        );
      }
      attachedToExisting = attached;
      return response;
    });
    return attachedToExisting;
  }

  @override
  Future<void> deleteSession(String id) async {
    await _mutate(
      () => _dio.delete<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}',
      ),
    );
  }

  @override
  Future<void> completeSession(String id, {String note = ''}) async {
    await _mutate(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}/complete',
        data: <String, Object?>{'note': note},
      ),
    );
  }

  @override
  Future<List<RoutineExercise>> fetchScheduledRoutines(String id) async {
    final res = await _dio.get<List<dynamic>>(
      '/trainer/schedule/${Uri.encodeComponent(id)}/routines',
    );
    return <RoutineExercise>[
      for (final row in res.data ?? const <dynamic>[])
        scheduledRoutineFromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> sendScheduledRoutines(
    String id, {
    List<RoutineExercise>? items,
  }) async {
    await _mutate(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}/routines/send',
        data: <String, Object?>{
          if (items != null) 'personal_routines': personalRoutinesToJson(items),
        },
      ),
    );
  }

  @override
  Future<void> dismissScheduledRoutines(String id) async {
    await _mutate(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}/routines/dismiss',
      ),
    );
  }

  @override
  Future<RecurrencePreview> previewRecurring({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/schedule/recurring/preview',
        data: _recurringBody(
          start: start,
          time: time,
          rule: rule,
          clientName: '',
          type: '',
          durationMinutes: 0,
        ),
      );
      final data = res.data ?? const <String, dynamic>{};
      return (
        dates: <DateTime>[
          for (final raw in (data['dates'] as List<dynamic>? ?? const []))
            if (raw is String) DateTime.parse(raw),
        ],
        conflicts: <ScheduleSession>[
          for (final row in (data['conflicts'] as List<dynamic>? ?? const []))
            if (row is Map<String, dynamic>) scheduleSessionFromJson(row),
        ],
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<ScheduleSession>> addRecurringSessions({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    required String clientName,
    String? clientId,
    required String type,
    required int durationMinutes,
    String note = '',
    String? clientRequestId,
  }) async {
    late final List<dynamic> rows;
    try {
      final res = await _dio.post<List<dynamic>>(
        '/trainer/schedule/recurring',
        data: _recurringBody(
          start: start,
          time: time,
          rule: rule,
          clientName: clientName,
          clientId: clientId,
          type: type,
          durationMinutes: durationMinutes,
          note: note,
          clientRequestId: clientRequestId,
        ),
      );
      rows = res.data ?? const <dynamic>[];
    } on DioException catch (e) {
      // 겹치는 회차는 서버가 409 와 함께 목록으로 알려 준다 — 화면이 어느 주가
      // 문제인지 짚어 줄 수 있도록 타입 있는 오류로 올린다(#870).
      final conflicts = _conflictsFrom(e);
      if (conflicts != null) throw ScheduleSeriesConflictError(conflicts);
      throw AppError.fromDio(e);
    }
    _bump();
    return <ScheduleSession>[
      for (final row in rows)
        if (row is Map<String, dynamic>) scheduleSessionFromJson(row),
    ];
  }

  Map<String, Object?> _recurringBody({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    required String clientName,
    String? clientId,
    required String type,
    required int durationMinutes,
    String note = '',
    String? clientRequestId,
  }) => <String, Object?>{
    'date': ymd(start),
    'time': time,
    'client_name': clientName,
    'member_id': ?clientId,
    'type': type,
    'duration_minutes': durationMinutes,
    'note': note,
    'weekdays': rule.weekdays.toList()..sort(),
    'count': ?rule.count,
    if (rule.until != null) 'until': ymd(rule.until!),
    'client_request_id': ?clientRequestId,
  };

  /// `일정 추가` 가 연결 대상을 정하지 못해 받은 409 인가(#1581).
  bool _isAttachConflict(DioException error) {
    if (error.response?.statusCode != 409) return false;
    final data = error.response?.data;
    return data is Map &&
        data['detail'] is Map &&
        (data['detail'] as Map).containsKey('candidates');
  }

  /// 409 응답에 실려 온 겹친 세션들. 다른 오류면 null.
  List<ScheduleSession>? _conflictsFrom(DioException error) {
    if (error.response?.statusCode != 409) return null;
    final detail = error.response?.data;
    if (detail is! Map) return null;
    final body = detail['detail'];
    if (body is! Map) return null;
    final rows = body['conflicts'];
    if (rows is! List) return null;
    return <ScheduleSession>[
      for (final row in rows)
        if (row is Map<String, dynamic>) scheduleSessionFromJson(row),
    ];
  }

  @override
  Future<void> cancelSession(
    String id, {
    required String source,
    String reason = '',
  }) async {
    await _mutate(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}/cancel',
        data: <String, Object?>{'source': source, 'reason': reason},
      ),
    );
  }

  @override
  Future<void> markNoShow(String id) async {
    await _mutate(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}/no-show',
      ),
    );
  }

  @override
  Future<void> sendProgram(String id, {String? clientRequestId}) async {
    await _mutate(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/schedule/${Uri.encodeComponent(id)}/program/send',
        data: <String, Object?>{'client_request_id': ?clientRequestId},
      ),
    );
  }

  Future<List<ScheduleSession>> _fetch(Map<String, String> query) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/trainer/schedule',
        queryParameters: query,
      );
      return <ScheduleSession>[
        for (final row in res.data ?? const <dynamic>[])
          if (row is Map<String, dynamic>) scheduleSessionFromJson(row),
      ];
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Runs a write and, only on success, tells the readers to re-fetch —
  /// a failed write must not make the timeline flicker as if something
  /// had changed.
  Future<void> _mutate(Future<Object?> Function() write) async {
    try {
      await write();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
    _bump();
  }
}

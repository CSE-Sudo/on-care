import 'package:dio/dio.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';

/// Assigns/reads a member's routines against the FastAPI backend. A routine
/// assigned here is what the member app receives via `/me/coach/routines`.
/// Selected when `USE_MOCK_API=false` (see [trainerRoutineRepositoryProvider]).
class DioTrainerRoutineRepository implements TrainerRoutineRepository {
  /// [fallbackName] 은 이름 없이 보낸 배정의 이름을 **보내는 순간의** 화면
  /// 언어로 돌려준다(#2301). 생략하면 한국어 기본 이름이다.
  DioTrainerRoutineRepository(this._dio, {this.fallbackName});

  final Dio _dio;

  /// 이름 없는 배정의 이름을 화면 언어로 돌려준다. `null` 이면 한국어 기본 이름.
  final String Function()? fallbackName;

  /// Assigns [routine] to [memberId].
  ///
  /// [clientRequestId] 를 주면 그 전송 시도에 대해 멱등하다 — 서버가
  /// `(trainer_id, member_id, client_request_id)` 로 중복을 막고, 같은 키의
  /// 재요청에는 먼저 저장된 배정을 그대로 돌려준다(#581). 그래서 네트워크
  /// 타임아웃처럼 결과를 알 수 없는 실패 뒤에도 **같은 키로** 안전하게 재시도할
  /// 수 있다. 키를 생략하면 예전처럼 매 호출이 새 배정이 된다.
  @override
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  }) async {
    final encodedId = Uri.encodeComponent(memberId);
    try {
      await _dio.post<Map<String, Object?>>(
        '/trainer/clients/$encodedId/routines',
        data: assignRoutineToJson(
          routine,
          clientRequestId: clientRequestId,
          fallbackName: fallbackName?.call() ?? kDefaultAiRoutineName,
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// Assigns a multi-session program in one request (#709).
  ///
  /// The whole program shares one `client_request_id`, so a retry after a
  /// dropped response does not leave the member with a half-assigned program.
  @override
  Future<void> assignProgram(
    String memberId,
    Map<String, Object?> payload,
  ) async {
    try {
      await _dio.post<List<dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(memberId)}/program',
        data: payload,
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    String? type,
    String? reason,
  }) async {
    // 보낼 필드만 담는다 — 서버의 부분 수정 규약(#495)에서 명시적 null 은 422 다.
    final body = <String, Object?>{
      if (name case final String value) 'name': value,
      if (minutes case final int value) 'minutes': value,
      if (type case final String value) 'type': value,
      if (reason case final String value) 'reason': value,
    };
    await _routineCall(
      () => _dio.put<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(memberId)}'
        '/routines/${Uri.encodeComponent(routineId)}',
        data: body,
      ),
      routineId,
    );
  }

  @override
  Future<void> deleteRoutine(String memberId, String routineId) async {
    await _routineCall(
      () => _dio.delete<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(memberId)}'
        '/routines/${Uri.encodeComponent(routineId)}',
      ),
      routineId,
    );
  }

  /// 404(없음·남의 배정)는 [StateError] 로 옮긴다 — 목과 실서버가 같은 예외를
  /// 내야 화면이 한 갈래만 다룬다. 나머지는 [AppError].
  Future<void> _routineCall(
    Future<void> Function() call,
    String routineId,
  ) async {
    try {
      await call();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw StateError('routine not found: $routineId');
      }
      throw AppError.fromDio(e);
    }
  }

  @override
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId) =>
      Stream<List<AssignedRoutine>>.fromFuture(_fetch(memberId));

  Future<List<AssignedRoutine>> _fetch(String memberId) async {
    final encodedId = Uri.encodeComponent(memberId);
    try {
      final res = await _dio.get<List<dynamic>>(
        '/trainer/clients/$encodedId/routines',
      );
      final data = res.data ?? const <dynamic>[];
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException(
                'Expected an object in the assigned-routine response.',
              );
            }
            return assignedRoutineFromJson(item);
          })
          .toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<SentDelivery?> fetchLatestDelivery(String memberId) async {
    final encodedId = Uri.encodeComponent(memberId);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/clients/$encodedId/deliveries/latest',
      );
      final data = res.data;
      // 보낸 적이 없으면 서버가 `null` 을 준다.
      if (data == null) return null;
      final session = data['session'];
      return SentDelivery(
        kind: (data['kind'] as String?) ?? DeliveryKinds.routineOnly,
        sentOn: DateTime.tryParse((data['sent_on'] as String?) ?? ''),
        session: session is Map<String, dynamic>
            ? scheduleSessionFromJson(session)
            : null,
        routines: <AssignedRoutine>[
          for (final row in (data['routines'] as List<dynamic>? ??
              const <dynamic>[]))
            if (row is Map<String, Object?>) assignedRoutineFromJson(row),
        ],
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

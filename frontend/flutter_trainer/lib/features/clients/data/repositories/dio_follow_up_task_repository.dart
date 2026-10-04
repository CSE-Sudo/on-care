import 'package:dio/dio.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';
import 'package:oncare_trainer/shared/services/follow_up_task_repository.dart';

/// 후속 관리 할 일을 FastAPI 백엔드에 저장한다 — 새로고침·재로그인·다른 브라우저
/// 어디서 열어도 같은 목록이 나온다(#869).
///
/// `USE_MOCK_API=false` 일 때 선택된다([followUpTaskRepositoryProvider]).
/// 담당하지 않는 고객은 404 로 돌아오고, 다른 client-scoped 읽기와 똑같이
/// 타입 있는 [AppError] 로 올라온다.
class DioFollowUpTaskRepository implements FollowUpTaskRepository {
  const DioFollowUpTaskRepository(this._dio);

  final Dio _dio;

  String _clientBase(String clientId) =>
      '/trainer/clients/${Uri.encodeComponent(clientId)}/follow-ups';

  static List<FollowUpTask> _decodeList(List<dynamic>? data) =>
      (data ?? const <dynamic>[])
          .map(
            (item) => FollowUpTask.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);

  @override
  Future<List<FollowUpTask>> fetchForClient(
    String clientId, {
    bool includeCompleted = false,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        _clientBase(clientId),
        queryParameters: <String, Object?>{
          if (includeCompleted) 'include_completed': true,
        },
      );
      return _decodeList(response.data);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<FollowUpTask> create(
    String clientId, {
    required String title,
    required DateTime dueDate,
    FollowUpContext context = FollowUpContext.general,
    String? clientRequestId,
    String memberName = '',
  }) async {
    try {
      final response = await _dio.post<Map<String, Object?>>(
        _clientBase(clientId),
        data: <String, Object?>{
          'title': title,
          'due_date': ymd(dueDate),
          'context_type': context.wire,
          // 서버가 이 키로 중복을 막는다 — 응답을 못 받고 다시 누른 저장이 같은
          // 할 일을 두 번 만들지 않는다.
          'client_request_id': ?clientRequestId,
        },
      );
      return FollowUpTask.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<FollowUpTask> update(
    String taskId, {
    String? title,
    DateTime? dueDate,
  }) async {
    try {
      final response = await _dio.put<Map<String, Object?>>(
        '/trainer/follow-ups/${Uri.encodeComponent(taskId)}',
        data: <String, Object?>{
          'title': ?title,
          if (dueDate != null) 'due_date': ymd(dueDate),
        },
      );
      return FollowUpTask.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<FollowUpTask> complete(String taskId) async {
    try {
      final response = await _dio.post<Map<String, Object?>>(
        '/trainer/follow-ups/${Uri.encodeComponent(taskId)}/complete',
      );
      return FollowUpTask.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }
}

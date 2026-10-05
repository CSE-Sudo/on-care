import 'package:dio/dio.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

/// Stores a trainer's per-member memos on the FastAPI backend so they
/// survive a re-login and follow the trainer to another browser (#706).
///
/// Selected when `USE_MOCK_API=false` (see [trainerMemoRepositoryProvider]).
/// A client this trainer isn't assigned to answers 404, which surfaces as a
/// typed [AppError] exactly like the other client-scoped reads.
class DioTrainerMemoRepository implements TrainerMemoRepository {
  const DioTrainerMemoRepository(this._dio);

  final Dio _dio;

  String _base(String clientId) =>
      '/trainer/clients/${Uri.encodeComponent(clientId)}/memos';

  @override
  Future<List<TrainerMemo>> fetch(String clientId) async {
    try {
      final response = await _dio.get<List<dynamic>>(_base(clientId));
      final data = response.data ?? const <dynamic>[];
      return data
          .map(
            (item) => TrainerMemo.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
    TrainerMemoRef? ref,
    TrainerMemoCategory category = TrainerMemoCategory.none,
  }) async {
    try {
      final response = await _dio.post<Map<String, Object?>>(
        _base(clientId),
        data: <String, Object?>{
          'body': body,
          'source': source.wire,
          // The server de-duplicates on this key, so a retried save of the
          // same chat insight returns the stored memo instead of adding one.
          'insight_id': ?insightId,
          if (insightKind.isNotEmpty) 'insight_kind': insightKind,
          // 기록은 id(이력 카드)나 날(회원 직접 기록 카드) 하나로만 가리킨다 —
          // 이름·날짜는 서버가 그 기록에서 읽는다(#2332).
          if (ref != null && ref.id != null)
            'ref_id': ref.id
          else if (ref != null) ...<String, Object?>{
            'ref_date': ?ref.day,
            // 그날의 어느 상자인가(#2508). 그날 전체(`day`)면 보내지 않는다.
            if (ref.kind != TrainerMemoRefKind.day) 'ref_kind': ref.kind.wire,
          },
          if (category != TrainerMemoCategory.none) 'category': category.wire,
        },
      );
      return TrainerMemo.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<TrainerMemo> update(
    String clientId,
    String memoId,
    String body, {
    TrainerMemoCategory? category,
  }) async {
    try {
      final response = await _dio.put<Map<String, Object?>>(
        '${_base(clientId)}/${Uri.encodeComponent(memoId)}',
        data: <String, Object?>{'body': body, 'category': ?category?.wire},
      );
      return TrainerMemo.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<void> delete(String clientId, String memoId) async {
    try {
      await _dio.delete<Map<String, Object?>>(
        '${_base(clientId)}/${Uri.encodeComponent(memoId)}',
      );
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }
}

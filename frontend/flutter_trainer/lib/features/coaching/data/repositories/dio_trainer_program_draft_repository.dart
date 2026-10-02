import 'package:dio/dio.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/trainer_program_draft.dart';

/// Stores the trainer's program drafts on the FastAPI backend so a draft
/// survives a reload, a page change and a re-login (#708).
///
/// Selected when `USE_MOCK_API=false` (see
/// [trainerProgramDraftRepositoryProvider]). Another trainer's draft answers
/// 404, which surfaces as a typed [AppError] like every other owned read.
class DioTrainerProgramDraftRepository
    implements TrainerProgramDraftRepository {
  const DioTrainerProgramDraftRepository(this._dio);

  final Dio _dio;

  static const String _base = '/trainer/programs';

  String _path(String id) => '$_base/${Uri.encodeComponent(id)}';

  @override
  Future<List<TrainerProgramDraftSummary>> list({String? memberId}) async {
    try {
      final response = memberId == null
          ? await _dio.get<List<dynamic>>(_base)
          : await _dio.get<List<dynamic>>(
              _base,
              queryParameters: <String, Object?>{'member_id': memberId},
            );
      final data = response.data ?? const <dynamic>[];
      return data
          .map(
            (item) => TrainerProgramDraftSummary.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<TrainerProgramDraft> read(String id) async {
    try {
      final response = await _dio.get<Map<String, Object?>>(_path(id));
      return TrainerProgramDraft.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<TrainerProgramDraft> create(Map<String, Object?> payload) async {
    try {
      final response = await _dio.post<Map<String, Object?>>(
        _base,
        data: payload,
      );
      return TrainerProgramDraft.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<TrainerProgramDraft> update(
    String id,
    Map<String, Object?> payload,
  ) async {
    try {
      final response = await _dio.put<Map<String, Object?>>(
        _path(id),
        data: payload,
      );
      return TrainerProgramDraft.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _dio.delete<Map<String, Object?>>(_path(id));
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }
}

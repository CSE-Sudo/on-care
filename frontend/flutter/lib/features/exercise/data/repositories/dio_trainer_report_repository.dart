import 'package:dio/dio.dart';

import 'package:oncare/features/exercise/domain/repositories/trainer_report_repository.dart';

/// 서버의 처리 전 중복 신고 코드. `trainer_report_service.ALREADY_OPEN_CODE` 와 같다.
const String kTrainerReportAlreadyOpenCode = 'report_already_open';

/// `POST /trainers/{id}/reports` 실 API (#3008).
class DioTrainerReportRepository implements TrainerReportRepository {
  DioTrainerReportRepository(this._dio);

  final Dio _dio;

  @override
  Future<void> report(
    String trainerId, {
    required TrainerReportReason reason,
    String memo = '',
  }) async {
    try {
      await _dio.post<Map<String, Object?>>(
        '/trainers/${Uri.encodeComponent(trainerId)}/reports',
        data: <String, Object?>{'reason': reason.wire, 'memo': memo.trim()},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final Object? detail = switch (e.response?.data) {
          final Map<String, Object?> body => body['detail'],
          _ => null,
        };
        if (detail is Map && detail['code'] == kTrainerReportAlreadyOpenCode) {
          throw const TrainerReportAlreadyOpen();
        }
      }
      rethrow;
    }
  }
}

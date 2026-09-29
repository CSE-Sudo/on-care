import 'package:dio/dio.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_options_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_context_source.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';

/// Generates A/B routine options from the member's real data via the
/// FastAPI backend. Selected when `USE_MOCK_API=false`.
class DioTrainerRoutineOptionsRepository
    implements TrainerRoutineOptionsRepository {
  DioTrainerRoutineOptionsRepository(this._dio);

  final Dio _dio;

  /// 루틴 생성 대기 시간. 전역 receiveTimeout(15초)으로는 모자란다.
  ///
  /// 생성은 회원 분석 + Gemini 호출이라 로컬 실측이 4.0~6.4초였다(사고 예산을
  /// 넘기기 전에는 10.9~12.8초로, 15초에 여유가 2초뿐이라 네트워크 지연이 붙으면
  /// 그대로 넘겼다 — #579). 여기서 앱만 먼저 포기하면 서버는 규칙형으로 정상
  /// 폴백해 200 을 돌려주는데도 트레이너는 "생성 실패"만 보게 된다.
  ///
  /// 회원 앱 AI 코치와 같은 값을 쓴다. 서버 쪽 LLM 타임아웃(#584)이 들어와도
  /// 그보다 넉넉해야 서버의 폴백 응답이 이기고, 앱은 실패 대신 결과를 받는다.
  static const Duration _generateTimeout = Duration(seconds: 60);

  @override
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
    Set<RoutineContextSource>? sources,
  }) async {
    final encodedId = Uri.encodeComponent(memberId);
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/trainer/clients/$encodedId/routine-options',
        data: <String, Object?>{
          'available_minutes': availableMinutes,
          'intensity_preference': intensityPreference,
          'trainer_note': trainerNote,
          // 보내지 않으면 서버 기본값이다 — 빈 목록과 구분해야 한다(#2587).
          if (sources != null)
            'sources': <String>[
              for (final RoutineContextSource source
                  in RoutineContextSource.values)
                if (sources.contains(source)) source.wire,
            ],
        },
        options: Options(receiveTimeout: _generateTimeout),
      );
      final data = res.data;
      if (data == null) {
        // 문구는 화면이 붙인다 — 리포지토리는 로케일을 모른다. (#501)
        throw const ServerError();
      }
      return routineOptionsFromJson(data);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

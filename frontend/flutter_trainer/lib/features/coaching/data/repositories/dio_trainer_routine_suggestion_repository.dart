import 'package:dio/dio.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_suggestion_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';

/// Reviews AI personal-exercise suggestions against the FastAPI backend.
///
/// 승인하면 서버가 그 행을 배정으로 바꾸고 회원에게 알림을 보낸다 — 별도의 배정
/// 호출이 없다. 그래서 이 클래스는 새 루틴을 만들지 않는다(#790).
/// `USE_MOCK_API=false` 일 때 선택된다.
class DioTrainerRoutineSuggestionRepository
    implements TrainerRoutineSuggestionRepository {
  /// Creates the repository over [_dio].
  DioTrainerRoutineSuggestionRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<RoutineSuggestion>> pending(String memberId) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/trainer/clients/${Uri.encodeComponent(memberId)}'
        '/routine-suggestions',
      );
      return <RoutineSuggestion>[
        for (final item in res.data ?? const <dynamic>[])
          if (item is Map<String, Object?>) routineSuggestionFromJson(item),
      ];
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> approve(
    String suggestionId, {
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String? reason,
  }) async {
    await _review(
      suggestionId,
      'approve',
      body: routineSuggestionApproveToJson(
        name: name,
        minutes: minutes,
        type: type,
        sets: sets,
        reps: reps,
        holdSeconds: holdSeconds,
        weight: weight,
        reason: reason,
      ),
    );
  }

  @override
  Future<void> dismiss(String suggestionId) async {
    await _review(suggestionId, 'dismiss');
  }

  /// 409 는 [RoutineSuggestionAlreadyReviewed] 로 옮긴다 — 화면이 "실패"가 아니라
  /// "이미 반영됨"으로 말할 수 있어야 한다. 404(없음·남의 회원)와 나머지는
  /// [AppError] 로 둔다.
  Future<void> _review(
    String suggestionId,
    String action, {
    Map<String, Object?>? body,
  }) async {
    try {
      await _dio.post<Map<String, Object?>>(
        '/trainer/routine-suggestions/${Uri.encodeComponent(suggestionId)}'
        '/$action',
        data: body,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw RoutineSuggestionAlreadyReviewed(suggestionId);
      }
      throw AppError.fromDio(e);
    }
  }
}

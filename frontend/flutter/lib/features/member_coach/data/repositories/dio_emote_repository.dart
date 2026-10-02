import 'package:dio/dio.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';
import 'package:oncare/features/member_coach/domain/repositories/emote_repository.dart';

class DioEmoteRepository implements EmoteRepository {
  DioEmoteRepository(this._dio);

  final Dio _dio;

  @override
  Future<EmoteState> fetchState() async {
    try {
      final res = await _dio.get<Map<String, Object?>>('/me/emotes');
      return EmoteState.fromJson(res.data!);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<EmoteState> unlock(
    String emoteId, {
    required String clientRequestId,
  }) async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/me/emotes/${Uri.encodeComponent(emoteId)}/unlock',
        // 키는 부르는 쪽이 구매 시도마다 하나 만든다 — 여기서 새로 만들면 응답을
        // 못 받고 다시 누른 구매가 다른 키로 가 409 가 된다. (#2845)
        data: <String, Object?>{'client_request_id': clientRequestId},
      );
      return EmoteState.fromJson(res.data!);
    } on DioException catch (e) {
      final EmoteUnlockRejected? rejected = EmoteUnlockRejected.fromResponse(
        e.response?.statusCode,
        e.response?.data,
      );
      if (rejected != null) throw rejected;
      throw AppError.fromDio(e);
    }
  }
}

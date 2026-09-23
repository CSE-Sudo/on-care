import 'package:dio/dio.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/utils/request_id.dart';
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
  Future<EmoteState> unlock(String emoteId) async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/me/emotes/${Uri.encodeComponent(emoteId)}/unlock',
        // 응답을 못 받고 다시 누른 구매가 포인트를 두 번 쓰지 않게 한다.
        data: <String, Object?>{'client_request_id': newClientRequestId()},
      );
      return EmoteState.fromJson(res.data!);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

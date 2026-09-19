import 'package:dio/dio.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/streak_shield_repository.dart';

/// `/me/streak-shields` 를 읽고 쓴다. (#1788)
class DioStreakShieldRepository implements StreakShieldRepository {
  const DioStreakShieldRepository(this._dio);

  final Dio _dio;

  /// 목업 인터셉터가 만든 409 응답은 상태코드 검사를 거치지 않고 돌아온다 —
  /// 성공 본문으로 읽지 않도록 실서버와 같은 오류로 바꾼다(사용처 저장소와 같다).
  static Map<String, Object?> _ok(Response<Map<String, Object?>> res) {
    final int status = res.statusCode ?? 0;
    if (status >= 400) {
      if (status == 404) throw const NotFoundError();
      if (status == 401 || status == 403) throw const UnauthorizedError();
      throw ServerError(statusCode: status);
    }
    final Map<String, Object?>? data = res.data;
    if (data == null) throw const ServerError();
    return data;
  }

  @override
  Future<StreakShields> fetch() async {
    try {
      return StreakShields.fromJson(
        _ok(await _dio.get<Map<String, Object?>>('/me/streak-shields')),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<StreakShields> use(DateTime date) async {
    try {
      return StreakShields.fromJson(
        _ok(
          await _dio.post<Map<String, Object?>>(
            '/me/streak-shields/use',
            data: <String, Object?>{'date': _ymd(date)},
          ),
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

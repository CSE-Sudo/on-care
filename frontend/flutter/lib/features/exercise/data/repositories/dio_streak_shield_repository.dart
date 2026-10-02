import 'package:dio/dio.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/streak_shield_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `/me/streak-shields` 를 읽고 쓴다. (#1788)
class DioStreakShieldRepository implements StreakShieldRepository {
  const DioStreakShieldRepository(this._dio);

  final Dio _dio;

  /// 본문이 비면 실서버와 같은 오류로 바꾼다. 오류 응답은 실서버·데모(로컬 목업
  /// API, #2743) 모두 `DioException` 으로 와 아래 `AppError.fromDio` 가 받는다.
  static Map<String, Object?> _ok(Response<Map<String, Object?>> res) {
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
            data: <String, Object?>{'date': wireDate(date)},
          ),
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

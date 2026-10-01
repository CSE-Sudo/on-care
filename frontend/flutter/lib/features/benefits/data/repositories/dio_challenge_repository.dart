import 'package:dio/dio.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/domain/repositories/challenge_repository.dart';

/// `/me/challenges*` 를 읽고 쓴다. (#1789)
///
/// 실모드는 백엔드로, 데모 모드는 `LocalApiInterceptor` 가 같은 경로를 받는다.
class DioChallengeRepository implements ChallengeRepository {
  const DioChallengeRepository(this._dio);

  final Dio _dio;

  /// 본문이 비면 실서버와 같은 오류로 바꾼다. 오류 응답은 실서버·데모(로컬 목업
  /// API, #2743) 모두 `DioException` 으로 와 아래 `AppError.fromDio` 가 받는다.
  static T _ok<T>(Response<T> res) {
    final T? data = res.data;
    if (data == null) throw const ServerError();
    return data;
  }

  @override
  Future<WeeklyChallenge> fetchWeekly() async {
    try {
      return WeeklyChallenge.fromJson(
        _ok(await _dio.get<Map<String, Object?>>('/me/challenges/weekly')),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<ChallengeJoin> join({String? clientRequestId}) async {
    try {
      return ChallengeJoin.fromJson(
        _ok(
          await _dio.post<Map<String, Object?>>(
            '/me/challenges/weekly/join',
            data: <String, Object?>{'client_request_id': ?clientRequestId},
          ),
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

}

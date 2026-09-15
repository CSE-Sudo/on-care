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

  /// 목업 인터셉터가 만든 응답은 상태코드 검사를 거치지 않고 그대로 돌아온다. 409
  /// (참가 기간 아님 등)를 성공 본문으로 읽지 않도록 실서버와 같은 오류로 바꾼다 —
  /// 사용처 저장소(`DioBenefitsRepository`)와 같은 처리다.
  static T _ok<T>(Response<T> res) {
    final int status = res.statusCode ?? 0;
    if (status >= 400) {
      if (status == 404) throw const NotFoundError();
      if (status == 401 || status == 403) throw const UnauthorizedError();
      throw ServerError(statusCode: status);
    }
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

  @override
  Future<List<Challenge>> fetchHistory() async {
    try {
      final List<Object?> rows = _ok(
        await _dio.get<List<Object?>>('/me/challenges'),
      );
      return <Challenge>[
        for (final Object? raw in rows)
          Challenge.fromJson(
            (raw! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
      ];
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

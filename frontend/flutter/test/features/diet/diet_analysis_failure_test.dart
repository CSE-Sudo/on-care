import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis_failure.dart';

AppError _fromStatus(int code) => AppError.fromDio(
  DioException(
    requestOptions: RequestOptions(path: '/diet/analyze'),
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: RequestOptions(path: '/diet/analyze'),
      statusCode: code,
    ),
  ),
);

void main() {
  group('DietAnalysisFailure.fromError', () {
    test('서버가 실제로 내는 코드를 각각 구분한다', () {
      // backend/app/api/v1/diet.py 가 내는 코드들.
      expect(
        DietAnalysisFailure.fromError(_fromStatus(415)),
        DietAnalysisFailure.unsupportedFormat,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(400)),
        DietAnalysisFailure.badRequest,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(401)),
        DietAnalysisFailure.unauthorized,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(403)),
        DietAnalysisFailure.forbidden,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(429)),
        DietAnalysisFailure.rateLimited,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(422)),
        DietAnalysisFailure.badRequest,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(501)),
        DietAnalysisFailure.notImplemented,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(502)),
        DietAnalysisFailure.recognitionFailed,
      );
    });

    test('네트워크·타임아웃·기타 5xx 는 일시 실패로 모은다', () {
      for (final DioExceptionType type in <DioExceptionType>[
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        expect(
          DietAnalysisFailure.fromError(
            AppError.fromDio(
              DioException(
                requestOptions: RequestOptions(path: '/diet/analyze'),
                type: type,
              ),
            ),
          ),
          DietAnalysisFailure.temporary,
          reason: '$type',
        );
      }
      expect(
        DietAnalysisFailure.fromError(_fromStatus(500)),
        DietAnalysisFailure.temporary,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(503)),
        DietAnalysisFailure.temporary,
      );
    });

    test('알 수 없는 예외는 재시도 가능한 일시 실패로 본다', () {
      // 멱등키가 있어 헛된 재시도는 무해하지만, 멀쩡한 사진을 못 쓴다고
      // 잘못 안내하면 사용자는 사진을 버리게 된다.
      expect(
        DietAnalysisFailure.fromError(StateError('boom')),
        DietAnalysisFailure.temporary,
      );
      expect(
        DietAnalysisFailure.fromError(const UnknownError()),
        DietAnalysisFailure.temporary,
      );
    });

    test('같은 사진 재시도가 통할 수 있을 때만 canRetry 가 참이다', () {
      expect(DietAnalysisFailure.unsupportedFormat.canRetry, isFalse);
      expect(DietAnalysisFailure.badRequest.canRetry, isFalse);
      expect(DietAnalysisFailure.unauthorized.canRetry, isFalse);
      expect(DietAnalysisFailure.forbidden.canRetry, isFalse);
      expect(DietAnalysisFailure.rateLimited.canRetry, isTrue);
      expect(DietAnalysisFailure.notImplemented.canRetry, isFalse);
      expect(DietAnalysisFailure.recognitionFailed.canRetry, isTrue);
      expect(DietAnalysisFailure.temporary.canRetry, isTrue);
    });
  });

  group('403·429 구분 (#2859)', () {
    test('403 은 로그인 만료가 아니다 — 권한·동의 문제다', () {
      expect(
        DietAnalysisFailure.fromError(_fromStatus(403)),
        isNot(DietAnalysisFailure.unauthorized),
      );
      expect(
        DietAnalysisFailure.fromError(const ForbiddenError()),
        DietAnalysisFailure.forbidden,
      );
    });

    test('429 는 잠시 뒤 다시 할 수 있는 실패다', () {
      expect(
        DietAnalysisFailure.fromError(const RateLimitedError()),
        DietAnalysisFailure.rateLimited,
      );
      expect(DietAnalysisFailure.rateLimited.canRetry, isTrue);
    });

    test('검증 오류(400·422)는 다른 사진을 고르게 한다', () {
      expect(
        DietAnalysisFailure.fromError(const ValidationError(statusCode: 400)),
        DietAnalysisFailure.badRequest,
      );
      expect(
        DietAnalysisFailure.fromError(const ValidationError(statusCode: 422)),
        DietAnalysisFailure.badRequest,
      );
    });

    test('목업이 상태 코드로 던지는 400 도 같은 뜻이다', () {
      expect(
        DietAnalysisFailure.fromError(const ServerError(statusCode: 400)),
        DietAnalysisFailure.badRequest,
      );
    });

    test('401 은 지금처럼 로그인 만료다', () {
      expect(
        DietAnalysisFailure.fromError(const UnauthorizedError()),
        DietAnalysisFailure.unauthorized,
      );
    });
  });
}

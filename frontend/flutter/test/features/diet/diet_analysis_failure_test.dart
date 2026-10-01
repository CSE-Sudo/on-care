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
        DietAnalysisFailure.unauthorized,
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

    test('코드 없는 429 는 잠시 뒤 다시 시도할 분당 한도로 본다', () {
      expect(
        DietAnalysisFailure.fromError(_fromStatus(429)),
        DietAnalysisFailure.rateLimited,
      );
      expect(
        DietAnalysisFailure.fromError(_fromStatus(422)),
        DietAnalysisFailure.badRequest,
      );
    });

    test('저장소가 던진 코드 거절은 그 이유를 그대로 쓴다', () {
      for (final DietAnalysisFailure f in <DietAnalysisFailure>[
        DietAnalysisFailure.noFood,
        DietAnalysisFailure.dailyLimit,
        DietAnalysisFailure.rateLimited,
        DietAnalysisFailure.unavailable,
      ]) {
        expect(DietAnalysisFailure.fromError(DietAnalysisRejected(f)), f);
      }
    });

    test('같은 사진 재시도가 통할 수 있을 때만 canRetry 가 참이다', () {
      expect(DietAnalysisFailure.unsupportedFormat.canRetry, isFalse);
      expect(DietAnalysisFailure.badRequest.canRetry, isFalse);
      expect(DietAnalysisFailure.unauthorized.canRetry, isFalse);
      expect(DietAnalysisFailure.notImplemented.canRetry, isFalse);
      expect(DietAnalysisFailure.recognitionFailed.canRetry, isTrue);
      expect(DietAnalysisFailure.temporary.canRetry, isTrue);
      expect(DietAnalysisFailure.noFood.canRetry, isFalse);
      expect(DietAnalysisFailure.dailyLimit.canRetry, isFalse);
      expect(DietAnalysisFailure.unavailable.canRetry, isFalse);
      expect(DietAnalysisFailure.rateLimited.canRetry, isTrue);
    });

    test('사진 길이 막힌 거절만 직접 추가를 권한다', () {
      expect(
        DietAnalysisFailure.values
            .where((DietAnalysisFailure f) => f.offersManualEntry)
            .toSet(),
        <DietAnalysisFailure>{
          DietAnalysisFailure.noFood,
          DietAnalysisFailure.dailyLimit,
          DietAnalysisFailure.rateLimited,
          DietAnalysisFailure.unavailable,
        },
      );
    });
  });

  group('DietAnalysisFailure.fromCode', () {
    test('서버 detail.code 를 거절 이유로 옮긴다', () {
      expect(
        DietAnalysisFailure.fromCode('no_food_detected'),
        DietAnalysisFailure.noFood,
      );
      expect(
        DietAnalysisFailure.fromCode('daily_limit'),
        DietAnalysisFailure.dailyLimit,
      );
      expect(
        DietAnalysisFailure.fromCode('rate_limited'),
        DietAnalysisFailure.rateLimited,
      );
      expect(
        DietAnalysisFailure.fromCode('analysis_unavailable'),
        DietAnalysisFailure.unavailable,
      );
      expect(DietAnalysisFailure.fromCode('unknown'), isNull);
      expect(DietAnalysisFailure.fromCode(null), isNull);
      expect(DietAnalysisFailure.fromCode(42), isNull);
    });
  });

  group('DietAnalysisRejected.fromResponseData', () {
    test('{detail: {code, message}} 를 읽는다', () {
      final DietAnalysisRejected? r = DietAnalysisRejected.fromResponseData(
        <String, Object?>{
          'detail': <String, Object?>{
            'code': 'daily_limit',
            'message': '오늘 사진 분석 횟수를 다 썼어요.',
          },
        },
      );
      expect(r?.failure, DietAnalysisFailure.dailyLimit);
      expect(r?.message, '오늘 사진 분석 횟수를 다 썼어요.');
    });

    test('코드가 없거나 모양이 다르면 null — AppError 로 넘긴다', () {
      expect(DietAnalysisRejected.fromResponseData(null), isNull);
      expect(DietAnalysisRejected.fromResponseData('oops'), isNull);
      expect(
        DietAnalysisRejected.fromResponseData(<String, Object?>{
          'detail': '문자열 detail',
        }),
        isNull,
      );
      expect(
        DietAnalysisRejected.fromResponseData(<String, Object?>{
          'detail': <Object?>[
            <String, Object?>{'type': 'missing'},
          ],
        }),
        isNull,
      );
      expect(
        DietAnalysisRejected.fromResponseData(<String, Object?>{
          'detail': <String, Object?>{'code': 'rate_limited', 'message': 3},
        })?.message,
        isNull,
      );
    });
  });
}

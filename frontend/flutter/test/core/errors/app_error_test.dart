import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/errors/app_error.dart';

void main() {
  RequestOptions opts() => RequestOptions(path: '/ping');

  /// [code] 로 끝난 응답. [body] 는 서버 응답 본문이다.
  AppError fromStatus(int code, {Object? body, String? dioMessage}) =>
      AppError.fromDio(
        DioException(
          requestOptions: opts(),
          type: DioExceptionType.badResponse,
          message: dioMessage,
          response: Response<Object?>(
            requestOptions: opts(),
            statusCode: code,
            data: body,
          ),
        ),
      );

  group('AppError.fromDio', () {
    test('timeouts → NetworkError', () {
      final e = AppError.fromDio(
        DioException(
          requestOptions: opts(),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      expect(e, isA<NetworkError>());
    });

    test('connection error → NetworkError', () {
      final e = AppError.fromDio(
        DioException(
          requestOptions: opts(),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(e, isA<NetworkError>());
      expect(e.detail, isNull);
    });

    test('cancel → CancelledError', () {
      final e = AppError.fromDio(
        DioException(requestOptions: opts(), type: DioExceptionType.cancel),
      );
      expect(e, isA<CancelledError>());
    });

    test('unknown → UnknownError', () {
      final e = AppError.fromDio(DioException(requestOptions: opts()));
      expect(e, isA<UnknownError>());
    });

    test('401 → UnauthorizedError', () {
      final e = AppError.fromDio(
        DioException(
          requestOptions: opts(),
          type: DioExceptionType.badResponse,
          response: Response<void>(requestOptions: opts(), statusCode: 401),
        ),
      );
      expect(e, isA<UnauthorizedError>());
    });

    test('403 → ForbiddenError, 로그인 만료로 보지 않는다 (#2859)', () {
      final e = fromStatus(403);
      expect(e, isA<ForbiddenError>());
      expect(e, isNot(isA<UnauthorizedError>()));
    });

    test('404 → NotFoundError', () {
      final e = AppError.fromDio(
        DioException(
          requestOptions: opts(),
          type: DioExceptionType.badResponse,
          response: Response<void>(requestOptions: opts(), statusCode: 404),
        ),
      );
      expect(e, isA<NotFoundError>());
    });

    test('400 → ValidationError(400)', () {
      final e = fromStatus(400);
      expect(e, isA<ValidationError>());
      expect((e as ValidationError).statusCode, 400);
    });

    test('422 → ValidationError(422)', () {
      final e = fromStatus(422);
      expect(e, isA<ValidationError>());
      expect((e as ValidationError).statusCode, 422);
    });

    test('429 → RateLimitedError, 일반 서버 오류가 아니다', () {
      final e = fromStatus(429);
      expect(e, isA<RateLimitedError>());
      expect(e, isNot(isA<ServerError>()));
    });

    test('409 → ServerError carrying status code', () {
      final e = fromStatus(409);
      expect(e, isA<ServerError>());
      expect((e as ServerError).statusCode, 409);
    });

    test('500 → ServerError carrying status code', () {
      final e = AppError.fromDio(
        DioException(
          requestOptions: opts(),
          type: DioExceptionType.badResponse,
          response: Response<void>(requestOptions: opts(), statusCode: 502),
        ),
      );
      expect(e, isA<ServerError>());
      expect((e as ServerError).statusCode, 502);
    });
  });

  group('서버 사유(detail)', () {
    test('문자열 detail 을 detail 과 message 에 담는다', () {
      for (final int code in <int>[400, 401, 403, 404, 409, 422, 429, 500]) {
        final e = fromStatus(
          code,
          body: <String, Object?>{'detail': '연락처는 비울 수 없습니다.'},
          dioMessage: 'The request returned an invalid status code',
        );
        expect(e.detail, '연락처는 비울 수 없습니다.', reason: '$code');
        expect(e.message, '연락처는 비울 수 없습니다.', reason: '$code');
      }
    });

    test('앞뒤 공백은 지운다', () {
      final e = fromStatus(
        403,
        body: <String, Object?>{'detail': '  동의가 필요합니다.  '},
      );
      expect(e.detail, '동의가 필요합니다.');
    });

    test('목록형 detail(FastAPI 스키마 검증)은 사유로 쓰지 않는다', () {
      final e = fromStatus(
        422,
        body: <String, Object?>{
          'detail': <Object?>[
            <String, Object?>{
              'loc': <Object?>['body', 'phone'],
              'msg': 'field required',
            },
          ],
        },
        dioMessage: 'dio says 422',
      );
      expect(e, isA<ValidationError>());
      expect(e.detail, isNull);
      // 기록용 message 는 Dio 문구로 남는다.
      expect(e.message, 'dio says 422');
    });

    test('객체형 detail(오류 코드)은 사유로 쓰지 않는다', () {
      final e = fromStatus(
        409,
        body: <String, Object?>{
          'detail': <String, Object?>{'code': 'already_decided'},
        },
      );
      expect(e.detail, isNull);
    });

    test('본문이 없거나 문자열이면 사유가 없다', () {
      expect(fromStatus(403).detail, isNull);
      expect(fromStatus(500, body: 'Internal Server Error').detail, isNull);
    });

    test('빈 detail 은 없는 것으로 본다', () {
      final e = fromStatus(
        400,
        body: <String, Object?>{'detail': '   '},
        dioMessage: 'dio says 400',
      );
      expect(e.detail, isNull);
      expect(e.message, 'dio says 400');
    });
  });

  group('serverDetailOf', () {
    test('문자열 detail 만 꺼낸다', () {
      expect(serverDetailOf(<String, Object?>{'detail': '사유'}), '사유');
      expect(serverDetailOf(<String, Object?>{'detail': 3}), isNull);
      expect(serverDetailOf(<String, Object?>{'other': '사유'}), isNull);
      expect(serverDetailOf(null), isNull);
      expect(serverDetailOf(<Object?>['detail']), isNull);
    });
  });

  group('직접 만든 오류', () {
    test('detail 을 넘기지 않으면 null 이다', () {
      expect(const ForbiddenError().detail, isNull);
      expect(const RateLimitedError().detail, isNull);
      expect(const ValidationError().detail, isNull);
      expect(const ServerError(statusCode: 409).detail, isNull);
    });

    test('toString 은 상태 코드를 보인다', () {
      expect(
        const ValidationError(statusCode: 422, message: 'm').toString(),
        'ValidationError(status: 422, message: m)',
      );
    });
  });
}

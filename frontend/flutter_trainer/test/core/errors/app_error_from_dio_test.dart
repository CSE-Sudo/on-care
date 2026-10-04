import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';

/// [AppError.fromDio] 의 종류·상태 코드별 결과.
///
/// 어느 경우에도 [AppError.message] 는 서버가 준 사유뿐이다 — Dio 의 영어
/// 설명문("This exception was thrown because …")이 화면 문자열로 흘러가지
/// 않는다.
const String _dioText =
    'This exception was thrown because the response has a status code of 422';

final RequestOptions _options = RequestOptions(path: '/trainer/x');

DioException _ofType(DioExceptionType type) =>
    DioException(requestOptions: _options, type: type, message: _dioText);

DioException _status(int status, [Object? body]) => DioException(
  requestOptions: _options,
  type: DioExceptionType.badResponse,
  message: _dioText,
  response: Response<Object?>(
    requestOptions: _options,
    statusCode: status,
    data: body,
  ),
);

void main() {
  group('전송 단계 오류는 NetworkError 이고 사유가 없다', () {
    for (final DioExceptionType type in <DioExceptionType>[
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.transformTimeout,
      DioExceptionType.connectionError,
    ]) {
      test(type.name, () {
        final AppError error = AppError.fromDio(_ofType(type));

        expect(error, isA<NetworkError>());
        expect(error.message, isNull);
        expect(error.cause, isA<DioException>());
      });
    }
  });

  test('취소는 CancelledError 다', () {
    expect(
      AppError.fromDio(_ofType(DioExceptionType.cancel)),
      isA<CancelledError>(),
    );
  });

  for (final DioExceptionType type in <DioExceptionType>[
    DioExceptionType.badCertificate,
    DioExceptionType.unknown,
  ]) {
    test('${type.name} 은 UnknownError 이고 사유가 없다', () {
      final AppError error = AppError.fromDio(_ofType(type));

      expect(error, isA<UnknownError>());
      expect(error.message, isNull);
    });
  }

  group('상태 코드별 종류 — 본문 없으면 사유 없음', () {
    final Map<int, Matcher> expected = <int, Matcher>{
      400: isA<ValidationError>(),
      401: isA<UnauthorizedError>(),
      403: isA<ForbiddenError>(),
      404: isA<NotFoundError>(),
      409: isA<ServerError>(),
      422: isA<ValidationError>(),
      429: isA<RateLimitedError>(),
      500: isA<ServerError>(),
      502: isA<ServerError>(),
      503: isA<ServerError>(),
    };
    expected.forEach((int status, Matcher kind) {
      test('$status', () {
        final AppError error = AppError.fromDio(_status(status));

        expect(error, kind);
        expect(error.message, isNull);
        expect(error.toString(), isNot(contains('exception was thrown')));
      });
    });
  });

  test('5xx 는 서버 쪽 문제로 표시된다', () {
    final AppError error = AppError.fromDio(_status(503));

    expect(error, isA<ServerError>());
    expect((error as ServerError).statusCode, 503);
    expect(error.isServerSide, isTrue);
    expect(
      (AppError.fromDio(_status(409)) as ServerError).isServerSide,
      isFalse,
    );
  });

  test('5xx 라도 서버가 사유를 주면 그 사유다', () {
    final AppError error = AppError.fromDio(
      _status(503, <String, Object?>{'detail': 'AI 서비스가 잠시 응답하지 않습니다.'}),
    );

    expect(error.message, 'AI 서비스가 잠시 응답하지 않습니다.');
  });

  test('객체 detail 의 message 를 사유로 읽는다', () {
    final AppError error = AppError.fromDio(
      _status(429, <String, Object?>{
        'detail': <String, Object?>{
          'code': 'daily_limit',
          'message': '오늘 AI 생성 한도를 다 썼어요.',
        },
      }),
    );

    expect(error, isA<RateLimitedError>());
    expect(error.message, '오늘 AI 생성 한도를 다 썼어요.');
    expect((error as RateLimitedError).isDailyLimit, isTrue);
  });

  test('빈 문자열 detail 은 사유가 아니다', () {
    final AppError error = AppError.fromDio(
      _status(400, <String, Object?>{'detail': '   '}),
    );

    expect(error.message, isNull);
  });
}

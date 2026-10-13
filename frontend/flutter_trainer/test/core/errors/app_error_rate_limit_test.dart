import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';

/// 429 의 `detail.code` 를 [RateLimitedError.code] 로 싣는지(#3032).
///
/// 분당 한도(잠시 뒤 다시)와 트레이너 하루 AI 상한(내일 다시)은 같은 429 지만
/// 안내가 다르다 — 화면이 코드로 가른다.
DioException _tooMany(Object? body) {
  final RequestOptions options = RequestOptions(path: '/trainer/clients/m1/routine-options');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    message: 'technical dio text',
    response: Response<Object?>(
      requestOptions: options,
      statusCode: 429,
      data: body,
      headers: Headers.fromMap(<String, List<String>>{
        'retry-after': <String>['3600'],
      }),
    ),
  );
}

void main() {
  test('하루 상한 429 는 daily_limit 코드와 서버 문구를 싣는다', () {
    final AppError error = AppError.fromDio(
      _tooMany(<String, Object?>{
        'detail': <String, Object?>{
          'code': 'daily_limit',
          'message': '오늘 AI 생성 한도를 다 썼어요. 내일 다시 이용해 주세요.',
        },
      }),
    );

    expect(error, isA<RateLimitedError>());
    final RateLimitedError limited = error as RateLimitedError;
    expect(limited.code, RateLimitedError.dailyLimitCode);
    expect(limited.isDailyLimit, isTrue);
    expect(limited.message, '오늘 AI 생성 한도를 다 썼어요. 내일 다시 이용해 주세요.');
  });

  test('분당 한도 429(문자열 detail)는 코드가 없다', () {
    final AppError error = AppError.fromDio(
      _tooMany(<String, Object?>{'detail': '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.'}),
    );

    final RateLimitedError limited = error as RateLimitedError;
    expect(limited.code, isNull);
    expect(limited.isDailyLimit, isFalse);
  });

  test('다른 코드의 429 는 하루 상한으로 읽지 않는다', () {
    final AppError error = AppError.fromDio(
      _tooMany(<String, Object?>{
        'detail': <String, Object?>{'code': 'rate_limited', 'message': '잠시 후'},
      }),
    );

    final RateLimitedError limited = error as RateLimitedError;
    expect(limited.code, 'rate_limited');
    expect(limited.isDailyLimit, isFalse);
  });

  test('본문이 없는 429 도 RateLimitedError 다', () {
    final AppError error = AppError.fromDio(_tooMany(null));

    expect(error, isA<RateLimitedError>());
    expect((error as RateLimitedError).isDailyLimit, isFalse);
  });

  test('직접 만든 RateLimitedError 는 기본이 일시 한도다', () {
    const RateLimitedError error = RateLimitedError();
    expect(error.isDailyLimit, isFalse);
    expect(error.toString(), contains('code: null'));
  });
}

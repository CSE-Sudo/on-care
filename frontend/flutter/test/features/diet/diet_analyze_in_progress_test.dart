/// 사진 분석의 `in_progress`(409) 응답 처리. (#3354)
///
/// 앱은 90초 안에 답이 없으면 같은 멱등키로 다시 보낸다. 첫 요청이 아직 모델을
/// 기다리는 중이면 서버는 두 번째를 새로 분석하지 않고(하루 횟수도 세지 않는다)
/// 409 `in_progress` 로 답한다. 앱은 이것을 실패로 띄우지 않고 잠시 쉬었다가 같은
/// 키로 다시 물어, 첫 요청이 저장한 결과를 받는다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis_failure.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';

final Uint8List _jpegBytes = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

MealPhoto get _photo => MealPhoto.fromBytes(_jpegBytes)!;

const Map<String, Object?> _analyzeResponse = <String, Object?>{
  'entry_id': 'diet-saved',
  'time_label': '12:10',
  'analysis': <String, Object?>{
    'foods': <Object?>[
      <String, Object?>{'name': '현미밥', 'calories': 300},
    ],
    'total_calories': 300,
    'total_sodium_mg': 5,
    'total_sugar_g': 0.5,
    'coach_comment': '',
    'engine': 'stub',
  },
};

/// 요청마다 [respond] 로 답하는 Dio. 보낸 요청의 옵션을 모아 둔다.
({Dio dio, List<RequestOptions> sent}) _dio(
  void Function(
    RequestOptions options,
    RequestInterceptorHandler handler,
    int attempt,
  )
  respond,
) {
  final List<RequestOptions> sent = <RequestOptions>[];
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        sent.add(options);
        respond(options, handler, sent.length);
      },
    ),
  );
  return (dio: dio, sent: sent);
}

void _timeout(RequestOptions options, RequestInterceptorHandler handler) =>
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      ),
    );

void _status(
  RequestOptions options,
  RequestInterceptorHandler handler,
  int statusCode, [
  Object? data,
]) => handler.reject(
  DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: options,
      statusCode: statusCode,
      data: data,
    ),
  ),
);

void _inProgress(RequestOptions options, RequestInterceptorHandler handler) =>
    _status(options, handler, 409, const <String, Object?>{
      'detail': <String, Object?>{
        'code': 'in_progress',
        'message': '같은 사진을 분석하는 중이에요.',
      },
    });

void _ok(RequestOptions options, RequestInterceptorHandler handler) =>
    handler.resolve(
      Response<Map<String, Object?>>(
        requestOptions: options,
        statusCode: 200,
        data: _analyzeResponse,
      ),
    );

String _keyOf(RequestOptions o) => (o.data as FormData).fields
    .firstWhere((MapEntry<String, String> f) => f.key == 'idempotency_key')
    .value;

/// 쉬는 시간 없이 다시 묻는 저장소 — 테스트가 실제로 기다리지 않게.
DioDietRepository _repo(Dio dio) =>
    DioDietRepository(dio, inProgressPollInterval: Duration.zero);

void main() {
  test('끊긴 뒤 다시 보낸 요청이 분석 중이면 같은 키로 다시 물어 저장된 결과를 받는다', () async {
    final ({Dio dio, List<RequestOptions> sent}) d = _dio((
      RequestOptions o,
      RequestInterceptorHandler h,
      int attempt,
    ) {
      switch (attempt) {
        case 1:
          _timeout(o, h);
        case 2 || 3:
          _inProgress(o, h);
        default:
          _ok(o, h);
      }
    });
    addTearDown(d.dio.close);

    final DietAnalysisResult result = await _repo(
      d.dio,
    ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'same-key');

    expect(result.entryId, 'diet-saved');
    expect(d.sent, hasLength(4));
    // 매번 같은 키다 — 키가 바뀌면 서버가 새로 분석하고 한 번 더 센다.
    expect(d.sent.map(_keyOf).toSet(), <String>{'same-key'});
    // 다시 보낸 요청도 사진을 싣는다 — multipart 본문은 한 번만 읽힌다.
    expect((d.sent.last.data as FormData).files, hasLength(1));
  });

  test('처음 보낸 요청이 분석 중이라고 답해도 기다렸다 결과를 받는다', () async {
    // 실패 화면의 다시 시도는 같은 키로 보낸다 — 앞선 시도가 아직 도는 중일 수 있다.
    final ({Dio dio, List<RequestOptions> sent}) d = _dio(
      (RequestOptions o, RequestInterceptorHandler h, int attempt) =>
          attempt == 1 ? _inProgress(o, h) : _ok(o, h),
    );
    addTearDown(d.dio.close);

    final DietAnalysisResult result = await _repo(
      d.dio,
    ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k');

    expect(result.entryId, 'diet-saved');
    expect(d.sent, hasLength(2));
  });

  test('다시 묻기 전에 정해진 시간만큼 쉰다', () async {
    final List<DateTime> at = <DateTime>[];
    final ({Dio dio, List<RequestOptions> sent}) d = _dio((
      RequestOptions o,
      RequestInterceptorHandler h,
      int attempt,
    ) {
      at.add(DateTime.now());
      if (attempt == 1) {
        _inProgress(o, h);
      } else {
        _ok(o, h);
      }
    });
    addTearDown(d.dio.close);
    const Duration interval = Duration(milliseconds: 80);

    await DioDietRepository(
      d.dio,
      inProgressPollInterval: interval,
    ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k');

    expect(at, hasLength(2));
    expect(at[1].difference(at[0]), greaterThanOrEqualTo(interval));
  });

  test('끝내 분석 중이면 정해진 횟수만 묻고 다시 시도할 수 있는 실패로 알린다', () async {
    final ({Dio dio, List<RequestOptions> sent}) d = _dio(
      (RequestOptions o, RequestInterceptorHandler h, int _) =>
          _inProgress(o, h),
    );
    addTearDown(d.dio.close);

    Object? thrown;
    try {
      await _repo(
        d.dio,
      ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k');
    } on Object catch (e) {
      thrown = e;
    }

    expect(thrown, isA<DietAnalysisRejected>());
    final DietAnalysisFailure failure = DietAnalysisFailure.fromError(thrown!);
    expect(failure, DietAnalysisFailure.temporary);
    expect(failure.canRetry, isTrue);
    // 처음 한 번 + 다시 묻기.
    expect(d.sent, hasLength(1 + DioDietRepository.inProgressPollLimit));
  });

  test('분석 중 뒤에 온 다른 거절은 그 이유 그대로 올린다', () async {
    final ({Dio dio, List<RequestOptions> sent}) d = _dio(
      (RequestOptions o, RequestInterceptorHandler h, int attempt) =>
          attempt == 1
          ? _inProgress(o, h)
          : _status(o, h, 422, const <String, Object?>{
              'detail': <String, Object?>{
                'code': 'no_food_detected',
                'message': '사진에서 음식을 찾지 못했어요.',
              },
            }),
    );
    addTearDown(d.dio.close);

    await expectLater(
      _repo(
        d.dio,
      ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k'),
      throwsA(
        isA<DietAnalysisRejected>().having(
          (DietAnalysisRejected e) => e.failure,
          'failure',
          DietAnalysisFailure.noFood,
        ),
      ),
    );
    expect(d.sent, hasLength(2));
  });

  test('분석 중을 기다리는 동안에도 끊긴 요청은 한 번만 다시 보낸다', () async {
    final ({Dio dio, List<RequestOptions> sent}) d = _dio((
      RequestOptions o,
      RequestInterceptorHandler h,
      int attempt,
    ) {
      switch (attempt) {
        case 1 || 3:
          _timeout(o, h);
        default:
          _inProgress(o, h);
      }
    });
    addTearDown(d.dio.close);

    await expectLater(
      _repo(
        d.dio,
      ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k'),
      throwsA(isA<NetworkError>()),
    );
    expect(d.sent, hasLength(3));
  });

  test('코드 없는 409 는 분석 중이 아니다 — 다시 묻지 않는다', () async {
    final ({Dio dio, List<RequestOptions> sent}) d = _dio(
      (RequestOptions o, RequestInterceptorHandler h, int _) =>
          _status(o, h, 409, const <String, Object?>{'detail': '충돌'}),
    );
    addTearDown(d.dio.close);

    await expectLater(
      _repo(
        d.dio,
      ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'k'),
      throwsA(isA<AppError>()),
    );
    expect(d.sent, hasLength(1));
  });

  test('멱등키가 없으면 다시 묻지 않는다 — 다시 보내면 중복 저장이 된다', () async {
    final ({Dio dio, List<RequestOptions> sent}) d = _dio(
      (RequestOptions o, RequestInterceptorHandler h, int _) =>
          _inProgress(o, h),
    );
    addTearDown(d.dio.close);

    await expectLater(
      _repo(d.dio).analyze(photo: _photo, mealType: 'lunch'),
      throwsA(isA<DietAnalysisRejected>()),
    );
    expect(d.sent, hasLength(1));
  });

  test('분석 중 코드는 다시 시도할 수 있는 일시 실패로 옮긴다', () {
    expect(
      DietAnalysisFailure.fromCode(kDietAnalysisInProgressCode),
      DietAnalysisFailure.temporary,
    );
    final DietAnalysisRejected? rejected =
        DietAnalysisRejected.fromResponseData(const <String, Object?>{
          'detail': <String, Object?>{'code': 'in_progress', 'message': 'm'},
        });
    expect(rejected?.failure, DietAnalysisFailure.temporary);
    expect(rejected?.failure.offersManualEntry, isFalse);
  });
}

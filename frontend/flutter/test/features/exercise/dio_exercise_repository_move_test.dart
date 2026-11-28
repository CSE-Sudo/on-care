/// 운동 기록 묶음 날짜 이동의 요청 모양 — POST /exercise/sessions/move. (#3365)
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/data/repositories/dio_exercise_repository.dart';

void main() {
  late Dio dio;
  late DioExerciseRepository repository;
  late List<RequestOptions> sent;
  late int status;

  setUp(() {
    sent = <RequestOptions>[];
    status = 200;
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          sent.add(options);
          final Response<Map<String, Object?>> response =
              Response<Map<String, Object?>>(
                requestOptions: options,
                statusCode: status,
                data: <String, Object?>{'sessions': <Object?>[]},
              );
          if (status >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: response,
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
          handler.resolve(response);
        },
      ),
    );
    repository = DioExerciseRepository(dio);
  });

  tearDown(() => dio.close());

  test('기록 여러 개를 요청 하나로 보낸다', () async {
    await repository.moveSessions(<String>[
      'ex-1',
      'ex-2',
      'ex-3',
    ], DateTime(2026, 9, 8));

    expect(sent, hasLength(1));
    expect(sent.single.method, 'POST');
    expect(sent.single.path, '/exercise/sessions/move');
    expect(sent.single.data, <String, Object?>{
      'session_ids': <String>['ex-1', 'ex-2', 'ex-3'],
      'date': '2026-09-08',
    });
  });

  test('날짜는 시각을 떼고 YYYY-MM-DD 로 보낸다', () async {
    await repository.moveSessions(<String>[
      'ex-1',
    ], DateTime(2026, 1, 5, 23, 59));

    expect((sent.single.data as Map<String, Object?>)['date'], '2026-01-05');
  });

  test('서버가 거절하면 그대로 실패한다 — 옮겨졌다고 여기지 않는다', () async {
    status = 409;

    await expectLater(
      repository.moveSessions(<String>['ex-1'], DateTime(2026, 9, 8)),
      throwsA(isA<DioException>()),
    );
  });
}

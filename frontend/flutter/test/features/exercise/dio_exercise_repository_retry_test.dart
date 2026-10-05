/// 운동 기록 추가의 멱등키 — 응답을 잃은 저장을 다시 누르면 같은 키. (#3095)
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/data/repositories/dio_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

void main() {
  late Dio dio;
  late DioExerciseRepository repository;
  late List<String?> sentKeys;
  late bool failNext;

  setUp(() {
    sentKeys = <String?>[];
    failNext = false;
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final Map<String, Object?> body =
              options.data as Map<String, Object?>;
          sentKeys.add(body['client_request_id'] as String?);
          if (failNext) {
            failNext = false;
            // 서버는 저장했지만 앱은 응답을 받지 못했다.
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.receiveTimeout,
              ),
            );
            return;
          }
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 201,
              data: <String, Object?>{
                'sessions': <Object?>[],
                'points': <String, Object?>{'awarded': 0, 'balance': 0},
              },
            ),
          );
        },
      ),
    );
    repository = DioExerciseRepository(dio);
  });

  tearDown(() => dio.close());

  ExerciseSessionDraft draft({int minutes = 30}) => ExerciseSessionDraft(
    type: ExerciseType.cardio,
    minutes: minutes,
    calories: 200,
    date: DateTime(2026, 10, 4),
    name: '러닝머신',
  );

  Future<void> failingSave(List<ExerciseSessionDraft> drafts) async {
    failNext = true;
    await expectLater(
      repository.addSessions(drafts),
      throwsA(isA<DioException>()),
    );
  }

  test('실패 뒤 같은 목록을 다시 보내면 같은 키다', () async {
    await failingSave(<ExerciseSessionDraft>[draft(), draft(minutes: 10)]);
    await repository.addSessions(<ExerciseSessionDraft>[
      draft(),
      draft(minutes: 10),
    ]);
    expect(sentKeys, hasLength(2));
    expect(sentKeys[0], isNotNull);
    expect(sentKeys[1], sentKeys[0]);
  });

  test('실패 뒤 목록을 고치면 새 키다', () async {
    await failingSave(<ExerciseSessionDraft>[draft()]);
    await repository.addSessions(<ExerciseSessionDraft>[draft(minutes: 45)]);
    expect(sentKeys[1], isNot(sentKeys[0]));
  });

  test('저장이 성공한 뒤의 같은 목록은 새 저장이라 새 키다', () async {
    await repository.addSessions(<ExerciseSessionDraft>[draft()]);
    await repository.addSessions(<ExerciseSessionDraft>[draft()]);
    expect(sentKeys[1], isNot(sentKeys[0]));
  });
}

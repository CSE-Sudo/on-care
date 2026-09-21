import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body, String path) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 201,
  data: body,
);

DioException _httpError(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
  ),
);

void main() {
  late _MockDio dio;
  late DioTrainerRoutineRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioTrainerRoutineRepository(dio);
  });

  test(
    'assignRoutine POSTs the normalised RoutineAssignRequest body',
    () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/m1/routines',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'id': 'r1',
        }, '/trainer/clients/m1/routines'),
      );

      await repo.assignRoutine(
        'm1',
        const AssignedRoutine(
          id: '',
          name: 'AI 맞춤 루틴',
          minutes: 999, // clamped to 600
          type: 'weird', // -> 근력
          reason: '걷기, 스쿼트',
          source: 'ai',
        ),
      );

      verify(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/m1/routines',
          data: <String, Object?>{
            'name': 'AI 맞춤 루틴',
            'minutes': 600,
            'type': '근력',
            // 날짜·강도·세트·중량도 함께 나간다 — 회원 앱의 운동 추가와 같은
            // 칸이다 (#1276, #1310). 세트·횟수·중량은 안 정했으면 비어 있다.
            'exercise_date': null,
            'intensity': 'moderate',
            'sets': null,
            'reps': null,
            'hold_seconds': null,
            'weight': null,
            'reason': '걷기, 스쿼트',
            'source': 'ai',
          },
        ),
      ).called(1);
    },
  );

  test('assignRoutine surfaces a failure as AppError', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/routines',
        data: any(named: 'data'),
      ),
    ).thenThrow(_httpError(500, '/trainer/clients/m1/routines'));

    await expectLater(
      repo.assignRoutine(
        'm1',
        const AssignedRoutine(
          id: '',
          name: 'x',
          minutes: 30,
          type: '근력',
          reason: '',
          source: 'ai',
        ),
      ),
      throwsA(isA<AppError>()),
    );
  });

  test('watchAssignedRoutines parses the list', () async {
    when(
      () => dio.get<List<dynamic>>('/trainer/clients/m1/routines'),
    ).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/trainer/clients/m1/routines'),
        statusCode: 200,
        data: <dynamic>[
          <String, Object?>{
            'id': 'r1',
            'name': '저강도 유산소',
            'minutes': 30,
            'type': '유산소',
            'reason': '혈압',
            'source': 'ai',
          },
        ],
      ),
    );

    final routines = await repo.watchAssignedRoutines('m1').first;
    expect(routines.single.name, '저강도 유산소');
    expect(routines.single.type, '유산소');
  });

  test('watchAssignedRoutines surfaces a 404 as NotFoundError', () async {
    when(
      () => dio.get<List<dynamic>>('/trainer/clients/x/routines'),
    ).thenThrow(_httpError(404, '/trainer/clients/x/routines'));

    await expectLater(
      repo.watchAssignedRoutines('x'),
      emitsError(isA<NotFoundError>()),
    );
  });

  test('encodes an opaque member id in routine paths', () async {
    const encoded = 'member%2Fwith%3Freserved';
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/$encoded/routines',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(
        const <String, Object?>{},
        '/trainer/clients/$encoded/routines',
      ),
    );
    when(
      () => dio.get<List<dynamic>>('/trainer/clients/$encoded/routines'),
    ).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(
          path: '/trainer/clients/$encoded/routines',
        ),
        statusCode: 200,
        data: const <dynamic>[],
      ),
    );
    const routine = AssignedRoutine(
      id: '',
      name: 'x',
      minutes: 10,
      type: '근력',
      reason: '',
      source: 'ai',
    );

    await repo.assignRoutine('member/with?reserved', routine);
    await repo.watchAssignedRoutines('member/with?reserved').first;

    verify(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/$encoded/routines',
        data: any(named: 'data'),
      ),
    ).called(1);
    verify(
      () => dio.get<List<dynamic>>('/trainer/clients/$encoded/routines'),
    ).called(1);
  });

  test('malformed routine entries fail instead of being dropped', () {
    when(
      () => dio.get<List<dynamic>>('/trainer/clients/m1/routines'),
    ).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/trainer/clients/m1/routines'),
        statusCode: 200,
        data: <dynamic>['not-an-object'],
      ),
    );

    expect(
      repo.watchAssignedRoutines('m1'),
      emitsError(isA<FormatException>()),
    );
  });
}

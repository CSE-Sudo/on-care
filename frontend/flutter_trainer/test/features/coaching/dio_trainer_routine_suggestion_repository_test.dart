import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body, String path, {int status = 200}) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: status,
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
  const String listPath = '/trainer/clients/m1/routine-suggestions';
  const String approvePath =
      '/trainer/routine-suggestions/s1/approve';
  const String dismissPath =
      '/trainer/routine-suggestions/s1/dismiss';

  late _MockDio dio;
  late DioTrainerRoutineSuggestionRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioTrainerRoutineSuggestionRepository(dio);
  });

  test('pending reads the review list with its evidence', () async {
    when(() => dio.get<List<dynamic>>(listPath)).thenAnswer(
      (_) async => _ok<List<dynamic>>(<dynamic>[
        <String, Object?>{
          'id': 's1',
          'name': '어깨 관절 보호 스트레칭',
          'minutes': 8,
          'type': '스트레칭',
          'reason': '어깨 안정화',
          'evidence': <dynamic>['최근 PT 피드백 반영', '', 42],
        },
        // 모양이 다른 항목 하나가 목록 전체를 막지 않는다.
        'not an object',
      ], listPath),
    );

    final rows = await repo.pending('m1');

    expect(rows.length, 1);
    expect(rows.single.id, 's1');
    expect(rows.single.minutes, 8);
    // 빈 문자열과 문자열이 아닌 값은 빠진다.
    expect(rows.single.evidence, <String>['최근 PT 피드백 반영']);
  });

  test('approve without edits sends an empty body', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        approvePath,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'id': 's1',
      }, approvePath),
    );

    await repo.approve('s1');

    // 명시적 null 은 서버가 422 로 거른다(#495 규약) — 주지 않은 필드는 아예
    // 실리지 않아야 '그대로 승인'이 된다.
    verify(
      () => dio.post<Map<String, Object?>>(
        approvePath,
        data: <String, Object?>{},
      ),
    ).called(1);
  });

  test('approve with edits normalises the values it sends', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        approvePath,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'id': 's1',
      }, approvePath),
    );

    await repo.approve(
      's1',
      name: '  어깨 회복 스트레칭  ',
      minutes: 999, // 0..600 으로 좁혀진다
      type: 'weird', // 계약값이 아니면 보내지 않는다
      reason: ' 통증 시 중단 ',
    );

    verify(
      () => dio.post<Map<String, Object?>>(
        approvePath,
        data: <String, Object?>{
          'name': '어깨 회복 스트레칭',
          'minutes': 600,
          'reason': '통증 시 중단',
        },
      ),
    ).called(1);
  });

  test('a 409 becomes RoutineSuggestionAlreadyReviewed', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        approvePath,
        data: any(named: 'data'),
      ),
    ).thenThrow(_httpError(409, approvePath));

    // 실패가 아니라 '이미 반영됨'이다 — 화면이 그렇게 말할 수 있어야 한다.
    await expectLater(
      repo.approve('s1'),
      throwsA(isA<RoutineSuggestionAlreadyReviewed>()),
    );
  });

  test('dismiss posts to the dismiss path', () async {
    when(
      () => dio.post<Map<String, Object?>>(dismissPath),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'id': 's1',
      }, dismissPath),
    );

    await repo.dismiss('s1');

    verify(
      () => dio.post<Map<String, Object?>>(dismissPath),
    ).called(1);
  });

  test('other failures surface as AppError', () async {
    when(() => dio.get<List<dynamic>>(listPath)).thenThrow(
      _httpError(404, listPath),
    );

    await expectLater(repo.pending('m1'), throwsA(isA<AppError>()));
  });
}

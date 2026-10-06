/// 개인운동 조회 두 곳의 실패가 [AppError] 로 올라오는가. (#2891)
///
/// 같은 저장소의 다른 조회는 `DioException` 을 [AppError.fromDio] 로 바꿔
/// 올리는데, 개인운동 조회 둘만 원시 예외를 흘려 부르는 쪽이 서버 사유·오류
/// 종류를 쓸 수 없었다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/dio_schedule_repository.dart';

class _MockDio extends Mock implements Dio {}

DioException _httpError(int status, String path, {String? detail}) =>
    DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: RequestOptions(path: path),
        statusCode: status,
        data: detail == null ? null : <String, dynamic>{'detail': detail},
      ),
    );

DioException _offline(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.connectionError,
);

const String _routinesPath = '/trainer/schedule/s1/routines';
const String _unsentPath = '/trainer/clients/m1/routines/unsent';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late DioScheduleRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioScheduleRepository(dio);
    addTearDown(repo.dispose);
  });

  void failGet(String path, DioException error) {
    when(() => dio.get<List<dynamic>>(path)).thenThrow(error);
  }

  group('fetchScheduledRoutines', () {
    test('서버 거절은 사유를 실은 AppError 다', () async {
      failGet(
        _routinesPath,
        _httpError(404, _routinesPath, detail: '일정을 찾을 수 없어요'),
      );

      await expectLater(
        repo.fetchScheduledRoutines('s1'),
        throwsA(
          isA<NotFoundError>().having(
            (e) => e.message,
            'message',
            '일정을 찾을 수 없어요',
          ),
        ),
      );
    });

    test('연결 실패는 NetworkError 다', () async {
      failGet(_routinesPath, _offline(_routinesPath));

      await expectLater(
        repo.fetchScheduledRoutines('s1'),
        throwsA(isA<NetworkError>()),
      );
    });

    test('서버 오류는 상태 코드를 지닌 ServerError 다', () async {
      failGet(_routinesPath, _httpError(500, _routinesPath));

      await expectLater(
        repo.fetchScheduledRoutines('s1'),
        throwsA(
          isA<ServerError>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('원시 DioException 은 올라오지 않는다', () async {
      failGet(_routinesPath, _httpError(503, _routinesPath));

      await expectLater(
        repo.fetchScheduledRoutines('s1'),
        throwsA(isNot(isA<DioException>())),
      );
    });

    test('성공하면 지금처럼 읽는다', () async {
      when(() => dio.get<List<dynamic>>(_routinesPath)).thenAnswer(
        (_) async => Response<List<dynamic>>(
          requestOptions: RequestOptions(path: _routinesPath),
          statusCode: 200,
          data: <dynamic>[
            <String, dynamic>{
              'name': '저강도 걷기',
              'type': '유산소',
              'minutes': 30,
              'pending_send': true,
            },
          ],
        ),
      );

      final rows = await repo.fetchScheduledRoutines('s1');
      expect(rows, hasLength(1));
      expect(rows.single.exercise.name, '저강도 걷기');
      expect(rows.single.sent, isFalse);
    });
  });

  group('fetchUnsentRoutinesFor', () {
    test('서버 거절은 사유를 실은 AppError 다', () async {
      failGet(_unsentPath, _httpError(403, _unsentPath, detail: '담당 회원이 아닙니다'));

      await expectLater(
        repo.fetchUnsentRoutinesFor('m1'),
        throwsA(
          isA<ForbiddenError>().having(
            (e) => e.message,
            'message',
            '담당 회원이 아닙니다',
          ),
        ),
      );
    });

    test('연결 실패는 NetworkError 다', () async {
      failGet(_unsentPath, _offline(_unsentPath));

      await expectLater(
        repo.fetchUnsentRoutinesFor('m1'),
        throwsA(isA<NetworkError>()),
      );
    });

    test('성공하면 지금처럼 읽는다', () async {
      when(() => dio.get<List<dynamic>>(_unsentPath)).thenAnswer(
        (_) async => Response<List<dynamic>>(
          requestOptions: RequestOptions(path: _unsentPath),
          statusCode: 200,
          data: <dynamic>[
            <String, dynamic>{
              'name': '저강도 걷기',
              'type': '유산소',
              'minutes': 30,
              'schedule_id': 's1',
              'schedule_date': '2026-08-19',
            },
          ],
        ),
      );

      final rows = await repo.fetchUnsentRoutinesFor('m1');
      expect(rows.single.scheduleId, 's1');
      expect(rows.single.scheduleDate, '2026-08-19');
    });
  });
}

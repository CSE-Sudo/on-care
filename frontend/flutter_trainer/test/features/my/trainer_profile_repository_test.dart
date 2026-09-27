import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/my/data/trainer_profile_repository.dart';

class _MockDio extends Mock implements Dio {}

Response<Map<String, Object?>> _profileResponse({
  String gymId = 'gym-1',
  String phone = '010-1111-2222',
}) => Response<Map<String, Object?>>(
  requestOptions: RequestOptions(path: '/trainer/me'),
  statusCode: 200,
  data: <String, Object?>{
    'name': '김트레이너',
    'email': 'trainer@oncare.com',
    'phone': phone,
    'specialty': '재활',
    'career': '7년',
    'intro': '소개',
    'certifications': <String>['CPT'],
    'gym': <String, Object?>{
      'id': gymId,
      'name': '온케어짐',
      'address': '서울',
      'hours': '06:00 - 23:00',
      'phone': '02-0000-0000',
    },
  },
);

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('DioTrainerProfileRepository', () {
    late _MockDio dio;
    late DioTrainerProfileRepository repository;

    setUp(() {
      dio = _MockDio();
      repository = DioTrainerProfileRepository(dio);
    });

    test(
      'update sends backend fields and returns the server profile',
      () async {
        when(
          () => dio.put<Map<String, Object?>>(
            '/trainer/me',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => _profileResponse(phone: '010-9999-0000'));

        final result = await repository.update(
          const TrainerProfileUpdate(
            phone: '010-9999-0000',
            specialty: '재활',
            careerYears: 8,
            intro: '새 소개',
            certifications: <String>['CPT'],
          ),
        );

        expect(result.phone, '010-9999-0000');
        final body =
            verify(
                  () => dio.put<Map<String, Object?>>(
                    '/trainer/me',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, Object?>;
        expect(body['career_years'], 8);
        expect(body, isNot(contains('name')));
        expect(body, isNot(contains('email')));
      },
    );

    test(
      'setGym uses the affiliation endpoint and maps its response',
      () async {
        when(
          () => dio.put<Map<String, Object?>>(
            '/trainer/me/gym',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => _profileResponse(gymId: 'gym-2'));

        final result = await repository.setGym('gym-2');

        expect(result.gym.id, 'gym-2');
        verify(
          () => dio.put<Map<String, Object?>>(
            '/trainer/me/gym',
            data: <String, Object?>{'gym_id': 'gym-2'},
          ),
        ).called(1);
      },
    );

    test('listGyms maps selectable affiliation options', () async {
      when(() => dio.get<List<Object?>>('/gyms')).thenAnswer(
        (_) async => Response<List<Object?>>(
          requestOptions: RequestOptions(path: '/gyms'),
          statusCode: 200,
          data: <Object?>[
            <String, Object?>{
              'id': 'gym-1',
              'name': '온케어짐',
              'address': '서울',
              'weekday_hours': '06:00 – 23:00',
              'phone': '02-1234-5678',
            },
          ],
        ),
      );

      final gyms = await repository.listGyms();

      expect(gyms.single.id, 'gym-1');
      expect(gyms.single.name, '온케어짐');
      expect(gyms.single.hours, '06:00 – 23:00');
      expect(gyms.single.phone, '02-1234-5678');
    });

    test('clearGym calls DELETE and returns the server view', () async {
      when(
        () => dio.delete<Map<String, Object?>>('/trainer/me/gym'),
      ).thenAnswer((_) async => _profileResponse(gymId: ''));

      await repository.clearGym();

      verify(
        () => dio.delete<Map<String, Object?>>('/trainer/me/gym'),
      ).called(1);
    });

    test('409 preserves the backend conflict detail', () async {
      when(
        () => dio.put<Map<String, Object?>>(
          '/trainer/me',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/trainer/me'),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/trainer/me'),
            statusCode: 409,
            data: <String, Object?>{'detail': '소속 헬스장 정보와 충돌합니다.'},
          ),
        ),
      );

      await expectLater(
        repository.update(
          const TrainerProfileUpdate(
            phone: '',
            specialty: '',
            careerYears: 0,
            intro: '',
            certifications: <String>[],
          ),
        ),
        throwsA(
          isA<ServerError>().having(
            (error) => error.message,
            'message',
            contains('충돌'),
          ),
        ),
      );
    });

    for (final scenario in <({int status, Type type, String detail})>[
      (status: 422, type: ValidationError, detail: '경력 값을 확인해 주세요.'),
      (status: 404, type: NotFoundError, detail: '선택한 헬스장이 없습니다.'),
    ]) {
      test('${scenario.status} preserves detail as ${scenario.type}', () async {
        when(
          () => dio.put<Map<String, Object?>>(
            '/trainer/me',
            data: any(named: 'data'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/trainer/me'),
            type: DioExceptionType.badResponse,
            response: Response<Object?>(
              requestOptions: RequestOptions(path: '/trainer/me'),
              statusCode: scenario.status,
              data: <String, Object?>{'detail': scenario.detail},
            ),
          ),
        );

        await expectLater(
          repository.update(
            const TrainerProfileUpdate(
              phone: '',
              specialty: '',
              careerYears: 0,
              intro: '',
              certifications: <String>[],
            ),
          ),
          throwsA(
            isA<AppError>()
                .having((error) => error.runtimeType, 'type', scenario.type)
                .having((error) => error.message, 'message', scenario.detail),
          ),
        );
      });
    }
  });

  test('mock repository persists profile and affiliation mutations', () async {
    final repository = MockTrainerProfileRepository();

    await repository.update(
      const TrainerProfileUpdate(
        phone: '010-7777-8888',
        specialty: '체형 교정',
        careerYears: 9,
        intro: '새 소개',
        certifications: <String>['CPT'],
      ),
    );
    await repository.setGym('gym-2');

    final restored = await repository.fetch();
    expect(restored.phone, '010-7777-8888');
    expect(restored.careerYears, 9);
    expect(restored.gym.id, 'gym-2');
    expect(restored.gym.hours, '06:00 – 24:00');

    await repository.clearGym();
    expect((await repository.fetch()).gym.id, isNull);
  });
}

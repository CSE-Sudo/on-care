import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/features/my/data/trainer_profile_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

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
      'registered gym is selected through the affiliation endpoint',
      () async {
        when(
          () => dio.put<Map<String, Object?>>(
            '/trainer/me/gym',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => _profileResponse(gymId: 'gym-2'));

        final result = await repository.selectGym(
          const TrainerGymCandidate(
            id: 'gym-2',
            name: '온케어짐 강남점',
            address: '서울',
            registered: true,
          ),
        );

        expect(result.gym.id, 'gym-2');
        verify(
          () => dio.put<Map<String, Object?>>(
            '/trainer/me/gym',
            data: <String, Object?>{'gym_id': 'gym-2'},
          ),
        ).called(1);
      },
    );

    test('Kakao gym is selected with its place id and name', () async {
      when(
        () => dio.put<Map<String, Object?>>(
          '/trainer/me/gym/kakao',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _profileResponse(gymId: '9000000001'));

      final result = await repository.selectGym(
        const TrainerGymCandidate(
          id: '9000000001',
          name: '온케어 무브랩',
          address: '서울 서대문구 연세로 20',
          registered: false,
        ),
      );

      expect(result.gym.id, '9000000001');
      // 주소는 보내지 않는다 — 서버가 카카오 값으로 저장한다.
      verify(
        () => dio.put<Map<String, Object?>>(
          '/trainer/me/gym/kakao',
          data: <String, Object?>{
            'kakao_place_id': '9000000001',
            'name': '온케어 무브랩',
          },
        ),
      ).called(1);
      verifyNever(
        () => dio.put<Map<String, Object?>>(
          '/trainer/me/gym',
          data: any(named: 'data'),
        ),
      );
    });

    test('searchGyms sends the query and maps candidates', () async {
      when(
        () => dio.get<List<Object?>>(
          '/trainer/gyms/search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<List<Object?>>(
          requestOptions: RequestOptions(path: '/trainer/gyms/search'),
          statusCode: 200,
          data: <Object?>[
            <String, Object?>{
              'id': 'gym-1',
              'name': '온케어짐',
              'address': '서울',
              'lat': 37.55,
              'lng': 126.93,
              'phone': '02-1234-5678',
              'distance_meters': null,
              'registered': true,
            },
            <String, Object?>{
              'id': '9000000001',
              'name': '온케어 무브랩',
              'address': '서울 서대문구',
              'lat': 37,
              'lng': 127,
              'phone': '',
              'distance_meters': 320,
              'registered': false,
            },
          ],
        ),
      );

      final gyms = await repository.searchGyms('헬스');

      verify(
        () => dio.get<List<Object?>>(
          '/trainer/gyms/search',
          queryParameters: <String, Object?>{'query': '헬스'},
        ),
      ).called(1);
      expect(gyms.map((g) => g.id), <String>['gym-1', '9000000001']);
      expect(gyms.first.registered, isTrue);
      expect(gyms.first.hasLocation, isTrue);
      expect(gyms.first.distanceMeters, isNull);
      expect(gyms.last.registered, isFalse);
      // 정수로 온 좌표도 실수로 읽는다.
      expect(gyms.last.lat, 37.0);
      expect(gyms.last.distanceMeters, 320);
    });

    Response<List<Object?>> gymListResponse(String path) =>
        Response<List<Object?>>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: <Object?>[
            <String, Object?>{
              'id': 'gym-1',
              'name': '온케어짐',
              'address': '서울',
              'lat': 37.55,
              'lng': 126.93,
              'phone': '',
              'distance_meters': 120,
              'registered': true,
            },
            // id 가 없는 줄은 고를 수 없어 버린다.
            <String, Object?>{'name': '이름만'},
          ],
        );

    test(
      'nearbyGyms sends coordinates to the nearby endpoint (#3223)',
      () async {
        when(
          () => dio.get<List<Object?>>(
            '/trainer/gyms/nearby',
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer((_) async => gymListResponse('/trainer/gyms/nearby'));

        final gyms = await repository.nearbyGyms(lat: 37.5548, lng: 126.9385);

        verify(
          () => dio.get<List<Object?>>(
            '/trainer/gyms/nearby',
            queryParameters: <String, Object?>{'lat': 37.5548, 'lng': 126.9385},
          ),
        ).called(1);
        expect(gyms.map((g) => g.id), <String>['gym-1']);
        expect(gyms.single.distanceMeters, 120);
      },
    );

    test('searchGyms adds coordinates only when both are known', () async {
      when(
        () => dio.get<List<Object?>>(
          '/trainer/gyms/search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => gymListResponse('/trainer/gyms/search'));

      await repository.searchGyms('헬스', lat: 37.5, lng: 126.9);
      await repository.searchGyms('헬스', lat: 37.5);

      final List<Object?> sent = verify(
        () => dio.get<List<Object?>>(
          '/trainer/gyms/search',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(sent, <Object?>[
        <String, Object?>{'query': '헬스', 'lat': 37.5, 'lng': 126.9},
        // 한쪽만 있는 좌표는 서버가 거절한다 — 보내지 않는다.
        <String, Object?>{'query': '헬스'},
      ]);
    });

    test('nearbyGyms maps server errors like search', () async {
      when(
        () => dio.get<List<Object?>>(
          '/trainer/gyms/nearby',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/trainer/gyms/nearby'),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/trainer/gyms/nearby'),
            statusCode: 422,
            data: <String, Object?>{'detail': '좌표를 확인해 주세요.'},
          ),
        ),
      );

      await expectLater(
        repository.nearbyGyms(lat: 0, lng: 0),
        throwsA(isA<AppError>()),
      );
    });

    test('update never sends gym text fields', () async {
      when(
        () => dio.put<Map<String, Object?>>(
          '/trainer/me',
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _profileResponse());

      await repository.update(
        const TrainerProfileUpdate(
          phone: '',
          specialty: '',
          careerYears: 0,
          intro: '',
          certifications: <String>[],
        ),
      );

      final body =
          verify(
                () => dio.put<Map<String, Object?>>(
                  '/trainer/me',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(body.keys.where((k) => k.startsWith('gym_')), isEmpty);
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

    test(
      'gym info is read and saved through the gym profile endpoint',
      () async {
        final Map<String, Object?> body = <String, Object?>{
          'gym_id': 'gym-1',
          'name': '온케어짐',
          'weekday_hours': '06:00 - 23:00',
          'weekend_hours': '09:00 - 18:00',
          'phone': '02-332-1720',
          'tags': <String>['샤워실', 'PT 전문'],
        };
        Response<Map<String, Object?>> response() =>
            Response<Map<String, Object?>>(
              requestOptions: RequestOptions(path: '/trainer/me/gym/profile'),
              statusCode: 200,
              data: body,
            );
        when(
          () => dio.get<Map<String, Object?>>('/trainer/me/gym/profile'),
        ).thenAnswer((_) async => response());
        when(
          () => dio.put<Map<String, Object?>>(
            '/trainer/me/gym/profile',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => response());

        final TrainerGymInfo info = await repository.fetchGymInfo();
        expect(info.weekendHours, '09:00 - 18:00');
        expect(info.tags, <String>['샤워실', 'PT 전문']);

        await repository.updateGymInfo(
          const TrainerGymInfoUpdate(
            weekdayHours: '06:00 - 23:00',
            weekendHours: '09:00 - 18:00',
            phone: '02-332-1720',
            tags: <String>['샤워실', 'PT 전문'],
          ),
        );
        final sent =
            verify(
                  () => dio.put<Map<String, Object?>>(
                    '/trainer/me/gym/profile',
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, Object?>;
        // 평점은 트레이너가 고치는 값이 아니다(#2700).
        expect(sent, isNot(contains('rating')));
        expect(sent['tags'], <String>['샤워실', 'PT 전문']);
      },
    );

    test('gym info without an affiliation keeps the 409 detail', () async {
      when(
        () => dio.get<Map<String, Object?>>('/trainer/me/gym/profile'),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/trainer/me/gym/profile'),
          response: Response<Map<String, Object?>>(
            requestOptions: RequestOptions(path: '/trainer/me/gym/profile'),
            statusCode: 409,
            data: <String, Object?>{'detail': '소속 헬스장이 없습니다.'},
          ),
        ),
      );

      await expectLater(
        repository.fetchGymInfo(),
        throwsA(
          isA<ServerError>()
              .having((error) => error.statusCode, 'status', 409)
              .having((error) => error.message, 'message', '소속 헬스장이 없습니다.'),
        ),
      );
    });
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
    await repository.selectGym((await repository.searchGyms('강남')).single);

    final restored = await repository.fetch();
    expect(restored.phone, '010-7777-8888');
    expect(restored.careerYears, 9);
    expect(restored.gym.id, 'gym-2');
    expect(restored.gym.name, '온케어짐 강남점');
  });

  group('mock gym search (#3223)', () {
    Future<List<String>> ids(String query, {DemoLanguage? language}) async {
      final repository = MockTrainerProfileRepository(
        language: language ?? DemoLanguage.ko,
      );
      return (await repository.searchGyms(
        query,
      )).map((TrainerGymCandidate g) => g.id).toList();
    }

    test('ignores spacing — 붙여 쓴 이름도 찾는다', () async {
      expect(await ids('온케어짐신촌'), <String>[kDemoTrainerGymId]);
    });

    test('ignores word order', () async {
      expect(await ids('신촌 온케어짐'), <String>[kDemoTrainerGymId]);
      expect(await ids('강남점   온케어짐'), <String>['gym-2']);
    });

    test('matches address words together with name words', () async {
      expect(await ids('연희로 스튜디오'), <String>['gym-demo-yeonhui']);
    });

    test('generic gym words narrow nothing on their own', () async {
      expect(await ids('강남 헬스장'), <String>['gym-2']);
      expect(await ids('헬스장'), hasLength(3));
      expect(await ids('피트니스'), hasLength(3));
    });

    test('is case-insensitive in English', () async {
      expect(await ids('ONCARE gangnam', language: DemoLanguage.en), <String>[
        'gym-2',
      ]);
    });

    test('never comes back empty for a real gym name — 데모 헬스장 전체', () async {
      // 데모에는 카카오가 없어 실제 상호는 찾을 수 없다. 빈 목록이면 가입한
      // 트레이너가 소속을 고르지 못한다.
      final List<String> found = await ids('스포애니 신림점');
      expect(found, <String>[kDemoTrainerGymId, 'gym-2', 'gym-demo-yeonhui']);
    });

    test('a blank query searches nothing', () async {
      expect(await ids(''), isEmpty);
      expect(await ids('   '), isEmpty);
    });

    test('a fallback result can still be selected', () async {
      final repository = MockTrainerProfileRepository();
      final List<TrainerGymCandidate> found = await repository.searchGyms(
        '없는 헬스장 이름',
      );
      final TrainerGymCandidate yeonhui = found.singleWhere(
        (TrainerGymCandidate g) => g.id == 'gym-demo-yeonhui',
      );
      final profile = await repository.selectGym(yeonhui);
      expect(profile.gym.id, 'gym-demo-yeonhui');
    });
  });

  group('mock nearby gyms (#3223)', () {
    // 헬스메이트 신촌점 자리 — 데모 신촌점은 약 400m, 연희 스튜디오는 약 1.5km,
    // 강남점은 7km 넘게 떨어져 있다.
    const double lat = 37.5548;
    const double lng = 126.9385;

    test('returns every demo gym with its distance, nearest first', () async {
      final repository = MockTrainerProfileRepository();
      final List<TrainerGymCandidate> gyms = await repository.nearbyGyms(
        lat: lat,
        lng: lng,
      );

      expect(gyms.map((TrainerGymCandidate g) => g.id), <String>[
        kDemoTrainerGymId,
        'gym-demo-yeonhui',
        'gym-2',
      ]);
      final List<int> distances = <int>[
        for (final TrainerGymCandidate g in gyms) g.distanceMeters!,
      ];
      expect(distances, orderedEquals(<int>[...distances]..sort()));
      expect(distances.first, inInclusiveRange(300, 500));
      expect(distances.last, greaterThan(5000));
    });

    test('a demo gym at the exact spot is 0 m away', () async {
      final repository = MockTrainerProfileRepository();
      final List<TrainerGymCandidate> gyms = await repository.nearbyGyms(
        lat: 37.4979,
        lng: 127.0276,
      );
      expect(gyms.first.id, 'gym-2');
      expect(gyms.first.distanceMeters, 0);
      expect(gyms.first.distanceLabel, '0.0km');
    });

    test('name search fills distances only with coordinates', () async {
      final repository = MockTrainerProfileRepository();
      final TrainerGymCandidate plain = (await repository.searchGyms(
        '강남',
      )).single;
      final TrainerGymCandidate located = (await repository.searchGyms(
        '강남',
        lat: lat,
        lng: lng,
      )).single;
      expect(plain.distanceMeters, isNull);
      expect(plain.distanceLabel, isNull);
      expect(located.distanceMeters, greaterThan(5000));
    });

    test('a nearby result can be selected like a search result', () async {
      final repository = MockTrainerProfileRepository();
      final List<TrainerGymCandidate> gyms = await repository.nearbyGyms(
        lat: lat,
        lng: lng,
      );
      final profile = await repository.selectGym(gyms[1]);
      expect(profile.gym.id, 'gym-demo-yeonhui');
    });
  });

  group('TrainerGymCandidate.distanceLabel', () {
    TrainerGymCandidate at(int? meters) => TrainerGymCandidate(
      id: 'g',
      name: 'g',
      address: '',
      registered: true,
      distanceMeters: meters,
    );

    test('shows kilometres with one decimal like the member app', () {
      expect(at(320).distanceLabel, '0.3km');
      expect(at(1450).distanceLabel, '1.4km');
      expect(at(12000).distanceLabel, '12.0km');
      expect(at(null).distanceLabel, isNull);
    });

    test('withDistance keeps every other field', () {
      const TrainerGymCandidate gym = TrainerGymCandidate(
        id: 'gym-x',
        name: '온케어짐',
        address: '서울',
        registered: false,
        lat: 37.5,
        lng: 126.9,
        phone: '02-1',
      );
      final TrainerGymCandidate moved = gym.withDistance(42);
      expect(moved.id, gym.id);
      expect(moved.name, gym.name);
      expect(moved.address, gym.address);
      expect(moved.registered, isFalse);
      expect((moved.lat, moved.lng), (37.5, 126.9));
      expect(moved.phone, '02-1');
      expect(moved.distanceMeters, 42);
    });
  });

  test(
    'mock gym info edit updates the profile copy of hours and phone',
    () async {
      final repository = MockTrainerProfileRepository();
      final TrainerGymInfo before = await repository.fetchGymInfo();
      expect(before.gymId, kDemoTrainerGymId);

      final TrainerGymInfo saved = await repository.updateGymInfo(
        const TrainerGymInfoUpdate(
          weekdayHours: '05:00 - 24:00',
          weekendHours: '08:00 - 20:00',
          phone: '02-332-1720',
          tags: <String>[' 샤워실 ', '샤워실', '24시간'],
        ),
      );
      expect(saved.tags, <String>['샤워실', '24시간']);

      final profile = await repository.fetch();
      expect(profile.gym.hours, '05:00 - 24:00');
      expect(profile.gym.phone, '02-332-1720');
      expect((await repository.fetchGymInfo()).weekendHours, '08:00 - 20:00');
    },
  );
}

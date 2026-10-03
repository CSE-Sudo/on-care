/// 실서버 헬스장 저장소가 기준 좌표의 출처를 따르는가(#3044).
///
/// 회원 위치를 얻기 전에는 `/me/gym` 에 좌표를 싣지 않는다 — 기본 검색 영역(신촌)은
/// 회원의 위치가 아니다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/exercise/data/repositories/dio_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';

void main() {
  late ProviderContainer container;
  late Dio dio;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1'));
    container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://example.test/v1',
            useMockApi: false,
          ),
        ),
        dioProvider.overrideWithValue(dio),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    dio.close();
  });

  test('기본 검색 영역이면 회원 좌표 없이 만든다', () {
    final GymRepository repo = container.read(gymRepositoryProvider);
    expect(repo, isA<DioGymRepository>());
    final DioGymRepository dioRepo = repo as DioGymRepository;
    expect(dioRepo.lat, isNull);
    expect(dioRepo.lng, isNull);
  });

  test('회원 위치를 얻으면 그 좌표로 다시 만든다', () {
    container.read(gymRepositoryProvider);
    container
        .read(gymSearchAreaProvider.notifier)
        .state = const GymSearchArea.userLocation(
      PlaceQuery(lat: 35.1, lng: 129.1, category: PlaceCategory.fitness),
    );
    final DioGymRepository repo =
        container.read(gymRepositoryProvider) as DioGymRepository;
    expect(repo.lat, 35.1);
    expect(repo.lng, 129.1);
  });
}

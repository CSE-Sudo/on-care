// 헬스장 이름 검색 — 검색어 다듬기, 목업 저장소, 검색 provider. (#3355)
//
// 실서버 경로는 서버가 등록된 헬스장과 외부 장소 검색을 합쳐 준다. 목업에는 그
// 서버가 없어 provider 가 주변 장소 목업에서 같은 일을 한다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';
import 'package:oncare/features/place/domain/repositories/place_repository.dart';
import 'package:oncare/features/place/presentation/controllers/place_controller.dart';

const Gym _registered = Gym(
  id: 'gym-registered',
  name: '온케어 부산짐',
  address: '부산 해운대구',
  distanceKm: 325,
  rating: 4.2,
  tags: <String>[],
);

const Place _sameNamePlace = Place(
  id: 'kakao-1',
  name: '온케어부산짐',
  category: PlaceCategory.fitness,
  address: '부산 해운대구 다른 표기',
  distanceMeters: 500,
  lat: 35.16,
  lng: 129.16,
);

const Place _discoveredPlace = Place(
  id: 'kakao-2',
  name: '부산 바다 피트니스',
  category: PlaceCategory.fitness,
  address: '부산 수영구',
  distanceMeters: 1500,
  lat: 35.15,
  lng: 129.11,
);

const Place _otherPlace = Place(
  id: 'kakao-3',
  name: '신촌 헬스',
  category: PlaceCategory.fitness,
  address: '서울 서대문구',
  distanceMeters: 300,
  lat: 37.55,
  lng: 126.93,
);

/// 검색어를 기록하고 정해 둔 결과를 돌려주는 저장소.
class _SearchRepository extends MockGymRepository {
  _SearchRepository(this.result);

  final List<Gym> result;
  final List<String> queries = <String>[];

  @override
  Future<List<Gym>> searchGyms(String query) async {
    queries.add(query);
    return result;
  }
}

class _FailingSearchRepository extends MockGymRepository {
  @override
  Future<List<Gym>> searchGyms(String query) =>
      Future<List<Gym>>.error(StateError('search down'));
}

class _Places implements PlaceRepository {
  _Places(this.places, {this.fail = false});

  final List<Place> places;
  final bool fail;
  int calls = 0;

  @override
  Future<List<Place>> nearbyPlaces(PlaceQuery query) async {
    calls++;
    if (fail) throw StateError('places down');
    return places;
  }
}

AppConfig _config({required bool mock}) => AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: mock,
);

ProviderContainer _container({
  required GymRepository repository,
  required PlaceRepository places,
  required bool mock,
}) {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config(mock: mock)),
      gymRepositoryProvider.overrideWithValue(repository),
      placeRepositoryProvider.overrideWithValue(places),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// autoDispose provider 라 읽는 동안 붙들어 둔다.
Future<List<Gym>> _read(ProviderContainer c, String query) {
  final ProviderSubscription<AsyncValue<List<Gym>>> sub = c.listen(
    gymSearchProvider(query),
    (_, _) {},
  );
  addTearDown(sub.close);
  return c.read(gymSearchProvider(query).future);
}

void main() {
  group('gymSearchQueryOf', () {
    test('앞뒤 공백을 뗀다', () {
      expect(gymSearchQueryOf('  온케어 부산  '), '온케어 부산');
    });

    test('공백뿐이면 빈 검색어다 — 검색하지 않는다', () {
      expect(gymSearchQueryOf(''), '');
      expect(gymSearchQueryOf('   \t'), '');
    });

    test('상한 안의 검색어는 그대로다', () {
      final String exact = '가' * kGymSearchQueryMaxLength;
      expect(gymSearchQueryOf(exact), exact);
    });

    test('상한을 넘는 뒤쪽을 자른다', () {
      final String long = '가' * (kGymSearchQueryMaxLength + 20);
      expect(gymSearchQueryOf(long).runes.length, kGymSearchQueryMaxLength);
    });

    test('글자(코드 포인트)로 센다 — 이모지를 반으로 가르지 않는다', () {
      final String long = '💪' * (kGymSearchQueryMaxLength + 5);
      final String cut = gymSearchQueryOf(long);
      expect(cut.runes.length, kGymSearchQueryMaxLength);
      expect(cut, '💪' * kGymSearchQueryMaxLength);
    });

    test('자른 끝이 공백이면 그 공백도 뗀다', () {
      final String long = '${'가' * (kGymSearchQueryMaxLength - 1)} 나다라';
      expect(gymSearchQueryOf(long), '가' * (kGymSearchQueryMaxLength - 1));
    });
  });

  group('MockGymRepository.searchGyms', () {
    test('이름으로 찾는다 — 띄어쓰기·단어 순서를 보지 않는다', () async {
      final MockGymRepository repo = MockGymRepository();

      final List<Gym> spaced = await repo.searchGyms('헬스메이트신촌');
      final List<Gym> reordered = await repo.searchGyms('신촌점 헬스메이트');

      expect(spaced.map((Gym g) => g.id), <String>['gym-healthmate']);
      expect(reordered.map((Gym g) => g.id), <String>['gym-healthmate']);
    });

    test('주소로도 찾는다', () async {
      final List<Gym> found = await MockGymRepository().searchGyms('신촌로 83');
      expect(found.map((Gym g) => g.id), <String>['gym-healthmate']);
    });

    test('맞는 곳이 없으면 빈 목록이다', () async {
      expect(await MockGymRepository().searchGyms('어디에도없는이름'), isEmpty);
    });

    test('주변 목록에 있는 헬스장만 나온다 — 지어낸 결과가 없다', () async {
      final MockGymRepository repo = MockGymRepository();
      final Set<String> listed = (await repo.fetchNearby())
          .map((Gym g) => g.id)
          .toSet();

      final List<Gym> found = await repo.searchGyms('신촌');

      expect(found, isNotEmpty);
      expect(listed.containsAll(found.map((Gym g) => g.id)), isTrue);
    });
  });

  group('gymSearchProvider — 실서버 경로', () {
    test('저장소가 준 결과를 순서 그대로 돌려준다', () async {
      final _SearchRepository repo = _SearchRepository(const <Gym>[
        _registered,
      ]);
      final _Places places = _Places(const <Place>[_discoveredPlace]);
      final ProviderContainer c = _container(
        repository: repo,
        places: places,
        mock: false,
      );

      final List<Gym> found = await _read(c, '부산');

      expect(found, <Gym>[_registered]);
      expect(repo.queries, <String>['부산']);
    });

    test('주변 장소 검색을 따로 부르지 않는다 — 합치는 일은 서버가 한다', () async {
      final _Places places = _Places(const <Place>[_discoveredPlace]);
      final ProviderContainer c = _container(
        repository: _SearchRepository(const <Gym>[]),
        places: places,
        mock: false,
      );

      expect(await _read(c, '부산'), isEmpty);
      expect(places.calls, 0);
    });

    test('검색어마다 따로 묻는다', () async {
      final _SearchRepository repo = _SearchRepository(const <Gym>[]);
      final ProviderContainer c = _container(
        repository: repo,
        places: _Places(const <Place>[]),
        mock: false,
      );

      await _read(c, '부산');
      await _read(c, '신촌');
      await _read(c, '부산');

      // 같은 검색어를 보고 있는 동안은 다시 묻지 않는다.
      expect(repo.queries, <String>['부산', '신촌']);
    });

    test('저장소 오류는 오류로 남는다', () async {
      final ProviderContainer c = _container(
        repository: _FailingSearchRepository(),
        places: _Places(const <Place>[]),
        mock: false,
      );

      await expectLater(_read(c, '부산'), throwsA(isA<StateError>()));
    });
  });

  group('gymSearchProvider — 목업 경로', () {
    test('등록된 헬스장 뒤에 주변 장소에서 이름이 맞는 곳을 잇는다', () async {
      final ProviderContainer c = _container(
        repository: _SearchRepository(const <Gym>[_registered]),
        places: _Places(const <Place>[_discoveredPlace, _otherPlace]),
        mock: true,
      );

      final List<Gym> found = await _read(c, '부산');

      expect(found.map((Gym g) => g.id), <String>['gym-registered', 'kakao-2']);
    });

    test('검색어에 맞지 않는 주변 장소는 잇지 않는다', () async {
      final ProviderContainer c = _container(
        repository: _SearchRepository(const <Gym>[]),
        places: _Places(const <Place>[_discoveredPlace, _otherPlace]),
        mock: true,
      );

      expect((await _read(c, '신촌')).map((Gym g) => g.id), <String>['kakao-3']);
    });

    test('주변 장소는 주소로도 맞춘다', () async {
      final ProviderContainer c = _container(
        repository: _SearchRepository(const <Gym>[]),
        places: _Places(const <Place>[_discoveredPlace, _otherPlace]),
        mock: true,
      );

      expect((await _read(c, '수영구')).map((Gym g) => g.id), <String>['kakao-2']);
    });

    test('등록된 헬스장과 이름이 같은 주변 장소는 한 번만 싣는다', () async {
      final ProviderContainer c = _container(
        repository: _SearchRepository(const <Gym>[_registered]),
        places: _Places(const <Place>[_sameNamePlace]),
        mock: true,
      );

      final List<Gym> found = await _read(c, '온케어');

      // 띄어쓰기만 다른 같은 헬스장 — 정보가 더 많은 등록 쪽이 남는다.
      expect(found, <Gym>[_registered]);
    });

    test('주변 장소 검색이 실패해도 등록된 헬스장 결과는 보인다', () async {
      final ProviderContainer c = _container(
        repository: _SearchRepository(const <Gym>[_registered]),
        places: _Places(const <Place>[], fail: true),
        mock: true,
      );

      expect(await _read(c, '부산'), <Gym>[_registered]);
    });
  });
}

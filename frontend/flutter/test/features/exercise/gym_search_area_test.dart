/// 헬스장 찾기 기준 좌표와 출처(#3044).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';

void main() {
  test('기본 검색 영역은 신촌이고 회원 위치가 아니다', () {
    const GymSearchArea area = GymSearchArea.defaultArea();
    expect(area.lat, kGymDefaultAreaLat);
    expect(area.lng, kGymDefaultAreaLng);
    expect(area.origin, GymSearchOrigin.defaultArea);
    expect(area.isUserLocation, isFalse);
    expect(area.query.category, PlaceCategory.fitness);
  });

  test('회원 위치는 그 좌표를 그대로 검색 중심으로 쓴다', () {
    const PlaceQuery q = PlaceQuery(
      lat: 35.1,
      lng: 129.1,
      category: PlaceCategory.fitness,
    );
    const GymSearchArea area = GymSearchArea.userLocation(q);
    expect(area.isUserLocation, isTrue);
    expect(area.lat, 35.1);
    expect(area.lng, 129.1);
    expect(identical(area.query, q), isTrue);
  });

  test('같은 좌표라도 출처가 다르면 다른 값이다', () {
    const GymSearchArea byDefault = GymSearchArea.defaultArea();
    const GymSearchArea byUser = GymSearchArea.userLocation(
      PlaceQuery(
        lat: kGymDefaultAreaLat,
        lng: kGymDefaultAreaLng,
        category: PlaceCategory.fitness,
      ),
    );
    expect(byDefault == byUser, isFalse);
    expect(byDefault, const GymSearchArea.defaultArea());
  });

  test('앱을 켜면 기본 검색 영역에서 시작한다 — 저장해 둔 위치가 없다', () {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(gymSearchAreaProvider), const GymSearchArea.defaultArea());
  });
}

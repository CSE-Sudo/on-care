/// 장소 응답의 좌표 계약. (#2879)
///
/// 서버 `PlaceOut.lat/lng` 는 null 을 허용하는데 앱은 필수로 읽어, 좌표 없는
/// 장소가 한 곳만 섞여도 목록 전체 파싱이 실패했다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/place/domain/entities/place.dart';

Map<String, Object?> _row({Object? lat = 37.55, Object? lng = 126.93}) =>
    <String, Object?>{
      'id': 'kakao-1',
      'name': '신촌 헬스',
      'category': 'fitness',
      'address': '서울 서대문구',
      'distance_meters': 320,
      'lat': lat,
      'lng': lng,
    };

void main() {
  test('좌표가 있으면 그대로 읽는다', () {
    final Place p = Place.fromJson(_row());
    expect(p.lat, 37.55);
    expect(p.lng, 126.93);
    expect(p.category, PlaceCategory.fitness);
    expect(p.distanceMeters, 320);
  });

  test('정수 좌표도 실수로 읽는다', () {
    final Place p = Place.fromJson(_row(lat: 37, lng: 127));
    expect(p.lat, 37.0);
    expect(p.lng, 127.0);
  });

  test('좌표가 null 이어도 장소는 읽힌다', () {
    final Place p = Place.fromJson(_row(lat: null, lng: null));
    expect(p.name, '신촌 헬스');
    expect(p.lat, isNull);
    expect(p.lng, isNull);
  });

  test('좌표 키가 아예 없어도 장소는 읽힌다', () {
    final Map<String, Object?> row = _row()
      ..remove('lat')
      ..remove('lng');
    final Place p = Place.fromJson(row);
    expect(p.lat, isNull);
    expect(p.lng, isNull);
  });

  test('좌표 없는 장소가 섞여도 목록 전체가 읽힌다', () {
    final List<Place> places = <Map<String, Object?>>[
      _row(),
      _row(lat: null, lng: null),
    ].map(Place.fromJson).toList();
    expect(places, hasLength(2));
    expect(places.where((Place p) => p.lat != null), hasLength(1));
  });
}

/// 헬스장 찾기의 기준 좌표 — 지도 중심이자 조회 기준. (#324, #329, #3044)
///
/// 지도(`_GymMap`)와 목록 조회(`DioGymRepository`, `gymFinderResultsProvider`)가
/// **같은 값**을 써야 한다. 두 곳에 따로 두면 한쪽만 바뀌었을 때 지도 중심과 검색
/// 중심이 조용히 어긋난다.
///
/// 좌표에는 **출처**가 함께 붙는다. 회원 위치를 얻기 전에는 기본 검색 영역(신촌)을
/// 검색 중심으로만 쓰고, 그 지점에서 잰 거리는 화면에 그리지 않는다 — 회원이 자기
/// 주변 결과로 읽기 때문이다(#3044).
library;

import 'package:flutter/foundation.dart';

import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';

/// 회원 위치를 얻기 전의 기본 검색 영역(신촌). 목록 조회에 검색 중심이 필요해
/// 두는 값이지, 회원의 위치가 아니다.
const double kGymDefaultAreaLat = 37.5559;
const double kGymDefaultAreaLng = 126.9368;

/// 기준 좌표가 어디서 왔나.
enum GymSearchOrigin {
  /// 기기에서 얻은 회원의 현재 위치. 거리·거리순이 의미가 있다.
  userLocation,

  /// 위치를 얻기 전의 기본 검색 영역. 거리는 회원과 무관한 값이다.
  defaultArea,
}

/// 헬스장 찾기의 기준 좌표와 그 출처.
///
/// 좌표는 기기 메모리(앱 실행 동안)에만 둔다. 기기·서버 어디에도 저장하지
/// 않는다(개인정보 처리방침 1-⑤).
@immutable
class GymSearchArea {
  const GymSearchArea._(this.query, this.origin);

  /// 기본 검색 영역(신촌).
  const GymSearchArea.defaultArea()
    : this._(
        const PlaceQuery(
          lat: kGymDefaultAreaLat,
          lng: kGymDefaultAreaLng,
          category: PlaceCategory.fitness,
        ),
        GymSearchOrigin.defaultArea,
      );

  /// 기기에서 얻은 회원 위치.
  const GymSearchArea.userLocation(PlaceQuery query)
    : this._(query, GymSearchOrigin.userLocation);

  /// 주변 장소 검색에 그대로 넘기는 값.
  final PlaceQuery query;
  final GymSearchOrigin origin;

  double get lat => query.lat;
  double get lng => query.lng;

  /// 회원 위치 기준인가 — 거리 표시·거리순·`/me/gym` 좌표가 이 값을 본다.
  bool get isUserLocation => origin == GymSearchOrigin.userLocation;

  @override
  bool operator ==(Object other) =>
      other is GymSearchArea &&
      other.origin == origin &&
      other.lat == lat &&
      other.lng == lng &&
      other.query.category == query.category &&
      other.query.radiusMeters == query.radiusMeters;

  @override
  int get hashCode =>
      Object.hash(origin, lat, lng, query.category, query.radiusMeters);

  @override
  String toString() => 'GymSearchArea($origin, $lat, $lng)';
}

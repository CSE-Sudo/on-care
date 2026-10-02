// 주변 헬스장 경로(/places/nearby).

part of '../local_api_interceptor.dart';

extension _LocalApiPlaces on LocalApiInterceptor {
  Future<Response<Object?>> _placesNearby(RequestOptions options) async {
    const rows = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'p1',
        'name': '강남세브란스 가정의학과',
        'category': 'medical',
        'address': '서울특별시 강남구 테헤란로 123',
        'distance_meters': 420,
        'lat': 37.4979,
        'lng': 127.0276,
      },
      <String, Object?>{
        'id': 'p3',
        'name': '그린 샐러드 바',
        'category': 'healthy_food',
        'address': '서울특별시 강남구 강남대로 311',
        'distance_meters': 250,
        'lat': 37.4970,
        'lng': 127.0270,
      },
      <String, Object?>{
        'id': 'p4',
        'name': '24시간 메디팜약국',
        'category': 'pharmacy',
        'address': '서울특별시 강남구 테헤란로 99',
        'distance_meters': 800,
        'lat': 37.4995,
        'lng': 127.0263,
      },
      // 헬스장 찾기(#329)가 보는 신촌 권역 비제휴 후보. **가상 헬스장**이다 — 예전에는
      // 카카오 실응답의 실재 업체를 옮겨 와 가상 트레이너를 붙였는데, 실재 업체에
      // 실존하지 않는 직원을 붙이는 것이라 가상 상호로 바꿨다(#2811). id 는 백엔드
      // 시드(`seed_gyms._DEMO_NONPARTNER_GYMS`)와 같아 실 API 로 전환해도 그대로
      // 매칭된다(`kakao_gym_demo_profile.dart`).
      <String, Object?>{
        'id': 'gym-demo-fitstudio',
        'name': '온케어 핏스튜디오',
        'category': 'fitness',
        'address': '서울 마포구 신촌로 90',
        'distance_meters': 127,
        'lat': 37.5551767,
        'lng': 126.9356861,
      },
      <String, Object?>{
        'id': 'gym-demo-movelab',
        'name': '온케어 무브랩',
        'category': 'fitness',
        'address': '서울 서대문구 연세로 20',
        'distance_meters': 186,
        'lat': 37.5573727,
        'lng': 126.9378164,
      },
      <String, Object?>{
        'id': 'gym-demo-ptlab',
        'name': '온케어 PT랩',
        'category': 'fitness',
        'address': '서울 서대문구 연세로 12',
        'distance_meters': 133,
        'lat': 37.5570723,
        'lng': 126.9371422,
      },
      <String, Object?>{
        'id': 'gym-demo-onestudio',
        'name': '온케어 1:1 스튜디오',
        'category': 'fitness',
        'address': '서울 서대문구 명물길 30',
        'distance_meters': 177,
        'lat': 37.5573852,
        'lng': 126.9375437,
      },
      // 신촌 밖에서 위치를 허용하면 위 네 곳이 반경 밖이라 목록이 비었다(#2661).
      // 자주 시연하는 권역(강남역·홍대입구역·잠실역)의 카카오 Local `헬스장` 검색
      // 실응답을 같은 방식으로 옮겼다. 거리는 초기 지도 중심(신촌) 기준이고, 좌표가
      // 오면 아래에서 다시 잰다. 시연용 보강 값(`kakao_gym_demo_profile.dart`)은
      // 두지 않아 평점·태그 없이 그린다.
      // 강남역
      <String, Object?>{
        'id': '27280559',
        'name': '스포애니 강남역1호점',
        'category': 'fitness',
        'address': '서울 강남구 강남대로78길 8',
        'distance_meters': 10678,
        'lat': 37.4946647,
        'lng': 127.03008422,
      },
      <String, Object?>{
        'id': '1426076788',
        'name': '스포애니 역삼역점',
        'category': 'fitness',
        'address': '서울 강남구 테헤란로 146',
        'distance_meters': 10691,
        'lat': 37.49998997,
        'lng': 127.03543776,
      },
      <String, Object?>{
        'id': '1710995183',
        'name': 'F45 역삼',
        'category': 'fitness',
        'address': '서울 강남구 테헤란로14길 13',
        'distance_meters': 10649,
        'lat': 37.49854351,
        'lng': 127.03351911,
      },
      <String, Object?>{
        'id': '27440610',
        'name': '스포애니 강남역2호점',
        'category': 'fitness',
        'address': '서울 서초구 서초대로78길 44',
        'distance_meters': 10631,
        'lat': 37.49379653,
        'lng': 127.02846456,
      },
      // 홍대입구역
      <String, Object?>{
        'id': '355866189',
        'name': 'F45 합정',
        'category': 'fitness',
        'address': '서울 마포구 양화로 85',
        'distance_meters': 1785,
        'lat': 37.55228104,
        'lng': 126.91706103,
      },
      <String, Object?>{
        'id': '1521470440',
        'name': '에이블짐 홍대입구역점',
        'category': 'fitness',
        'address': '서울 마포구 양화로 186',
        'distance_meters': 981,
        'lat': 37.55766857,
        'lng': 126.92589302,
      },
      <String, Object?>{
        'id': '1001520518',
        'name': '짐박스피트니스 홍대입구점',
        'category': 'fitness',
        'address': '서울 마포구 양화로 144',
        'distance_meters': 1272,
        'lat': 37.55533994,
        'lng': 126.92238583,
      },
      <String, Object?>{
        'id': '142489778',
        'name': '아크로짐 홍대점24시휘트니스',
        'category': 'fitness',
        'address': '서울 마포구 월드컵북로 30',
        'distance_meters': 1544,
        'lat': 37.55735976,
        'lng': 126.91937098,
      },
      // 잠실역
      <String, Object?>{
        'id': '1781300886',
        'name': 'F45 잠실',
        'category': 'fitness',
        'address': '서울 송파구 송파대로 558',
        'distance_meters': 15064,
        'lat': 37.51509458,
        'lng': 127.09971196,
      },
      <String, Object?>{
        'id': '15209409',
        'name': '스포애니 잠실점',
        'category': 'fitness',
        'address': '서울 송파구 삼학사로 99',
        'distance_meters': 15173,
        'lat': 37.5060787,
        'lng': 127.09698899,
      },
      <String, Object?>{
        'id': '1192524319',
        'name': '에이블짐 잠실역점',
        'category': 'fitness',
        'address': '서울 송파구 올림픽로35가길 11',
        'distance_meters': 15390,
        'lat': 37.51632971,
        'lng': 127.10406058,
      },
      <String, Object?>{
        'id': '1645271768',
        'name': '헬스보이짐 잠실점',
        'category': 'fitness',
        'address': '서울 송파구 올림픽로 240',
        'distance_meters': 15065,
        'lat': 37.51131078,
        'lng': 127.0981404,
      },
    ];

    // category 는 언제나 존중한다 — 필터링하지 않으면 헬스장 찾기에 병원·약국이
    // 섞여 들어온다.
    //
    // 좌표가 실제로 전달된 요청은 거리도 그 중심 기준으로 다시 재고 radius_m 밖을
    // 잘라낸다. 고정 거리를 그대로 주면 지도 중심을 옮겼을 때 mock 과 실 응답이
    // 어긋난다(리뷰 지적). 좌표가 없으면 걸러낼 기준이 없으므로 픽스처를 그대로
    // 준다 — 이 픽스처는 여러 동네에 흩어져 있어 백엔드 기본 중심(서울시청·3km)을
    // 적용하면 전부 사라진다. 실 백엔드의 시드는 시청 근처라 그런 문제가 없다.
    final Map<String, dynamic> q = options.queryParameters;
    final String? category = q['category'] as String?;
    final double? lat = _asDouble(q['lat']);
    final double? lng = _asDouble(q['lng']);
    final int radiusM = (_asDouble(q['radius_m']) ?? 3000).round();

    final List<Map<String, Object?>> out = <Map<String, Object?>>[];
    for (final Map<String, Object?> row in rows) {
      if (category != null && row['category'] != category) continue;
      if (lat == null || lng == null) {
        out.add(row);
        continue;
      }
      final int distance = _haversineMeters(
        lat,
        lng,
        row['lat']! as double,
        row['lng']! as double,
      );
      if (distance > radiusM) continue;
      out.add(<String, Object?>{...row, 'distance_meters': distance});
    }
    out.sort(
      (Map<String, Object?> a, Map<String, Object?> b) =>
          (a['distance_meters']! as int).compareTo(
            b['distance_meters']! as int,
          ),
    );
    return _ok(options, out);
  }
}

double? _asDouble(Object? v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// 두 좌표 사이 거리(m). 백엔드 `places.py` 의 `_haversine_m` 과 같은 계산이다.
///
/// 마지막 변환은 반올림이 아니라 **절삭**이어야 한다 — 백엔드가 `int(...)` 로
/// 소수점을 버리므로, `round()` 를 쓰면 같은 좌표에서 mock 과 실 응답의
/// `distance_meters` 가 1m 어긋난다(리뷰 지적).
int _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const double r = 6371000;
  final double p1 = lat1 * math.pi / 180;
  final double p2 = lat2 * math.pi / 180;
  final double dp = (lat2 - lat1) * math.pi / 180;
  final double dl = (lng2 - lng1) * math.pi / 180;
  final double a =
      math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return (r * 2 * math.asin(math.sqrt(a))).toInt();
}

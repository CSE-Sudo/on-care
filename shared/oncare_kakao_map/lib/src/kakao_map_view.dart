import 'package:flutter/widgets.dart';

import 'package:oncare_kakao_map/src/kakao_map_config.dart';
import 'package:oncare_kakao_map/src/kakao_map_platform_stub.dart'
    if (dart.library.js_interop) 'package:oncare_kakao_map/src/kakao_map_platform_web.dart'
    as platform;

/// 카카오맵 위젯. 키가 없거나(빌드에 `KAKAO_JS_KEY` 미주입) web 이 아니거나
/// SDK 로드가 실패하면 [fallback] 을 그대로 그린다 — 데모가 절대 비지 않게 하기
/// 위한 #329 요건이다.
class KakaoMapView extends StatelessWidget {
  const KakaoMapView({
    super.key,
    required this.centerLat,
    required this.centerLng,
    required this.markers,
    required this.fallback,
    this.level = 5,
    this.onMarkerTap,
  });

  final double centerLat;
  final double centerLng;
  final List<KakaoMapMarker> markers;

  /// 지도를 못 띄울 때 대신 그릴 위젯(기존 그림 지도).
  final Widget fallback;

  /// 카카오 확대 레벨 — 값이 작을수록 확대. 1~14.
  final int level;

  /// 핀을 눌렀을 때. `KakaoMapMarker.id` 가 있는 핀만 알린다.
  final ValueChanged<KakaoMapMarker>? onMarkerTap;

  @override
  Widget build(BuildContext context) =>
      platform.buildKakaoMap(
        centerLat: centerLat,
        centerLng: centerLng,
        markers: markers,
        level: level,
        fallback: fallback,
        onMarkerTap: onMarkerTap,
      ) ??
      fallback;
}

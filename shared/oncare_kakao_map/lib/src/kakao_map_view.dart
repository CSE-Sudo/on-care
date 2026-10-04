import 'package:flutter/widgets.dart';

import 'package:oncare_kakao_map/src/kakao_map_config.dart';
import 'package:oncare_kakao_map/src/kakao_map_platform_mobile.dart'
    if (dart.library.js_interop) 'package:oncare_kakao_map/src/kakao_map_platform_web.dart'
    as platform;

/// 카카오맵 위젯. 웹은 JS SDK 를 `HtmlElementView` 로, 안드로이드·iOS 는 같은
/// SDK 를 WebView 로 띄운다(#3043). 키가 없거나(빌드에 `KAKAO_JS_KEY` 미주입)
/// 지도를 띄울 수 없는 타깃이거나 SDK 로드가 실패하면 [fallback] 을 그대로
/// 그린다 — 지도 자리가 절대 비지 않게 하기 위한 #329 요건이다.
class KakaoMapView extends StatelessWidget {
  const KakaoMapView({
    super.key,
    required this.centerLat,
    required this.centerLng,
    required this.markers,
    required this.fallback,
    this.level = 5,
    this.onMarkerTap,
    this.onUnavailable,
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

  /// SDK 를 불러오지 못해 [fallback] 으로 떨어졌을 때(도메인 미등록·키 오류·
  /// 네트워크 차단). 지도 자리를 접고 싶은 화면이 쓴다 — 키가 없는 빌드는
  /// [isKakaoMapConfigured] 로 미리 알 수 있어 여기로 오지 않는다.
  final VoidCallback? onUnavailable;

  @override
  Widget build(BuildContext context) =>
      platform.buildKakaoMap(
        centerLat: centerLat,
        centerLng: centerLng,
        markers: markers,
        level: level,
        fallback: fallback,
        onMarkerTap: onMarkerTap,
        onUnavailable: onUnavailable,
      ) ??
      fallback;
}

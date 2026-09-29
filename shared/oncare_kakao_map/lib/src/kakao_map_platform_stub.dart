import 'package:flutter/widgets.dart';

import 'package:oncare_kakao_map/src/kakao_map_config.dart';

/// 비-web 타깃(안드로이드·iOS·테스트)에서는 지도를 만들지 않는다.
///
/// 카카오는 Flutter 용 지도 SDK 를 제공하지 않는다. 웹은 JS SDK 를
/// `HtmlElementView` 로 직접 삽입하고, 네이티브가 필요해지면 WebView 래퍼
/// (`kakao_map_plugin`)를 여기에 끼워 넣으면 된다 — 교체 지점이 이 파일 하나다.
Widget? buildKakaoMap({
  required double centerLat,
  required double centerLng,
  required List<KakaoMapMarker> markers,
  required int level,
  required Widget fallback,
  ValueChanged<KakaoMapMarker>? onMarkerTap,
  VoidCallback? onUnavailable,
}) => null;

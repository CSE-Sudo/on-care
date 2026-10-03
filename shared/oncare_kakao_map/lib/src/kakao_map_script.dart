import 'dart:convert';

import 'package:oncare_kakao_map/src/kakao_map_config.dart';

/// 카카오맵 JS SDK 주소. 웹(`HtmlElementView`)과 모바일(WebView)이 같은 SDK 를
/// 쓴다 — 두 지도가 다른 버전으로 갈라지지 않게 한 곳에 둔다(#3043).
const String kKakaoMapSdkUrl = 'https://dapi.kakao.com/v2/maps/sdk.js';

/// SDK 로드 제한 시간. 스크립트가 load/error 어느 쪽도 알리지 않는 경우
/// (프록시 지연·네트워크 블랙홀 등) 지도가 영영 빈 채로 남지 않게 한다.
const Duration kKakaoMapSdkTimeout = Duration(seconds: 10);

/// 모바일 지도 문서가 Dart 로 소식을 보내는 JavaScript 채널 이름.
const String kKakaoMapChannel = 'OnCareKakaoMap';

/// `appkey` 를 붙인 SDK 주소. `autoload=false` 로 받아 `kakao.maps.load` 로
/// 초기화를 기다린다 — autoload 를 켜면 스크립트 onload 시점과 실제 준비
/// 시점이 어긋난다.
String kakaoMapSdkSrc(String appKey) =>
    '$kKakaoMapSdkUrl?appkey=${Uri.encodeQueryComponent(appKey)}'
    '&autoload=false';

/// Dart 값을 JS 리터럴로 옮긴다. HTML `<script>` 안에 그대로 넣어도 안전하다.
///
/// JSON 은 따옴표·역슬래시·한글을 JS 문자열로 옮기지만 `</script>` 를 막지
/// 않는다 — 헬스장 이름에 그 글자가 들어 있으면 문서가 거기서 끊긴다. `<` 와
/// 줄 구분 문자(U+2028·U+2029)를 이스케이프해 둔다.
String kakaoMapJsLiteral(Object? value) => jsonEncode(value)
    .replaceAll('<', r'<')
    .replaceAll('>', r'>')
    .replaceAll('&', r'&')
    .replaceAll(' ', r' ')
    .replaceAll(' ', r' ');

/// 좌표가 유한한 수인가. NaN·무한대는 JSON 으로 옮길 수 없고 지도도 그릴 수 없다.
bool _finite(double v) => v.isFinite;

/// 마커 목록을 JS 에 넘길 값으로 바꾼다. 좌표가 잘못된 핀은 뺀다 — 엉뚱한
/// 자리에 찍느니 찍지 않는다.
List<Map<String, Object?>> kakaoMapMarkerData(List<KakaoMapMarker> markers) =>
    <Map<String, Object?>>[
      for (final KakaoMapMarker m in markers)
        if (_finite(m.lat) && _finite(m.lng))
          <String, Object?>{
            'lat': m.lat,
            'lng': m.lng,
            'title': m.title,
            if (m.id != null) 'id': m.id,
          },
    ];

/// 지도 중심을 옮기는 스크립트. 문서를 다시 불러오지 않는다.
String kakaoMapSetCenterScript(double lat, double lng) {
  if (!_finite(lat) || !_finite(lng)) return '';
  return 'window.onCareSetCenter('
      '${kakaoMapJsLiteral(lat)},${kakaoMapJsLiteral(lng)});';
}

/// 마커를 모두 바꿔 찍는 스크립트. 문서를 다시 불러오지 않는다.
String kakaoMapSetMarkersScript(List<KakaoMapMarker> markers) =>
    'window.onCareSetMarkers('
    '${kakaoMapJsLiteral(kakaoMapMarkerData(markers))});';

/// 모바일 WebView 에 띄울 지도 문서(#3043).
///
/// 웹 구현과 같은 규칙으로 그린다 — SDK 를 `autoload=false` 로 받아 초기화를
/// 기다리고, 확대·축소 버튼은 SDK 에 있을 때만 붙이고, 컨테이너 크기가 바뀌면
/// 한 박자 미뤄 relayout 한 뒤 중심을 되돌린다. 준비·실패·마커 탭은
/// [kKakaoMapChannel] 로 `{"type": ...}` JSON 을 보낸다.
String kakaoMapHtml({
  required String appKey,
  required double centerLat,
  required double centerLng,
  required int level,
  required List<KakaoMapMarker> markers,
}) {
  final String sdk = kakaoMapJsLiteral(kakaoMapSdkSrc(appKey));
  final String center = kakaoMapJsLiteral(<String, double>{
    'lat': _finite(centerLat) ? centerLat : 0,
    'lng': _finite(centerLng) ? centerLng : 0,
  });
  final String initialMarkers = kakaoMapJsLiteral(kakaoMapMarkerData(markers));
  final String channel = kakaoMapJsLiteral(kKakaoMapChannel);
  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>html,body,#map{margin:0;padding:0;width:100%;height:100%;overflow:hidden;}</style>
</head>
<body>
<div id="map"></div>
<script>
(function () {
  function post(message) {
    try { window[$channel].postMessage(JSON.stringify(message)); } catch (e) {}
  }
  var map = null;
  var pins = [];
  var center = $center;
  var pending = $initialMarkers;
  var relayoutTimer = null;

  function latLng(lat, lng) { return new kakao.maps.LatLng(lat, lng); }

  function draw(list) {
    for (var i = 0; i < pins.length; i++) { pins[i].setMap(null); }
    pins = [];
    for (var j = 0; j < list.length; j++) {
      (function (m) {
        var marker = new kakao.maps.Marker({ position: latLng(m.lat, m.lng), title: m.title });
        marker.setMap(map);
        if (m.id !== undefined && m.id !== null && kakao.maps.event) {
          kakao.maps.event.addListener(marker, 'click', function () {
            post({ type: 'marker', id: m.id });
          });
        }
        pins.push(marker);
      })(list[j]);
    }
  }

  window.onCareSetCenter = function (lat, lng) {
    center = { lat: lat, lng: lng };
    if (map) { map.setCenter(latLng(lat, lng)); }
  };
  window.onCareSetMarkers = function (list) {
    pending = list;
    if (map) { draw(list); }
  };

  function relayout() {
    if (!map) { return; }
    var el = document.getElementById('map');
    if (el.clientWidth === 0 || el.clientHeight === 0) { return; }
    map.relayout();
    map.setCenter(latLng(center.lat, center.lng));
  }
  window.addEventListener('resize', function () {
    if (relayoutTimer) { clearTimeout(relayoutTimer); }
    relayoutTimer = setTimeout(relayout, 120);
  });

  function init() {
    map = new kakao.maps.Map(document.getElementById('map'), {
      center: latLng(center.lat, center.lng),
      level: $level
    });
    if (kakao.maps.ZoomControl && kakao.maps.ControlPosition) {
      map.addControl(new kakao.maps.ZoomControl(), kakao.maps.ControlPosition.RIGHT);
    }
    draw(pending);
    setTimeout(relayout, 0);
    post({ type: 'ready' });
  }

  var script = document.createElement('script');
  script.src = $sdk;
  script.async = true;
  script.onload = function () {
    if (!window.kakao || !kakao.maps) { post({ type: 'error', reason: 'sdk' }); return; }
    try { kakao.maps.load(function () {
      try { init(); } catch (e) { post({ type: 'error', reason: 'init' }); }
    }); } catch (e) { post({ type: 'error', reason: 'load' }); }
  };
  script.onerror = function () { post({ type: 'error', reason: 'network' }); };
  document.head.appendChild(script);
})();
</script>
</body>
</html>
''';
}

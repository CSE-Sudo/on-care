import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// `navigator.geolocation` 으로 현재 위치를 읽는다. 처음이면 브라우저가 권한을
/// 묻는다. 정밀도는 낮게 두고(지도 시작점이라 동네면 충분하다), 최근 값이 있으면
/// 그대로 쓴다.
Future<({double lat, double lng})?> readCurrentPosition() {
  final Completer<({double lat, double lng})?> done =
      Completer<({double lat, double lng})?>();
  void finish(({double lat, double lng})? value) {
    if (!done.isCompleted) done.complete(value);
  }

  try {
    web.window.navigator.geolocation.getCurrentPosition(
      ((web.GeolocationPosition position) {
        finish((lat: position.coords.latitude, lng: position.coords.longitude));
      }).toJS,
      ((web.GeolocationPositionError _) => finish(null)).toJS,
      web.PositionOptions(
        enableHighAccuracy: false,
        timeout: 10000,
        maximumAge: 600000,
      ),
    );
  } catch (_) {
    // 위치 API 가 없거나(오래된 브라우저·안전하지 않은 출처) 막힌 경우.
    finish(null);
  }
  // 권한 창을 닫지 않고 두면 브라우저는 timeout 을 세지 않는다 — 기다리게 두지 않는다.
  return done.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () => null,
  );
}

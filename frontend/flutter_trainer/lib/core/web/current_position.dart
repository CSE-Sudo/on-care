/// 브라우저의 현재 위치를 한 번 읽는다. (#3206)
///
/// 소속 헬스장이 없는 트레이너의 헬스장 찾기 지도를 내 주변에서 시작하려고
/// 쓴다. 권한 거부·시간 초과·위치를 못 읽는 브라우저면 `null` 이고, 호출부는
/// 기본 위치로 둔다 — 위치는 지도 시작점일 뿐이라 실패를 따로 알리지 않는다.
/// 웹이 아닌 곳(테스트 등)에서는 늘 `null` 이다.
library;

export 'current_position_stub.dart'
    if (dart.library.js_interop) 'current_position_web.dart';

/// 카카오맵 위젯 — 회원 앱 헬스장 찾기와 트레이너 웹 소속 헬스장 찾기가 함께 쓴다.
///
/// 회원 앱에만 있던 것을 옮겼다(#2543). 두 앱이 같은 지도 규칙(키 주입·폴백·
/// 크기 재계산)을 따로 고치지 않게 한 곳에 둔다.
library;

export 'package:oncare_kakao_map/src/kakao_map_config.dart'
    show KakaoMapMarker, isKakaoMapConfigured, kakaoJsKey;
export 'package:oncare_kakao_map/src/kakao_map_view.dart' show KakaoMapView;

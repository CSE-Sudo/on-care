/// 카카오맵 JavaScript 키.
///
/// 빌드 시 주입한다 — 소스/저장소에 키를 남기지 않기 위해서다:
///
///   flutter run  -d web-server --dart-define=KAKAO_JS_KEY=xxxx
///   flutter build web --release --dart-define=KAKAO_JS_KEY=xxxx
///
/// JS 키는 페이지 소스에 드러나는 것이 전제인 클라이언트 키이고, 카카오 콘솔의
/// **Web 플랫폼 도메인 등록**으로 보호된다. 도메인을 등록하지 않으면 지도가 뜨지
/// 않는다. 서버 전용인 REST API 키(`KAKAO_REST_API_KEY`)와 절대 섞지 말 것.
const String kakaoJsKey = String.fromEnvironment('KAKAO_JS_KEY');

/// 키가 없으면 지도를 시도하지 않고 폴백 그래픽을 그린다(#329).
bool get isKakaoMapConfigured => kakaoJsKey.isNotEmpty;

/// 지도에 찍을 핀 하나.
class KakaoMapMarker {
  const KakaoMapMarker({
    required this.lat,
    required this.lng,
    required this.title,
    this.id,
  });

  final double lat;
  final double lng;
  final String title;

  /// 핀을 눌렀을 때 누가 눌렸는지 알려 줄 값(`KakaoMapView.onMarkerTap`).
  /// 누를 일이 없는 지도는 비워 둔다.
  final String? id;
}

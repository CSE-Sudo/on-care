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

/// 모바일 WebView 가 지도 문서를 띄우는 출처(#3043).
///
/// 카카오 JS 키는 콘솔의 **JavaScript SDK 도메인** 목록으로만 보호된다(#2913).
/// WebView 는 이 주소를 출처로 SDK 를 부르므로, 이 값은 목록에 이미 있는 주소여야
/// 지도가 뜬다. 배포 빌드는 운영 회원 웹 주소를 넣는다 — 운영 목록에 `localhost`
/// 를 더하지 않기 위해서다:
///
///   flutter build appbundle --dart-define=KAKAO_JS_KEY=xxxx \
///     --dart-define=KAKAO_MAP_ORIGIN=https://<운영 회원 웹 주소>
///
/// 비우면 로컬 개발용 `http://localhost` 다. 실제로 이 주소에 요청을 보내지는 않는다.
const String kakaoMapMobileOrigin = String.fromEnvironment(
  'KAKAO_MAP_ORIGIN',
  defaultValue: 'http://localhost',
);

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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:oncare_kakao_map/src/kakao_map_config.dart';
import 'package:oncare_kakao_map/src/kakao_map_script.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 비-web 타깃(안드로이드·iOS)은 카카오맵 JS SDK 를 WebView 에 띄운다(#3043).
///
/// 카카오는 Flutter 지도 SDK 가 없다. 웹 구현과 같은 JS SDK 를
/// `webview_flutter`(iOS WKWebView·안드로이드 WebView)로 띄워 두 지도가 같은
/// 동작을 하게 한다. 다음이면 `null` 을 돌려 [KakaoMapView] 가 폴백을 그린다:
///
/// * 키를 주입하지 않은 빌드(`KAKAO_JS_KEY` 없음)
/// * 안드로이드·iOS 가 아닌 타깃(데스크톱)
/// * WebView 플러그인이 없는 환경(VM 테스트) — `WebViewPlatform.instance` 가 비었다
Widget? buildKakaoMap({
  required double centerLat,
  required double centerLng,
  required List<KakaoMapMarker> markers,
  required int level,
  required Widget fallback,
  ValueChanged<KakaoMapMarker>? onMarkerTap,
  VoidCallback? onUnavailable,
}) {
  if (!isKakaoMapConfigured) return null;
  if (!kakaoMobileMapSupported(
    platform: defaultTargetPlatform,
    hasWebView: WebViewPlatform.instance != null,
  )) {
    return null;
  }
  return KakaoMobileMap(
    appKey: kakaoJsKey,
    centerLat: centerLat,
    centerLng: centerLng,
    markers: markers,
    level: level,
    fallback: fallback,
    onMarkerTap: onMarkerTap,
    onUnavailable: onUnavailable,
  );
}

/// 이 타깃에서 WebView 지도를 띄울 수 있는가.
@visibleForTesting
bool kakaoMobileMapSupported({
  required TargetPlatform platform,
  required bool hasWebView,
}) {
  if (!hasWebView) return false;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

/// 지도 문서 안에서 머물러도 되는 주소인가. 지도 아래 카카오 로고 등을 눌러
/// 다른 페이지로 넘어가면 지도 자리가 웹 페이지로 바뀐다 — 본 문서와 하위
/// 프레임만 둔다.
@visibleForTesting
bool kakaoMobileMapAllowsNavigation(String url, {required bool isMainFrame}) {
  if (!isMainFrame) return true;
  return url.startsWith(kKakaoMapMobileBaseUrl) || url.startsWith('about:');
}

/// WebView 에 띄운 카카오맵. [kakaoMapHtml] 문서를 한 번 불러오고, 그 뒤 중심·
/// 마커가 바뀌면 문서를 다시 불러오지 않고 스크립트로 고친다 — 목록 시트를
/// 끌 때마다 지도가 새로 뜨면 안 된다.
@visibleForTesting
class KakaoMobileMap extends StatefulWidget {
  const KakaoMobileMap({
    super.key,
    required this.appKey,
    required this.centerLat,
    required this.centerLng,
    required this.markers,
    required this.level,
    required this.fallback,
    this.onMarkerTap,
    this.onUnavailable,
    this.readyTimeout = kKakaoMapSdkTimeout,
  });

  final String appKey;
  final double centerLat;
  final double centerLng;
  final List<KakaoMapMarker> markers;
  final int level;
  final Widget fallback;
  final ValueChanged<KakaoMapMarker>? onMarkerTap;
  final VoidCallback? onUnavailable;

  /// 이 시간 안에 지도 준비 소식이 오지 않으면 폴백으로 떨어진다.
  final Duration readyTimeout;

  @override
  State<KakaoMobileMap> createState() => _KakaoMobileMapState();
}

class _KakaoMobileMapState extends State<KakaoMobileMap> {
  late final WebViewController _controller;
  Timer? _readyTimer;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_load());
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) =>
              kakaoMobileMapAllowsNavigation(
                request.url,
                isMainFrame: request.isMainFrame,
              )
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      await _controller.addJavaScriptChannel(
        kKakaoMapChannel,
        onMessageReceived: (JavaScriptMessage message) =>
            _onMessage(message.message),
      );
      if (!mounted) return;
      _readyTimer = Timer(widget.readyTimeout, _fail);
      await _controller.loadHtmlString(
        kakaoMapHtml(
          appKey: widget.appKey,
          centerLat: widget.centerLat,
          centerLng: widget.centerLng,
          level: widget.level,
          markers: widget.markers,
        ),
        baseUrl: kKakaoMapMobileBaseUrl,
      );
    } on Object {
      _fail();
    }
  }

  void _onMessage(String raw) {
    if (!mounted) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    switch (decoded['type']) {
      case 'ready':
        _readyTimer?.cancel();
        if (_failed) return;
        _ready = true;
        // 문서를 부르는 사이 중심·마커가 바뀌었을 수 있다 — 지금 값으로 맞춘다.
        _syncCenter();
        _syncMarkers();
      case 'error':
        _fail();
      case 'marker':
        final Object? id = decoded['id'];
        if (id is! String) return;
        // 콜백은 누른 순간의 위젯에서 읽는다 — 부모가 콜백을 바꿔도 옛 것을
        // 부르지 않게.
        for (final KakaoMapMarker m in widget.markers) {
          if (m.id == id) {
            widget.onMarkerTap?.call(m);
            return;
          }
        }
    }
  }

  /// 로드 실패(도메인 미등록·키 오류·네트워크 차단·시간 초과)는 폴백으로
  /// 되돌리고 화면에 알린다. 한 번만 알린다.
  void _fail() {
    _readyTimer?.cancel();
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
      _ready = false;
    });
    widget.onUnavailable?.call();
  }

  void _run(String script) {
    if (!_ready || script.isEmpty) return;
    unawaited(_controller.runJavaScript(script).catchError((Object _) {}));
  }

  void _syncCenter() =>
      _run(kakaoMapSetCenterScript(widget.centerLat, widget.centerLng));

  void _syncMarkers() => _run(kakaoMapSetMarkersScript(widget.markers));

  @override
  void didUpdateWidget(KakaoMobileMap old) {
    super.didUpdateWidget(old);
    if (!_ready) return;
    if (old.centerLat != widget.centerLat ||
        old.centerLng != widget.centerLng) {
      _syncCenter();
    }
    if (!_sameMarkers(old.markers, widget.markers)) _syncMarkers();
  }

  static bool _sameMarkers(List<KakaoMapMarker> a, List<KakaoMapMarker> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].lat != b[i].lat ||
          a[i].lng != b[i].lng ||
          a[i].title != b[i].title ||
          a[i].id != b[i].id) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback;
    return WebViewWidget(
      controller: _controller,
      // 지도 위 손짓은 **지도의 것**이다(#1362) — 끌기·두 손가락 확대를 바깥
      // 스크롤이 먼저 가져가지 않게 한다.
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}

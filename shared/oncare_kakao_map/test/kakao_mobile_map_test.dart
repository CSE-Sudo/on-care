/// 모바일 WebView 카카오맵(#3043).
///
/// 플랫폼 WebView 를 가짜 구현으로 바꿔 끼워, 문서를 한 번만 불러오는지·중심과
/// 마커를 스크립트로 고치는지·마커 탭과 실패를 화면에 알리는지 본다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_kakao_map/oncare_kakao_map.dart';
import 'package:oncare_kakao_map/src/kakao_map_platform_mobile.dart';
import 'package:oncare_kakao_map/src/kakao_map_script.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _FakeWebViewPlatform extends WebViewPlatform {
  final List<_FakeController> controllers = <_FakeController>[];

  _FakeController get last => controllers.last;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final _FakeController c = _FakeController(params);
    controllers.add(c);
    return c;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  final List<({String html, String? baseUrl})> loads =
      <({String html, String? baseUrl})>[];
  final List<String> scripts = <String>[];
  final Map<String, JavaScriptChannelParams> channels =
      <String, JavaScriptChannelParams>{};
  JavaScriptMode? mode;
  _FakeNavigationDelegate? delegate;
  bool failLoad = false;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    mode = javaScriptMode;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler as _FakeNavigationDelegate;
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    channels[javaScriptChannelParams.name] = javaScriptChannelParams;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    if (failLoad) throw StateError('load failed');
    loads.add((html: html, baseUrl: baseUrl));
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }

  /// 지도 문서가 채널로 보낸 것처럼 꾸민다.
  void send(String message) => channels[kKakaoMapChannel]!.onMessageReceived(
    JavaScriptMessage(message: message),
  );
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onRequest;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    onRequest = onNavigationRequest;
  }
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey<String>('fake-webview'));
}

const Key _fallback = ValueKey<String>('fallback');
const Key _webView = ValueKey<String>('fake-webview');

const List<KakaoMapMarker> _markers = <KakaoMapMarker>[
  KakaoMapMarker(lat: 37.5, lng: 126.9, title: '온케어 신촌', id: 'g1'),
  KakaoMapMarker(lat: 37.51, lng: 126.91, title: '바른 짐', id: 'g2'),
];

void main() {
  late _FakeWebViewPlatform platform;

  setUp(() {
    platform = _FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  Future<void> pumpMap(
    WidgetTester tester, {
    double lat = 37.5559,
    double lng = 126.9368,
    List<KakaoMapMarker> markers = _markers,
    ValueChanged<KakaoMapMarker>? onMarkerTap,
    VoidCallback? onUnavailable,
    Duration readyTimeout = const Duration(seconds: 10),
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: KakaoMobileMap(
          appKey: 'test-key',
          centerLat: lat,
          centerLng: lng,
          markers: markers,
          level: 5,
          fallback: const SizedBox(key: _fallback),
          onMarkerTap: onMarkerTap,
          onUnavailable: onUnavailable,
          readyTimeout: readyTimeout,
        ),
      ),
    );
    // 설정·문서 불러오기는 비동기로 이어진다.
    await tester.pump();
  }

  /// 남은 시간 제한 타이머가 테스트 끝에 걸리지 않게 지도를 내린다.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('문서를 http://localhost 출처로 한 번 불러온다', (WidgetTester tester) async {
    await pumpMap(tester);

    expect(find.byKey(_webView), findsOneWidget);
    final _FakeController c = platform.last;
    expect(c.mode, JavaScriptMode.unrestricted);
    expect(c.channels.keys, <String>[kKakaoMapChannel]);
    expect(c.loads, hasLength(1));
    expect(c.loads.single.baseUrl, 'http://localhost');
    expect(
      c.loads.single.html,
      contains(
        'https://dapi.kakao.com/v2/maps/sdk.js?appkey=test-key&autoload=false',
      ),
    );
    expect(c.loads.single.html, contains('"lat":37.5559'));
    expect(c.loads.single.html, contains('온케어 신촌'));
    await unmount(tester);
  });

  testWidgets('준비되면 지금 중심·마커로 맞춘다', (WidgetTester tester) async {
    await pumpMap(tester);
    final _FakeController c = platform.last;
    expect(c.scripts, isEmpty, reason: '준비 전에는 스크립트를 보내지 않는다');

    c.send('{"type":"ready"}');
    await tester.pump();

    expect(c.scripts, <String>[
      kakaoMapSetCenterScript(37.5559, 126.9368),
      kakaoMapSetMarkersScript(_markers),
    ]);
    await unmount(tester);
  });

  testWidgets('중심이 바뀌면 다시 불러오지 않고 스크립트로 옮긴다', (WidgetTester tester) async {
    await pumpMap(tester);
    final _FakeController c = platform.last;
    c.send('{"type":"ready"}');
    await tester.pump();
    c.scripts.clear();

    await pumpMap(tester, lat: 35.1, lng: 129.1);

    expect(platform.controllers, hasLength(1), reason: 'WebView 를 새로 만들지 않는다');
    expect(c.loads, hasLength(1), reason: '문서를 다시 불러오지 않는다');
    expect(c.scripts, <String>[kakaoMapSetCenterScript(35.1, 129.1)]);
    await unmount(tester);
  });

  testWidgets('마커가 바뀌면 마커만 다시 찍는다', (WidgetTester tester) async {
    await pumpMap(tester);
    final _FakeController c = platform.last;
    c.send('{"type":"ready"}');
    await tester.pump();
    c.scripts.clear();

    const List<KakaoMapMarker> next = <KakaoMapMarker>[
      KakaoMapMarker(lat: 37.52, lng: 126.92, title: '새 헬스장', id: 'g3'),
    ];
    await pumpMap(tester, markers: next);

    expect(c.loads, hasLength(1));
    expect(c.scripts, <String>[kakaoMapSetMarkersScript(next)]);
    await unmount(tester);
  });

  testWidgets('값이 같으면 아무것도 보내지 않는다', (WidgetTester tester) async {
    await pumpMap(tester);
    final _FakeController c = platform.last;
    c.send('{"type":"ready"}');
    await tester.pump();
    c.scripts.clear();

    await pumpMap(
      tester,
      markers: <KakaoMapMarker>[for (final KakaoMapMarker m in _markers) m],
    );

    expect(c.scripts, isEmpty);
    await unmount(tester);
  });

  testWidgets('준비 전에 바뀐 값은 준비 뒤 한 번에 맞춘다', (WidgetTester tester) async {
    await pumpMap(tester);
    final _FakeController c = platform.last;
    await pumpMap(tester, lat: 35.1, lng: 129.1);
    expect(c.scripts, isEmpty);

    c.send('{"type":"ready"}');
    await tester.pump();

    expect(c.scripts.first, kakaoMapSetCenterScript(35.1, 129.1));
    await unmount(tester);
  });

  group('마커 탭', () {
    testWidgets('누른 핀을 onMarkerTap 으로 알린다', (WidgetTester tester) async {
      final List<KakaoMapMarker> taps = <KakaoMapMarker>[];
      await pumpMap(tester, onMarkerTap: taps.add);
      final _FakeController c = platform.last;
      c.send('{"type":"ready"}');
      await tester.pump();

      c.send('{"type":"marker","id":"g2"}');
      await tester.pump();

      expect(taps.map((KakaoMapMarker m) => m.title), <String>['바른 짐']);
      await unmount(tester);
    });

    testWidgets('모르는 id·깨진 소식은 무시한다', (WidgetTester tester) async {
      final List<KakaoMapMarker> taps = <KakaoMapMarker>[];
      await pumpMap(tester, onMarkerTap: taps.add);
      final _FakeController c = platform.last;

      c.send('{"type":"marker","id":"nope"}');
      c.send('{"type":"marker","id":3}');
      c.send('not json');
      c.send('[1,2]');
      await tester.pump();

      expect(taps, isEmpty);
      expect(find.byKey(_webView), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('지도를 만든 뒤 바뀐 콜백을 부른다', (WidgetTester tester) async {
      final List<String> calls = <String>[];
      await pumpMap(tester, onMarkerTap: (_) => calls.add('old'));
      final _FakeController c = platform.last;
      await pumpMap(tester, onMarkerTap: (_) => calls.add('new'));

      c.send('{"type":"marker","id":"g1"}');
      await tester.pump();

      expect(calls, <String>['new']);
      await unmount(tester);
    });
  });

  group('지도를 띄우지 못하면', () {
    testWidgets('SDK 실패 소식이면 폴백으로 떨어지고 한 번 알린다', (WidgetTester tester) async {
      int unavailable = 0;
      await pumpMap(tester, onUnavailable: () => unavailable++);
      final _FakeController c = platform.last;

      c.send('{"type":"error","reason":"network"}');
      await tester.pump();
      c.send('{"type":"error","reason":"network"}');
      await tester.pump();

      expect(find.byKey(_fallback), findsOneWidget);
      expect(find.byKey(_webView), findsNothing);
      expect(unavailable, 1);
    });

    testWidgets('실패한 뒤 늦게 온 준비 소식은 무시한다', (WidgetTester tester) async {
      await pumpMap(tester);
      final _FakeController c = platform.last;
      c.send('{"type":"error"}');
      await tester.pump();

      c.send('{"type":"ready"}');
      await tester.pump();

      expect(find.byKey(_fallback), findsOneWidget);
      expect(c.scripts, isEmpty);
    });

    testWidgets('시간 안에 준비되지 않으면 폴백으로 떨어진다', (WidgetTester tester) async {
      int unavailable = 0;
      await pumpMap(
        tester,
        onUnavailable: () => unavailable++,
        readyTimeout: const Duration(seconds: 2),
      );
      expect(find.byKey(_webView), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));

      expect(find.byKey(_fallback), findsOneWidget);
      expect(unavailable, 1);
    });

    testWidgets('준비되면 시간 제한이 풀린다', (WidgetTester tester) async {
      int unavailable = 0;
      await pumpMap(
        tester,
        onUnavailable: () => unavailable++,
        readyTimeout: const Duration(seconds: 2),
      );
      platform.last.send('{"type":"ready"}');
      await tester.pump(const Duration(seconds: 3));

      expect(find.byKey(_webView), findsOneWidget);
      expect(unavailable, 0);
      await unmount(tester);
    });

    testWidgets('문서를 불러오다 실패해도 폴백으로 떨어진다', (WidgetTester tester) async {
      int unavailable = 0;
      WebViewPlatform.instance = _FailingPlatform();
      await pumpMap(tester, onUnavailable: () => unavailable++);
      await tester.pump();

      expect(find.byKey(_fallback), findsOneWidget);
      expect(unavailable, 1);
    });
  });

  testWidgets('지도 밖 페이지로 넘어가지 않는다', (WidgetTester tester) async {
    await pumpMap(tester);
    final NavigationRequestCallback onRequest =
        platform.last.delegate!.onRequest!;

    expect(
      await onRequest(
        const NavigationRequest(url: 'http://localhost/', isMainFrame: true),
      ),
      NavigationDecision.navigate,
    );
    expect(
      await onRequest(
        const NavigationRequest(
          url: 'https://map.kakao.com/link/map/1',
          isMainFrame: true,
        ),
      ),
      NavigationDecision.prevent,
    );
    await unmount(tester);
  });

  testWidgets('지운 뒤 늦게 온 소식에 넘어지지 않는다', (WidgetTester tester) async {
    int unavailable = 0;
    await pumpMap(tester, onUnavailable: () => unavailable++);
    final _FakeController c = platform.last;
    await unmount(tester);

    c.send('{"type":"error"}');
    c.send('{"type":"marker","id":"g1"}');
    await tester.pump();

    expect(unavailable, 0);
  });

  testWidgets('키가 없는 빌드는 KakaoMapView 가 폴백을 그린다', (WidgetTester tester) async {
    // 테스트는 --dart-define 없이 돈다. WebView 가 있어도 지도를 시도하지 않는다.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: KakaoMapView(
          centerLat: 37.5,
          centerLng: 126.9,
          markers: _markers,
          fallback: SizedBox(key: _fallback),
        ),
      ),
    );
    expect(find.byKey(_fallback), findsOneWidget);
    expect(platform.controllers, isEmpty);
  });

  test('준비 시간 기본값은 웹 SDK 제한 시간과 같다', () {
    const KakaoMobileMap map = KakaoMobileMap(
      appKey: 'k',
      centerLat: 0,
      centerLng: 0,
      markers: <KakaoMapMarker>[],
      level: 5,
      fallback: SizedBox(),
    );
    expect(map.readyTimeout, kKakaoMapSdkTimeout);
  });
}

/// 문서 불러오기가 실패하는 WebView.
class _FailingPlatform extends _FakeWebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final _FakeController c = _FakeController(params)..failLoad = true;
    controllers.add(c);
    return c;
  }
}

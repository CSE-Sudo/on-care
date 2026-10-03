import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:oncare_kakao_map/src/kakao_map_config.dart';
import 'package:web/web.dart' as web;

/// 카카오맵 JS SDK 를 `HtmlElementView` 로 얹는다.
///
/// 카카오는 Flutter 지도 SDK 가 없어 웹에서는 JS SDK 가 유일한 경로다. 서드파티
/// 플러그인(`kakao_map_plugin`)은 WebView 래퍼라 web 을 지원하지 않으므로 쓰지 않고,
/// 플랫폼 뷰에 직접 붙인다.
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
  return _KakaoMapView(
    centerLat: centerLat,
    centerLng: centerLng,
    markers: markers,
    level: level,
    fallback: fallback,
    onMarkerTap: onMarkerTap,
    onUnavailable: onUnavailable,
  );
}

const String _sdkUrl = 'https://dapi.kakao.com/v2/maps/sdk.js';

/// SDK 로드 제한 시간. 스크립트가 load/error 어느 이벤트도 내지 않는 경우
/// (프록시 지연·네트워크 블랙홀 등) 지도가 영영 빈 채로 남지 않게 한다.
const Duration _sdkTimeout = Duration(seconds: 10);

Future<void>? _sdkReady;

/// SDK 를 한 번만 내려받고, `autoload=false` + `kakao.maps.load` 로 초기화를 기다린다.
/// (autoload 를 켜면 스크립트 onload 시점과 실제 준비 시점이 어긋난다.)
Future<void> _ensureSdkLoaded() {
  final Future<void>? existing = _sdkReady;
  if (existing != null) return existing;

  final Completer<void> completer = Completer<void>();
  // SRI(integrity)는 걸 수 없다(#3089) — SDK 내용이 예고 없이 바뀌고 t1.daumcdn.net
  // 의 스크립트를 다시 불러온다. 남은 방어는 CSP script-src 와 카카오 콘솔의 JS 키
  // 사용 도메인 제한이다.
  final web.HTMLScriptElement script =
      web.document.createElement('script') as web.HTMLScriptElement
        ..src = '$_sdkUrl?appkey=$kakaoJsKey&autoload=false'
        ..async = true;

  script.addEventListener(
    'load',
    (JSAny _) {
      final JSObject? kakao = _global('kakao');
      final JSObject? maps = kakao == null ? null : _prop(kakao, 'maps');
      if (maps == null) {
        completer.completeError(
          StateError('카카오맵 SDK 로드 후 kakao.maps 를 찾지 못했습니다.'),
        );
        return;
      }
      maps.callMethod('load'.toJS, (() => completer.complete()).toJS);
    }.toJS,
  );
  script.addEventListener(
    'error',
    (JSAny _) {
      // 도메인 미등록·키 오류·네트워크 차단 모두 여기로 온다.
      completer.completeError(
        StateError('카카오맵 SDK 를 불러오지 못했습니다 (JS 키/도메인 등록 확인).'),
      );
    }.toJS,
  );

  web.document.head!.append(script);
  return _sdkReady = completer.future.timeout(
    _sdkTimeout,
    onTimeout: () => throw TimeoutException(
      '카카오맵 SDK 로드가 ${_sdkTimeout.inSeconds}초 안에 끝나지 않았습니다.',
      _sdkTimeout,
    ),
  );
}

JSObject? _global(String name) {
  if (!globalContext.hasProperty(name.toJS).toDart) return null;
  return globalContext[name] as JSObject?;
}

JSObject? _prop(JSObject target, String name) {
  if (!target.hasProperty(name.toJS).toDart) return null;
  return target[name] as JSObject?;
}

class _KakaoMapView extends StatefulWidget {
  const _KakaoMapView({
    required this.centerLat,
    required this.centerLng,
    required this.markers,
    required this.level,
    required this.fallback,
    this.onMarkerTap,
    this.onUnavailable,
  });

  final double centerLat;
  final double centerLng;
  final List<KakaoMapMarker> markers;
  final int level;
  final Widget fallback;
  final ValueChanged<KakaoMapMarker>? onMarkerTap;
  final VoidCallback? onUnavailable;

  @override
  State<_KakaoMapView> createState() => _KakaoMapViewState();
}

class _KakaoMapViewState extends State<_KakaoMapView> {
  static int _seq = 0;

  late final String _viewType = 'kakao-map-${_seq++}';
  late final web.HTMLDivElement _container;
  Object? _error;
  JSObject? _map;
  final List<JSObject> _markers = <JSObject>[];
  web.ResizeObserver? _resize;
  Timer? _relayoutDebounce;

  @override
  void initState() {
    super.initState();
    _container = web.document.createElement('div') as web.HTMLDivElement;
    _container.style
      ..width = '100%'
      ..height = '100%'
      // 폰에서 지도 위 손짓은 **지도의 것**이다 (#1362). 그대로 두면 브라우저가
      // 한 손가락 끌기를 페이지 스크롤로, 두 손가락을 페이지 확대로 먼저
      // 가져가 지도가 움직이지 않는다.
      ..touchAction = 'none';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _container,
    );
    unawaited(_initialise());
  }

  @override
  void dispose() {
    _relayoutDebounce?.cancel();
    _resize?.disconnect();
    super.dispose();
  }

  Future<void> _initialise() async {
    try {
      await _ensureSdkLoaded();
      if (!mounted) return;
      _createMap();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      widget.onUnavailable?.call();
    }
  }

  JSObject get _maps => _prop(_global('kakao')!, 'maps')!;

  JSObject _latLng(double lat, double lng) => (_maps['LatLng'] as JSFunction)
      .callAsConstructor<JSObject>(lat.toJS, lng.toJS);

  void _createMap() {
    final JSObject options = JSObject()
      ..setProperty('center'.toJS, _latLng(widget.centerLat, widget.centerLng))
      ..setProperty('level'.toJS, widget.level.toJS);

    final JSObject map = (_maps['Map'] as JSFunction)
        .callAsConstructor<JSObject>(_container, options);
    _map = map;
    _addZoomControl(map);
    _syncMarkers();

    // 플랫폼 뷰가 배치된 뒤 크기가 확정되므로 한 프레임 뒤 다시 계산시킨다.
    // 이걸 빼면 지도가 0×0 으로 잡혀 회색으로만 보인다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _relayout());
    // 한 프레임 뒤 한 번으로는 모자란다. 시트가 올라오는 동안, 창을 줄였다
    // 늘릴 때, 목록이 채워지며 폭이 바뀔 때 컨테이너 크기는 계속 달라지는데
    // 카카오는 생성 시점 크기로 타일을 깔아 둔다 — 그래서 지도가 한쪽(대개
    // 왼쪽 절반)만 그려지고 나머지는 빈 채로 남았다(#1072). 컨테이너 크기가
    // 바뀔 때마다 relayout 을 걸어 항상 부모 폭을 채우게 한다.
    final web.ResizeObserver observer = web.ResizeObserver(
      ((JSArray<JSAny?> _, web.ResizeObserver _) => _scheduleRelayout()).toJS,
    );
    observer.observe(_container);
    _resize = observer;
  }

  /// 확대·축소 버튼. 폰에서 두 손가락이 마음대로 되지 않아도 배율을 바꿀 수
  /// 있어야 한다 (#1362). SDK 버전에 따라 없을 수 있으므로 있을 때만 붙인다 —
  /// 여기서 예외가 나면 지도 전체가 폴백 그래픽으로 떨어진다.
  void _addZoomControl(JSObject map) {
    final JSObject? position = _prop(_maps, 'ControlPosition');
    if (!_maps.hasProperty('ZoomControl'.toJS).toDart || position == null) {
      return;
    }
    final JSObject control = (_maps['ZoomControl'] as JSFunction)
        .callAsConstructor<JSObject>();
    map.callMethodVarArgs('addControl'.toJS, <JSAny?>[
      control,
      position['RIGHT'],
    ]);
  }

  /// 컨테이너 크기가 바뀐 뒤 지도에 다시 계산시키고 중심을 되돌린다.
  /// relayout 만 하면 카카오가 새 크기의 좌상단을 기준으로 잡아 중심이 밀린다.
  ///
  /// **한 박자 미룬다** (#1362). 시트를 끄는 동안 지도 높이가 매 프레임 바뀌는데,
  /// 그때마다 타일을 다시 까는 것은 폰에서 눈에 띄게 무겁다. 손이 멈춘 뒤 한 번만
  /// 계산하면 결과는 같다.
  void _scheduleRelayout() {
    _relayoutDebounce?.cancel();
    _relayoutDebounce = Timer(const Duration(milliseconds: 120), _relayout);
  }

  void _relayout() {
    final JSObject? map = _map;
    if (map == null || !mounted) return;
    // 시트가 화면을 다 덮으면 지도 자리가 0 이 된다 — 그 크기로 타일을 다시
    // 깔게 두지 않는다. 자리가 생기면 ResizeObserver 가 다시 부른다.
    if (_container.clientWidth == 0 || _container.clientHeight == 0) return;
    map.callMethod('relayout'.toJS);
    map.callMethod(
      'setCenter'.toJS,
      _latLng(widget.centerLat, widget.centerLng),
    );
  }

  /// 기존 마커를 지우고 [widget.markers] 로 다시 찍는다.
  ///
  /// 목록이 비동기라서 지도는 대개 마커 0개로 먼저 만들어진다. 갱신 때 이걸 다시
  /// 부르지 않으면 핀이 영영 표시되지 않는다.
  void _syncMarkers() {
    final JSObject? map = _map;
    if (map == null) return;

    for (final JSObject old in _markers) {
      // 카카오는 setMap(null) 로만 마커를 뗀다. 인자 없이 부르면 setMap(undefined)
      // 가 되어 마커가 남고, 목록이 바뀔 때마다 핀이 쌓인다. callMethod 는 null 을
      // 넘길 수 없어 callMethodVarArgs 를 쓴다.
      old.callMethodVarArgs('setMap'.toJS, <JSAny?>[null]);
    }
    _markers.clear();

    final JSFunction markerCtor = _maps['Marker'] as JSFunction;
    for (final KakaoMapMarker m in widget.markers) {
      final JSObject marker = markerCtor.callAsConstructor<JSObject>(
        JSObject()
          ..setProperty('position'.toJS, _latLng(m.lat, m.lng))
          ..setProperty('title'.toJS, m.title.toJS),
      );
      marker.callMethod('setMap'.toJS, map);
      if (m.id != null) _listenTap(marker, m);
      _markers.add(marker);
    }
  }

  /// 핀 누르기를 알린다. 콜백은 누른 순간의 위젯에서 읽는다 — 지도를 만든 뒤
  /// 부모가 콜백을 바꿔도 옛 것을 부르지 않게.
  void _listenTap(JSObject marker, KakaoMapMarker m) {
    final JSObject? event = _prop(_maps, 'event');
    if (event == null) return;
    event.callMethodVarArgs('addListener'.toJS, <JSAny?>[
      marker,
      'click'.toJS,
      (() {
        if (mounted) widget.onMarkerTap?.call(m);
      }).toJS,
    ]);
  }

  @override
  void didUpdateWidget(_KakaoMapView old) {
    super.didUpdateWidget(old);
    if (_map == null) return;

    if (!_sameMarkers(old.markers, widget.markers)) _syncMarkers();

    if (old.centerLat != widget.centerLat ||
        old.centerLng != widget.centerLng) {
      _map!.callMethod(
        'setCenter'.toJS,
        _latLng(widget.centerLat, widget.centerLng),
      );
    }
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
    // 로드 실패(도메인 미등록·키 오류·네트워크 차단)는 폴백 그래픽으로 되돌린다.
    if (_error != null) return widget.fallback;
    return HtmlElementView(viewType: _viewType);
  }
}

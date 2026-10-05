import 'dart:async';
import 'dart:js_interop';

import 'package:oncare/core/release/release_update.dart';
import 'package:web/web.dart' as web;

/// 웹: 이 앱의 `<base href>version.txt` 를 캐시 없이 읽는다(#3023).
ReleaseProbe? createReleaseProbe() => const _BrowserReleaseProbe();

const web.EventStreamProvider<web.Event> _visibilityChange =
    web.EventStreamProvider<web.Event>('visibilitychange');

/// 새로고침 전에 서버에서 새로 받아 둘 진입 파일(#3204) — `<base href>` 기준.
///
/// 이름에 해시가 없어 배포가 바뀌어도 URL 이 같은 파일들이다. GitHub Pages 는 모든
/// 파일에 `max-age=600` 을 붙여, 보통의 새로고침은 이 파일들을 HTTP 캐시에서 그대로
/// 다시 쓸 수 있다. 문서(`index.html`)는 새로고침이 늘 재검증하므로 넣지 않는다.
/// 없는 파일은 404 로 끝나고 무시된다.
const List<String> kReleaseEntryFiles = <String>[
  'flutter_bootstrap.js',
  'main.dart.js',
  'version.json',
  'drift_worker.js',
  'sqlite3.wasm',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
];

/// 진입 파일 미리 받기를 기다리는 최대 시간. 넘으면 그대로 새로고침한다.
const Duration kReleaseRefreshTimeout = Duration(seconds: 15);

/// 새로고침으로 받으러 간 배포 SHA 를 담는 sessionStorage 키.
const String kReloadedShaKey = 'oncare.release.reloadedSha';

class _BrowserReleaseProbe implements ReleaseProbe {
  const _BrowserReleaseProbe();

  /// 앱 경로(`/frontend/diet` 등)가 아니라 `<base href>` 기준으로 찾는다 —
  /// 두 앱은 각자 폴더(`/frontend/`·`/trainer/`)에 자기 version.txt 를 둔다.
  Uri get _base => Uri.parse(web.document.baseURI);

  @override
  Future<String?> fetchLatest() async {
    final web.Response response = await web.window
        .fetch(
          _base.resolve('version.txt').toString().toJS,
          web.RequestInit(cache: 'no-store', credentials: 'omit'),
        )
        .toDart;
    if (!response.ok) return null;
    return (await response.text().toDart).toDart;
  }

  /// 탭이 다시 보일 때만 — 숨겨질 때 나는 같은 이벤트는 거른다. 리스너는 듣는
  /// 쪽이 있을 때만 브라우저에 걸린다.
  @override
  Stream<void> get onVisible => _visibilityChange
      .forTarget(web.document)
      .where((_) => web.document.visibilityState == 'visible');

  /// 진입 파일을 `cache: 'reload'` 로 받아 HTTP 캐시를 새 파일로 바꾼 뒤 다시 읽는다.
  ///
  /// `reload` 요청은 캐시를 건너뛰고 서버에서 받은 응답을 캐시에 다시 넣는다. 다시
  /// 실릴 때 `<script src>` 가 같은 URL 을 찾으면 방금 받은 새 파일이 나온다. 쿼리
  /// 문자열(`?v=`)로 문서만 우회하는 방식은 `flutter_bootstrap.js`·`main.dart.js` 가
  /// 그대로라 쓰지 않는다.
  @override
  Future<void> reload() async {
    try {
      await Future.wait<void>(
        kReleaseEntryFiles.map(_refresh),
      ).timeout(kReleaseRefreshTimeout);
    } on Object {
      // 시간 초과 등 — 받은 만큼으로 새로고침한다.
    }
    web.window.location.reload();
  }

  /// 파일 하나를 서버에서 새로 받는다. 본문을 끝까지 읽어야 캐시에 온전히 남는다.
  Future<void> _refresh(String path) async {
    try {
      final web.Response response = await web.window
          .fetch(
            _base.resolve(path).toString().toJS,
            web.RequestInit(cache: 'reload', credentials: 'same-origin'),
          )
          .toDart;
      await response.arrayBuffer().toDart;
    } on Object {
      // 없는 파일·오프라인은 넘긴다 — 새로고침은 그대로 한다.
    }
  }

  @override
  String? readReloadedSha() =>
      web.window.sessionStorage.getItem(kReloadedShaKey);

  @override
  void writeReloadedSha(String? sha) {
    if (sha == null) {
      web.window.sessionStorage.removeItem(kReloadedShaKey);
    } else {
      web.window.sessionStorage.setItem(kReloadedShaKey, sha);
    }
  }
}

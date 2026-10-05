import 'dart:js_interop';

import 'package:oncare_trainer/core/release/release_update.dart';
import 'package:web/web.dart' as web;

/// 웹: 이 앱의 `<base href>version.txt` 를 캐시 없이 읽는다(#3023).
ReleaseProbe? createReleaseProbe() => const _BrowserReleaseProbe();

const web.EventStreamProvider<web.Event> _visibilityChange =
    web.EventStreamProvider<web.Event>('visibilitychange');

class _BrowserReleaseProbe implements ReleaseProbe {
  const _BrowserReleaseProbe();

  /// 앱 경로(`/trainer/clients/12` 등)가 아니라 `<base href>` 기준으로 찾는다 —
  /// 두 앱은 각자 폴더(`/member/`·`/trainer/`)에 자기 version.txt 를 둔다.
  Uri get _versionUrl => Uri.parse(web.document.baseURI).resolve('version.txt');

  @override
  Future<String?> fetchLatest() async {
    final web.Response response = await web.window
        .fetch(
          _versionUrl.toString().toJS,
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

  @override
  void reload() => web.window.location.reload();
}

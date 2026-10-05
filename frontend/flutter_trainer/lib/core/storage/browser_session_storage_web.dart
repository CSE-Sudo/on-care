import 'dart:js_interop';
import 'dart:math';

import 'package:oncare_core/storage/token_keys.dart';
import 'package:oncare_trainer/core/storage/browser_tab_claim.dart';
import 'package:oncare_trainer/core/storage/token_session_storage.dart';
import 'package:web/web.dart' as web;

/// 웹: 브라우저 sessionStorage 에 둔다(#2828). 탭을 닫으면 사라지고 다른 탭과
/// 나누지 않는다. sessionStorage 에 접근할 수 없으면 메모리로 물러난다.
///
/// 복제한 탭은 sessionStorage 를 복사해 받으므로, 토큰을 읽기 전에 복제인지
/// 보고 받은 토큰을 버린다(#3248, [BrowserTabClaim]). 판정은 페이지마다 한
/// 번이다 — 다시 부르면 같은 저장소를 돌려준다. 두 번 판정하면 이 탭이 남긴
/// 표시를 보고 자기 자신을 복제로 여긴다.
TokenSessionStorage? createBrowserSessionStorage() =>
    _pageStorage ??= _createBrowserSessionStorage();

TokenSessionStorage? _pageStorage;

TokenSessionStorage _createBrowserSessionStorage() {
  final _BrowserSessionStorage session;
  try {
    final web.Storage storage = web.window.sessionStorage;
    // 사파리 사생활 보호 모드 등은 읽기는 되고 쓰기에서 예외를 낸다 — 미리 확인한다.
    const String probe = '__oncare_session_probe__';
    storage.setItem(probe, '1');
    storage.removeItem(probe);
    session = _BrowserSessionStorage(storage);
  } on Object {
    return InMemoryTokenSessionStorage();
  }
  _claimTab(session);
  return session;
}

void _claimTab(TokenSessionStorage session) {
  final TabMarkerStore markers;
  try {
    markers = _LocalTabMarkers(web.window.localStorage);
  } on Object {
    return; // 공유 저장소가 없으면 복제를 알아챌 수 없다 — 예전처럼 둔다.
  }
  final String id = BrowserTabClaim.claim(
    tab: session,
    markers: markers,
    tokenKeys: <String>[
      TokenKeyspace.trainer.accessKey,
      TokenKeyspace.trainer.refreshKey,
    ],
    newTabId: _newTabId,
    now: DateTime.now(),
  );
  // 떠날 때 표시를 지우고, 뒤로 가기 캐시에서 돌아오면 다시 남긴다.
  web.window.addEventListener(
    'pagehide',
    ((web.Event _) {
      try {
        BrowserTabClaim.release(markers, id);
      } on Object {
        // 지우지 못한 표시는 다음 복구에서 복제로 보일 뿐이다.
      }
    }).toJS,
  );
  web.window.addEventListener(
    'pageshow',
    ((web.PageTransitionEvent event) {
      if (!event.persisted) return;
      try {
        BrowserTabClaim.mark(markers, id, DateTime.now());
      } on Object {
        // 위와 같다.
      }
    }).toJS,
  );
}

String _newTabId() {
  final Random random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
}

class _BrowserSessionStorage implements TokenSessionStorage {
  _BrowserSessionStorage(this._storage);

  final web.Storage _storage;

  @override
  String? read(String key) => _storage.getItem(key);

  @override
  void write(String key, String value) => _storage.setItem(key, value);

  @override
  void remove(String key) => _storage.removeItem(key);
}

class _LocalTabMarkers implements TabMarkerStore {
  _LocalTabMarkers(this._storage);

  final web.Storage _storage;

  @override
  String? read(String key) => _storage.getItem(key);

  @override
  void write(String key, String value) => _storage.setItem(key, value);

  @override
  void remove(String key) => _storage.removeItem(key);

  @override
  Iterable<String> get keys => <String>[
    for (int i = 0; i < _storage.length; i++) ?_storage.key(i),
  ];
}

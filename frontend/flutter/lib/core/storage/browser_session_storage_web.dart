import 'package:oncare/core/storage/token_session_storage.dart';
import 'package:web/web.dart' as web;

/// 웹: 브라우저 sessionStorage 에 둔다(#2828). 탭을 닫으면 사라지고 다른 탭과
/// 나누지 않는다. sessionStorage 에 접근할 수 없으면 메모리로 물러난다.
TokenSessionStorage? createBrowserSessionStorage() {
  try {
    final web.Storage storage = web.window.sessionStorage;
    // 사파리 사생활 보호 모드 등은 읽기는 되고 쓰기에서 예외를 낸다 — 미리 확인한다.
    const String probe = '__oncare_session_probe__';
    storage.setItem(probe, '1');
    storage.removeItem(probe);
    return _BrowserSessionStorage(storage);
  } on Object {
    return InMemoryTokenSessionStorage();
  }
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

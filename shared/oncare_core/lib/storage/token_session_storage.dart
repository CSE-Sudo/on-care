/// 탭(세션) 단위로만 사는 토큰 저장소(#2828). 두 앱이 함께 쓴다(#3271).
///
/// 웹의 `flutter_secure_storage` 는 값을 브라우저 localStorage 에 두고, 그 값을 푸는
/// 키도 같은 localStorage 에 둔다. 같은 출처의 스크립트면 누구든 그대로 읽을 수 있고
/// 브라우저를 닫아도 남는다. 웹에서는 토큰을 이 저장소(sessionStorage)에만 두어,
/// 탭을 닫으면 사라지게 한다 — 주입된 스크립트가 있더라도 훔칠 수 있는 기간이 그
/// 탭이 열려 있는 동안으로 줄어든다. 모바일은 이 저장소를 쓰지 않는다.
library;

abstract interface class TokenSessionStorage {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

/// 메모리에만 두는 구현. 브라우저 sessionStorage 를 쓸 수 없을 때(사생활 보호
/// 모드에서 막힘 등)와 테스트에서 쓴다. 새로고침하면 다시 로그인해야 한다.
class InMemoryTokenSessionStorage implements TokenSessionStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;

  @override
  void remove(String key) => _values.remove(key);
}

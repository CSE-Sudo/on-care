/// 두 앱의 토큰 저장 키 이름과 옛 키 이전 규칙(#3054).
///
/// 회원 앱 웹 빌드와 트레이너 웹은 한 도메인 아래 경로만 다르게 배포된다
/// (`/member/`, `/trainer/`). 브라우저 저장소는 경로가 아니라 **출처** 단위로
/// 나뉘어 두 앱이 같은 `sessionStorage` 를 본다. 예전에는 두 앱 모두 토큰을
/// `access_token`·`refresh_token` 으로 저장해, 한 탭에서 두 앱을 오가면 서로의
/// 토큰을 덮어쓰고 지웠다. 이제 키에 앱 이름공간을 붙인다. 모바일(Keychain·
/// Keystore)은 앱마다 저장소가 따로라 충돌이 없지만 코드 한 줄기로 두려고 같은
/// 이름을 쓴다.
library;

/// 토큰 키의 앱 이름공간.
enum TokenKeyspace {
  /// 회원 앱(`frontend/flutter`).
  member('oncare.member'),

  /// 트레이너 웹(`frontend/flutter_trainer`).
  trainer('oncare.trainer');

  const TokenKeyspace(this.prefix);

  /// 키 앞에 붙는 이름공간.
  final String prefix;

  /// 접근 토큰 키.
  String get accessKey => '$prefix.$legacyAccessTokenKey';

  /// 갱신 토큰 키.
  String get refreshKey => '$prefix.$legacyRefreshTokenKey';
}

/// 이름공간이 없던 옛 접근 토큰 키. 어느 앱이 쓴 값인지 알 수 없다.
const String legacyAccessTokenKey = 'access_token';

/// 이름공간이 없던 옛 갱신 토큰 키.
const String legacyRefreshTokenKey = 'refresh_token';

/// 토큰 키를 읽고 쓰는 저장소. 두 앱의 보안 저장소(비동기)와 탭 단위
/// 저장소(동기)를 같은 규칙으로 옮기려고 함수 셋만 받는다.
class TokenKeyValueAccess {
  const TokenKeyValueAccess({
    required this.read,
    required this.write,
    required this.delete,
  });

  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final Future<void> Function(String key) delete;
}

/// 옛 키의 토큰을 [space] 의 키로 한 번 옮긴다. 옮겼으면 `true`.
///
///  * 새 접근 토큰 키에 값이 있으면 **아무것도 건드리지 않는다** — 이미 옮겼거나
///    새 빌드로 로그인한 것이다. 옛 키는 다른 앱의 것일 수 있다.
///  * 옛 접근 토큰이 없으면 옮길 것이 없다. 짝 없이 남은 옛 갱신 토큰만 지운다.
///  * 옮긴 뒤 옛 키를 지운다. 같은 값을 다른 앱이 다시 옮겨 가지 않게 한다.
///
/// 웹에서는 옛 키가 어느 앱 것인지 모르므로, 옮긴 토큰은 세션 복원의 역할
/// 확인을 거쳐야 세션이 된다(두 앱 세션 컨트롤러).
Future<bool> migrateLegacyTokenKeys(
  TokenKeyValueAccess store,
  TokenKeyspace space,
) async {
  final String? current = await store.read(space.accessKey);
  if (current != null && current.isNotEmpty) return false;

  final String? access = await store.read(legacyAccessTokenKey);
  final String? refresh = await store.read(legacyRefreshTokenKey);
  if (access == null || access.isEmpty) {
    if (refresh != null) await store.delete(legacyRefreshTokenKey);
    return false;
  }
  await store.write(space.accessKey, access);
  if (refresh != null && refresh.isNotEmpty) {
    await store.write(space.refreshKey, refresh);
  }
  await store.delete(legacyAccessTokenKey);
  await store.delete(legacyRefreshTokenKey);
  return true;
}

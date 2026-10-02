import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:oncare/core/storage/token_session_storage.dart';

/// `FlutterSecureStorage` is platform-backed (Keychain / Keystore /
/// localStorage on web — 그래서 웹 토큰은 [SecureTokenStore] 가
/// sessionStorage 에 둔다, #2828) — wrap it so call sites don't depend on
/// the package directly and we can swap implementations in tests.
/// 키체인 항목을 이 기기가 잠금 해제된 뒤에만 읽고, **기기 밖으로 백업되지
/// 않게** 둔다(#1944). 기본값(`unlocked`)은 iCloud 키체인을 타고 다른 기기로
/// 넘어갈 수 있는데, 여기 담기는 것은 이 기기의 세션이다.
const IOSOptions _iosOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

/// 안드로이드는 암호화된 저장소를 쓴다 — 평문 SharedPreferences 에 토큰을
/// 남기지 않는다(#1944).
const AndroidOptions _androidOptions = AndroidOptions(
  encryptedSharedPreferences: true,
);

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    iOptions: _iosOptions,
    aOptions: _androidOptions,
  ),
  name: 'secureStorage',
);

/// 접근·refresh 토큰 저장소.
///
/// 모바일은 플랫폼 보안 저장소(Keychain/Keystore)에 영구 저장한다 — 앱을 다시 켜도
/// 세션이 이어진다. 웹은 `sessionStorage` 가 주어지며 토큰을 거기(탭 단위)에만
/// 둔다(#2828). 웹의 보안 저장소는 사실상 localStorage 라 같은 출처의 스크립트가
/// 그대로 읽을 수 있고 브라우저를 닫아도 남는다. 탭을 닫으면 다시 로그인해야 한다.
class SecureTokenStore {
  SecureTokenStore(this._storage, {TokenSessionStorage? sessionStorage})
    : _session = sessionStorage;

  final FlutterSecureStorage _storage;
  final TokenSessionStorage? _session;

  /// 이 인스턴스가 예전 웹 빌드가 localStorage 에 남긴 토큰을 이미 지웠는가.
  bool _legacyPurged = false;

  static const String _kAccessToken = 'access_token';
  static const String _kRefreshToken = 'refresh_token';

  /// 토큰을 탭 단위 저장소에만 두는가(웹).
  bool get isSessionScoped => _session != null;

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    final TokenSessionStorage? session = _session;
    if (session != null) {
      session
        ..write(_kAccessToken, access)
        ..write(_kRefreshToken, refresh);
      await _purgeLegacyPersistedTokens();
      return;
    }
    await _storage.write(key: _kAccessToken, value: access);
    await _storage.write(key: _kRefreshToken, value: refresh);
  }

  Future<String?> readAccessToken() => _read(_kAccessToken);
  Future<String?> readRefreshToken() => _read(_kRefreshToken);

  Future<String?> _read(String key) async {
    final TokenSessionStorage? session = _session;
    if (session == null) return _storage.read(key: key);
    // 예전 빌드가 영구 저장소에 남긴 토큰은 **읽지 않고** 지운다 — 읽어 이어 쓰면
    // localStorage 에 30일짜리 refresh 토큰이 계속 남는다. 한 번 다시 로그인하면 된다.
    await _purgeLegacyPersistedTokens();
    return session.read(key);
  }

  Future<void> clear() async {
    final TokenSessionStorage? session = _session;
    if (session != null) {
      session
        ..remove(_kAccessToken)
        ..remove(_kRefreshToken);
      _legacyPurged = false;
      await _purgeLegacyPersistedTokens();
      return;
    }
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
  }

  /// 웹에서 영구 저장소(localStorage)에 남은 토큰을 지운다. 실패해도 세션 동작은
  /// 막지 않는다 — 다음 호출에서 다시 시도한다.
  Future<void> _purgeLegacyPersistedTokens() async {
    if (_legacyPurged) return;
    try {
      await _storage.delete(key: _kAccessToken);
      await _storage.delete(key: _kRefreshToken);
      _legacyPurged = true;
    } on Object {
      // 저장소를 쓸 수 없는 브라우저 — 남은 값도 없다고 보고 다음에 다시 본다.
    }
  }
}

/// 웹이면 탭 단위 토큰 저장소, 그 밖은 `null`(#2828). 테스트는 이 provider 를
/// 덮어 웹 동작을 확인한다.
final tokenSessionStorageProvider = Provider<TokenSessionStorage?>(
  (ref) => createPlatformTokenSessionStorage(),
  name: 'tokenSessionStorage',
);

final secureTokenStoreProvider = Provider<SecureTokenStore>(
  (ref) => SecureTokenStore(
    ref.watch(secureStorageProvider),
    sessionStorage: ref.watch(tokenSessionStorageProvider),
  ),
  name: 'secureTokenStore',
);

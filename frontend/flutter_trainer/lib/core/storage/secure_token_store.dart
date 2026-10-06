import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:oncare_core/storage/token_keys.dart';
import 'package:oncare_trainer/core/storage/token_session_storage.dart';

/// `FlutterSecureStorage` is platform-backed (Keychain / Keystore /
/// localStorage on web — 그래서 웹 토큰은 [SecureTokenStore] 가
/// sessionStorage 에 둔다, #2828) — wrap it so call sites don't depend on the
/// package directly and it can be overridden in tests.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
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

  /// 이 인스턴스가 이름공간 없던 옛 키를 이미 옮겼는가(#3054).
  bool _keysMigrated = false;

  /// 진행 중인 옛 키 옮기기. 동시에 부른 쪽이 같은 작업을 기다린다 — 옮기는
  /// 도중 [clear] 가 끼면 옮기던 옛 토큰이 지운 뒤에 다시 써진다.
  Future<void>? _migration;

  /// 이 인스턴스가 옛 키에서 복사해 온 접근 토큰(#3260, 웹). 역할 확인을 통과하면
  /// [claimLegacyKeys] 가 이 값을 가진 옛 키를 지운다.
  String? _copiedLegacyAccess;

  /// 토큰 키 이름공간(#3054). 회원 앱과 트레이너 웹은 한 출처에 배포돼 같은
  /// 브라우저 저장소를 보므로, 키에 앱 이름을 붙여 서로의 토큰을 건드리지 않는다.
  static const TokenKeyspace keyspace = TokenKeyspace.trainer;

  /// 토큰을 탭 단위 저장소에만 두는가(웹).
  bool get isSessionScoped => _session != null;

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _migrateLegacyKeys();
    final TokenSessionStorage? session = _session;
    if (session != null) {
      session
        ..write(keyspace.accessKey, access)
        ..write(keyspace.refreshKey, refresh);
      await _purgeLegacyPersistedTokens();
      return;
    }
    await _storage.write(key: keyspace.accessKey, value: access);
    await _storage.write(key: keyspace.refreshKey, value: refresh);
  }

  Future<String?> readAccessToken() => _read(keyspace.accessKey);
  Future<String?> readRefreshToken() => _read(keyspace.refreshKey);

  Future<String?> _read(String key) async {
    await _migrateLegacyKeys();
    final TokenSessionStorage? session = _session;
    if (session == null) return _storage.read(key: key);
    // 예전 빌드가 영구 저장소에 남긴 토큰은 **읽지 않고** 지운다 — 읽어 이어 쓰면
    // localStorage 에 30일짜리 refresh 토큰이 계속 남는다. 한 번 다시 로그인하면 된다.
    await _purgeLegacyPersistedTokens();
    return session.read(key);
  }

  /// 이 앱의 토큰을 지운다. 웹은 이 앱 키만 지운다 — 같은 탭 저장소를 쓰는 다른
  /// 앱의 토큰은 남긴다. 모바일 저장소는 이 앱만 쓰므로 옛 키도 함께 지운다.
  ///
  /// [forgetLegacy] 는 로그아웃처럼 이 앱이 세션을 끝낼 때 켠다(#3260). 웹에서도
  /// 이름공간 없던 옛 키를 지운다 — 남겨 두면 새로 고침이 그 토큰을 다시 복사해
  /// 방금 끝낸 로그인이 되살아난다. 역할 확인에 걸려 복사해 온 토큰만 버릴 때는
  /// 끈 채로 두어, 옛 키를 원래 주인 앱이 가져가게 한다.
  Future<void> clear({bool forgetLegacy = false}) async {
    // 세션 복원이 옛 키를 옮기는 중이면 끝난 뒤에 지운다 — 먼저 지우면 옮기던
    // 앞 계정 토큰이 새 키로 되살아난다.
    await _migrateLegacyKeys();
    final TokenSessionStorage? session = _session;
    if (session != null) {
      session
        ..remove(keyspace.accessKey)
        ..remove(keyspace.refreshKey);
      if (forgetLegacy) await deleteLegacyTokenKeys(_sessionAccess(session));
      _copiedLegacyAccess = null;
      _legacyPurged = false;
      await _purgeLegacyPersistedTokens();
      return;
    }
    await _storage.delete(key: keyspace.accessKey);
    await _storage.delete(key: keyspace.refreshKey);
    await _storage.delete(key: legacyAccessTokenKey);
    await _storage.delete(key: legacyRefreshTokenKey);
  }

  /// 세션 복원이 [verifiedAccess] 로 이 앱의 역할을 확인했다 — 그 토큰이 옛 키에서
  /// 온 것이면 옛 키를 지운다(#3260).
  ///
  /// 옛 접근 토큰이 이 인스턴스가 복사해 온 값이거나 방금 확인한 토큰과 같을 때만
  /// 지운다. 이 앱이 새 키로 따로 로그인해 있던 탭이면 옛 키는 다른 앱의 것이라
  /// 남긴다. 모바일은 복사하면서 이미 지웠다.
  Future<void> claimLegacyKeys(String verifiedAccess) async {
    final TokenSessionStorage? session = _session;
    if (session == null) return;
    await _migrateLegacyKeys();
    final String? legacy = session.read(legacyAccessTokenKey);
    if (legacy == null || legacy.isEmpty) return;
    if (legacy != verifiedAccess && legacy != _copiedLegacyAccess) return;
    await deleteLegacyTokenKeys(_sessionAccess(session));
  }

  /// [access] 가 역할 확인 전의 옛 키 토큰인가(#3260, 웹).
  ///
  /// 옛 키는 어느 앱 것인지 모른다. 세션 복원이 이 토큰으로 401 을 받으면
  /// 갱신 토큰을 **회전하지 않는다** — 갱신 토큰은 일회용이고 재사용은 세션
  /// 폐기라, 다른 앱의 것을 돌리면 주인 앱이 나중에 그 세션을 잃는다. 이 앱의
  /// 새 키만 비우고 옛 키는 남겨, 주인 앱도 같은 규칙으로 다룬다. 역할 확인을
  /// 통과해 [claimLegacyKeys] 가 옛 키를 지운 뒤에는 거짓이다. 모바일은 이 앱만
  /// 쓰는 저장소라 늘 거짓이다.
  Future<bool> isUnconfirmedLegacy(String access) async {
    final TokenSessionStorage? session = _session;
    if (session == null || access.isEmpty) return false;
    await _migrateLegacyKeys();
    final String? legacy = session.read(legacyAccessTokenKey);
    if (legacy == null || legacy.isEmpty) return false;
    return legacy == access || legacy == _copiedLegacyAccess;
  }

  /// 이름공간 없던 옛 키의 토큰을 한 번 옮긴다(#3054).
  ///
  /// 모바일은 이 앱만 쓰는 저장소라 옮긴 토큰이 이 앱의 것이다 — 업데이트한
  /// 회원이 다시 로그인하지 않아도 된다. 복사한 뒤 옛 키를 바로 지운다. 웹 탭
  /// 저장소의 옛 키는 어느 앱 것인지 모르므로 복사만 하고, 옮긴 토큰은 세션
  /// 복원의 역할 확인을 통과해야 세션이 된다 — 통과하면 [claimLegacyKeys] 가 옛
  /// 키를 지운다(#3260). 실패하면 다음 호출에서 다시 시도한다.
  Future<void> _migrateLegacyKeys() {
    if (_keysMigrated) return Future<void>.value();
    return _migration ??= _runMigration().whenComplete(() => _migration = null);
  }

  Future<void> _runMigration() async {
    final TokenSessionStorage? session = _session;
    final TokenKeyValueAccess access = session != null
        ? _sessionAccess(session)
        : TokenKeyValueAccess(
            read: (String key) => _storage.read(key: key),
            write: (String key, String value) =>
                _storage.write(key: key, value: value),
            delete: (String key) => _storage.delete(key: key),
          );
    try {
      if (await migrateLegacyTokenKeys(access, keyspace)) {
        if (session == null) {
          await deleteLegacyTokenKeys(access);
        } else {
          _copiedLegacyAccess = session.read(keyspace.accessKey);
        }
      }
      _keysMigrated = true;
    } on Object {
      // 저장소를 지금 쓸 수 없다 — 이어지는 읽기·쓰기가 같은 실패를 알린다.
    }
  }

  static TokenKeyValueAccess _sessionAccess(TokenSessionStorage session) =>
      TokenKeyValueAccess(
        read: (String key) async => session.read(key),
        write: (String key, String value) async => session.write(key, value),
        delete: (String key) async => session.remove(key),
      );

  /// 웹에서 영구 저장소(localStorage)에 남은 토큰을 지운다. 실패해도 세션 동작은
  /// 막지 않는다 — 다음 호출에서 다시 시도한다. 예전 빌드는 옛 이름으로만
  /// 썼으므로 옛 이름을 지운다.
  Future<void> _purgeLegacyPersistedTokens() async {
    if (_legacyPurged) return;
    try {
      await _storage.delete(key: legacyAccessTokenKey);
      await _storage.delete(key: legacyRefreshTokenKey);
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

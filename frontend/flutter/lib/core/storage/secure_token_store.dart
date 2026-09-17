import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// `FlutterSecureStorage` is platform-backed (Keychain / Keystore /
/// localStorage on web) — wrap it so call sites don't depend on
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

/// Holds the access/refresh tokens emitted by the auth feature
/// (Stage 4). Token rotation will happen inside the auth interceptor
/// once it lands.
class SecureTokenStore {
  SecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const String _kAccessToken = 'access_token';
  static const String _kRefreshToken = 'refresh_token';

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _kAccessToken, value: access);
    await _storage.write(key: _kRefreshToken, value: refresh);
  }

  Future<String?> readAccessToken() => _storage.read(key: _kAccessToken);
  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);

  Future<void> clear() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
  }
}

final secureTokenStoreProvider = Provider<SecureTokenStore>(
  (ref) => SecureTokenStore(ref.watch(secureStorageProvider)),
  name: 'secureTokenStore',
);

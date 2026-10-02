import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/core/storage/token_session_storage.dart';

/// 웹 빌드의 토큰 저장 위치(#2828).
///
/// 웹의 보안 저장소는 localStorage 라 refresh 토큰이 브라우저를 닫아도 남고 같은
/// 출처의 스크립트가 읽을 수 있다. 웹에서는 탭 단위 저장소에만 두고, 예전 빌드가
/// 남긴 값은 읽지 않고 지운다. 모바일(탭 단위 저장소 없음)은 그대로다.
void main() {
  const FlutterSecureStorage secure = FlutterSecureStorage();

  Future<Map<String, String>> persisted() => secure.readAll();

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  group('mobile (no session storage)', () {
    test('saves both tokens to the platform secure storage', () async {
      final SecureTokenStore store = SecureTokenStore(secure);
      expect(store.isSessionScoped, isFalse);

      await store.saveTokens(access: 'a1', refresh: 'r1');

      expect(await persisted(), <String, String>{
        'access_token': 'a1',
        'refresh_token': 'r1',
      });
      expect(await store.readAccessToken(), 'a1');
      expect(await store.readRefreshToken(), 'r1');
    });

    test('keeps a session saved by an earlier launch', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'old-a',
        'refresh_token': 'old-r',
      });
      final SecureTokenStore store = SecureTokenStore(secure);

      expect(await store.readAccessToken(), 'old-a');
      expect(await store.readRefreshToken(), 'old-r');
    });

    test('clear removes both tokens', () async {
      final SecureTokenStore store = SecureTokenStore(secure);
      await store.saveTokens(access: 'a1', refresh: 'r1');

      await store.clear();

      expect(await persisted(), isEmpty);
      expect(await store.readRefreshToken(), isNull);
    });
  });

  group('web (session storage)', () {
    late InMemoryTokenSessionStorage session;
    late SecureTokenStore store;

    setUp(() {
      session = InMemoryTokenSessionStorage();
      store = SecureTokenStore(secure, sessionStorage: session);
    });

    test('never writes tokens to the persistent storage', () async {
      expect(store.isSessionScoped, isTrue);

      await store.saveTokens(access: 'a1', refresh: 'r1');

      expect(await persisted(), isEmpty);
      expect(session.read('access_token'), 'a1');
      expect(session.read('refresh_token'), 'r1');
    });

    test('reads tokens back from the tab session', () async {
      await store.saveTokens(access: 'a1', refresh: 'r1');

      expect(await store.readAccessToken(), 'a1');
      expect(await store.readRefreshToken(), 'r1');
    });

    test('rotation overwrites the tab session only', () async {
      await store.saveTokens(access: 'a1', refresh: 'r1');
      await store.saveTokens(access: 'a2', refresh: 'r2');

      expect(await store.readRefreshToken(), 'r2');
      expect(await persisted(), isEmpty);
    });

    test('purges tokens an older web build left in localStorage', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'legacy-a',
        'refresh_token': 'legacy-r',
        'unrelated': 'kept',
      });

      // 예전 값은 이어 쓰지 않는다 — 다시 로그인하게 한다.
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(await persisted(), <String, String>{'unrelated': 'kept'});
    });

    test('saving also purges legacy persistent tokens', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'refresh_token': 'legacy-r',
      });

      await store.saveTokens(access: 'a1', refresh: 'r1');

      expect(await persisted(), isEmpty);
      expect(await store.readRefreshToken(), 'r1');
    });

    test('clear empties the tab session and persistent storage', () async {
      await store.saveTokens(access: 'a1', refresh: 'r1');
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'refresh_token': 'legacy-r',
      });

      await store.clear();

      expect(session.read('access_token'), isNull);
      expect(session.read('refresh_token'), isNull);
      expect(await persisted(), isEmpty);
    });

    test('a new tab (fresh session storage) starts signed out', () async {
      await store.saveTokens(access: 'a1', refresh: 'r1');

      final SecureTokenStore otherTab = SecureTokenStore(
        secure,
        sessionStorage: InMemoryTokenSessionStorage(),
      );

      expect(await otherTab.readAccessToken(), isNull);
      expect(await otherTab.readRefreshToken(), isNull);
    });
  });

  group('providers', () {
    test('tests and mobile builds have no session storage', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(tokenSessionStorageProvider), isNull);
      expect(container.read(secureTokenStoreProvider).isSessionScoped, isFalse);
    });

    test('a session storage override routes the store to it', () async {
      final InMemoryTokenSessionStorage session = InMemoryTokenSessionStorage();
      final ProviderContainer container = ProviderContainer(
        overrides: [tokenSessionStorageProvider.overrideWithValue(session)],
      );
      addTearDown(container.dispose);

      final SecureTokenStore store = container.read(secureTokenStoreProvider);
      await store.saveTokens(access: 'a1', refresh: 'r1');

      expect(store.isSessionScoped, isTrue);
      expect(session.read('refresh_token'), 'r1');
      expect(await persisted(), isEmpty);
    });
  });

  group('InMemoryTokenSessionStorage', () {
    test('read / write / remove', () {
      final InMemoryTokenSessionStorage s = InMemoryTokenSessionStorage();
      expect(s.read('k'), isNull);
      s.write('k', 'v');
      expect(s.read('k'), 'v');
      s.write('k', 'w');
      expect(s.read('k'), 'w');
      s.remove('k');
      expect(s.read('k'), isNull);
    });
  });
}

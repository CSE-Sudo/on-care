import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/core/storage/token_session_storage.dart';
import 'package:oncare_core/storage/token_keys.dart';

/// 웹 빌드의 토큰 저장 위치(#2828).
///
/// 웹의 보안 저장소는 localStorage 라 refresh 토큰이 브라우저를 닫아도 남고 같은
/// 출처의 스크립트가 읽을 수 있다. 웹에서는 탭 단위 저장소에만 두고, 예전 빌드가
/// 남긴 값은 읽지 않고 지운다. 모바일(탭 단위 저장소 없음)은 그대로다.
void main() {
  const FlutterSecureStorage secure = FlutterSecureStorage();

  Future<Map<String, String>> persisted() => secure.readAll();

  // 이 앱의 토큰 키(#3054).
  final String access = TokenKeyspace.member.accessKey;
  final String refresh = TokenKeyspace.member.refreshKey;

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  group('mobile (no session storage)', () {
    test('saves both tokens to the platform secure storage', () async {
      final SecureTokenStore store = SecureTokenStore(secure);
      expect(store.isSessionScoped, isFalse);

      await store.saveTokens(access: 'a1', refresh: 'r1');

      expect(await persisted(), <String, String>{access: 'a1', refresh: 'r1'});
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
      // 옛 이름은 이 앱 이름으로 옮겨졌다(#3054) — 업데이트해도 다시 로그인하지 않는다.
      expect(await persisted(), <String, String>{
        access: 'old-a',
        refresh: 'old-r',
      });
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
      expect(session.read(access), 'a1');
      expect(session.read(refresh), 'r1');
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

      expect(session.read(access), isNull);
      expect(session.read(refresh), isNull);
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

  group('key namespace (#3054)', () {
    test('mobile clear also removes leftover legacy keys', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'refresh_token': 'orphan-r',
      });
      final SecureTokenStore store = SecureTokenStore(secure);
      await store.saveTokens(access: 'a1', refresh: 'r1');

      await store.clear();

      expect(await persisted(), isEmpty);
    });

    test('mobile never treats a token as unconfirmed legacy', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'old-a',
        'refresh_token': 'old-r',
      });
      final SecureTokenStore store = SecureTokenStore(secure);

      expect(await store.readAccessToken(), 'old-a');
      expect(await store.isUnconfirmedLegacy('old-a'), isFalse);
    });

    test('mobile keeps namespaced tokens over legacy ones', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        access: 'new-a',
        refresh: 'new-r',
        'access_token': 'legacy-a',
        'refresh_token': 'legacy-r',
      });
      final SecureTokenStore store = SecureTokenStore(secure);

      expect(await store.readAccessToken(), 'new-a');
      expect(await store.readRefreshToken(), 'new-r');
    });

    test(
      'clear during a legacy migration does not bring the old token back',
      () async {
        // 세션 복원이 옛 키를 옮기는 사이 로그인이 토큰을 지우는 순서다.
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          'access_token': 'old-access',
          'refresh_token': 'old-refresh',
        });
        final SecureTokenStore store = SecureTokenStore(secure);

        final Future<String?> restoring = store.readAccessToken();
        final Future<void> clearing = store.clear();
        await Future.wait(<Future<Object?>>[restoring, clearing]);

        expect(await store.readAccessToken(), isNull);
        expect(await store.readRefreshToken(), isNull);
        expect(await persisted(), isEmpty);
      },
    );

    test('concurrent reads share one migration', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'legacy-a',
        'refresh_token': 'legacy-r',
      });
      final SecureTokenStore store = SecureTokenStore(secure);

      final List<String?> read = await Future.wait(<Future<String?>>[
        store.readAccessToken(),
        store.readRefreshToken(),
        store.readAccessToken(),
      ]);

      expect(read, <String?>['legacy-a', 'legacy-r', 'legacy-a']);
      expect(await persisted(), <String, String>{
        access: 'legacy-a',
        refresh: 'legacy-r',
      });
    });

    test('web moves a pre-namespace tab session to this app keys', () async {
      final InMemoryTokenSessionStorage session = InMemoryTokenSessionStorage()
        ..write('access_token', 'old-a')
        ..write('refresh_token', 'old-r');
      final SecureTokenStore store = SecureTokenStore(
        secure,
        sessionStorage: session,
      );

      expect(await store.readAccessToken(), 'old-a');
      expect(await store.readRefreshToken(), 'old-r');
      expect(session.read(access), 'old-a');
      // 역할 확인 전에는 옛 키를 남긴다 — 다른 앱 것일 수 있다(#3260).
      expect(session.read('access_token'), 'old-a');
      expect(session.read('refresh_token'), 'old-r');
    });

    group('legacy keys on the web (#3260)', () {
      late InMemoryTokenSessionStorage session;
      late SecureTokenStore store;

      setUp(() {
        session = InMemoryTokenSessionStorage()
          ..write('access_token', 'old-a')
          ..write('refresh_token', 'old-r');
        store = SecureTokenStore(secure, sessionStorage: session);
      });

      test('a passed role check removes the copied legacy keys', () async {
        final String? copied = await store.readAccessToken();

        await store.claimLegacyKeys(copied!);

        expect(session.read('access_token'), isNull);
        expect(session.read('refresh_token'), isNull);
        expect(session.read(access), 'old-a');
        expect(session.read(refresh), 'old-r');
      });

      test('the claim also holds after a rotation', () async {
        await store.readAccessToken();
        await store.saveTokens(access: 'rotated-a', refresh: 'rotated-r');

        await store.claimLegacyKeys('rotated-a');

        expect(session.read('access_token'), isNull);
        expect(session.read('refresh_token'), isNull);
      });

      test(
        'a failed role check keeps the legacy keys for their owner',
        () async {
          await store.readAccessToken();

          await store.clear();

          expect(session.read(access), isNull);
          expect(session.read(refresh), isNull);
          expect(session.read('access_token'), 'old-a');
          expect(session.read('refresh_token'), 'old-r');
        },
      );

      test(
        'legacy keys of the other app stay when this app is signed in',
        () async {
          session
            ..write(access, 'mine-a')
            ..write(refresh, 'mine-r');

          expect(await store.readAccessToken(), 'mine-a');
          await store.claimLegacyKeys('mine-a');

          expect(session.read('access_token'), 'old-a');
          expect(session.read('refresh_token'), 'old-r');
        },
      );

      test(
        'a legacy token equal to the verified one is claimed later',
        () async {
          // 앞 페이지가 복사만 하고 확인하지 못한 채 새로 고침된 탭이다.
          session
            ..write(access, 'old-a')
            ..write(refresh, 'old-r');

          expect(await store.readAccessToken(), 'old-a');
          await store.claimLegacyKeys('old-a');

          expect(session.read('access_token'), isNull);
          expect(session.read('refresh_token'), isNull);
        },
      );

      test('a copied legacy token is unconfirmed until claimed', () async {
        final String? copied = await store.readAccessToken();

        expect(await store.isUnconfirmedLegacy(copied!), isTrue);
        await store.claimLegacyKeys(copied);
        expect(await store.isUnconfirmedLegacy(copied), isFalse);
      });

      test('a copy left by an earlier page is still unconfirmed', () async {
        session
          ..write(access, 'old-a')
          ..write(refresh, 'old-r');

        expect(await store.isUnconfirmedLegacy('old-a'), isTrue);
      });

      test('this app own token is not an unconfirmed legacy one', () async {
        session
          ..write(access, 'mine-a')
          ..write(refresh, 'mine-r');

        expect(await store.readAccessToken(), 'mine-a');
        expect(await store.isUnconfirmedLegacy('mine-a'), isFalse);
      });

      test('sign-out removes the legacy keys too', () async {
        session
          ..write(access, 'mine-a')
          ..write(refresh, 'mine-r');
        await store.readAccessToken();

        await store.clear(forgetLegacy: true);

        expect(session.read(access), isNull);
        expect(session.read('access_token'), isNull);
        expect(session.read('refresh_token'), isNull);
      });

      test('a reload after sign-out stays signed out', () async {
        await store.readAccessToken();
        await store.clear(forgetLegacy: true);

        final SecureTokenStore reloaded = SecureTokenStore(
          secure,
          sessionStorage: session,
        );

        expect(await reloaded.readAccessToken(), isNull);
        expect(await reloaded.readRefreshToken(), isNull);
      });

      test('sign-out leaves the trainer app keys alone', () async {
        session
          ..write(TokenKeyspace.trainer.accessKey, 'other-a')
          ..write(TokenKeyspace.trainer.refreshKey, 'other-r');
        await store.readAccessToken();

        await store.clear(forgetLegacy: true);

        expect(session.read(TokenKeyspace.trainer.accessKey), 'other-a');
        expect(session.read(TokenKeyspace.trainer.refreshKey), 'other-r');
      });
    });

    test('web never writes the other app keys', () async {
      final InMemoryTokenSessionStorage session = InMemoryTokenSessionStorage()
        ..write(TokenKeyspace.trainer.accessKey, 'other-a')
        ..write(TokenKeyspace.trainer.refreshKey, 'other-r');
      final SecureTokenStore store = SecureTokenStore(
        secure,
        sessionStorage: session,
      );

      await store.saveTokens(access: 'a1', refresh: 'r1');
      await store.saveTokens(access: 'a2', refresh: 'r2');
      expect(await store.readAccessToken(), 'a2');

      await store.clear();

      expect(await store.readAccessToken(), isNull);
      expect(session.read(TokenKeyspace.trainer.accessKey), 'other-a');
      expect(session.read(TokenKeyspace.trainer.refreshKey), 'other-r');
    });

    test('this app does not read the other app session', () async {
      final InMemoryTokenSessionStorage session = InMemoryTokenSessionStorage()
        ..write(TokenKeyspace.trainer.accessKey, 'other-a')
        ..write(TokenKeyspace.trainer.refreshKey, 'other-r');
      final SecureTokenStore store = SecureTokenStore(
        secure,
        sessionStorage: session,
      );

      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    });

    test('keyspace is this app name', () {
      expect(SecureTokenStore.keyspace, TokenKeyspace.member);
      expect(access, startsWith('oncare.member.'));
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
      expect(session.read(refresh), 'r1');
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

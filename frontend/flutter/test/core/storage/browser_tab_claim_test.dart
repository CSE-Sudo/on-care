/// 이 앱의 복제 탭 판정(#3248, #3271). 판정 자체는 `oncare_core` 가 맡고
/// (`shared/oncare_core/test/storage/browser_tab_claim_test.dart`), 여기서는 이
/// 앱의 토큰 저장소가 그 판정을 거쳐 복제한 탭에서 로그인을 잇지 않는지 본다.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/core/storage/token_session_storage.dart';
import 'package:oncare_core/storage/browser_tab_claim.dart';
import 'package:oncare_core/storage/token_keys.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 10, 5, 3);
  const BrowserTabClaim tabs = BrowserTabClaim(SecureTokenStore.keyspace);
  final String access = SecureTokenStore.keyspace.accessKey;
  final String refresh = SecureTokenStore.keyspace.refreshKey;
  late InMemoryTabMarkerStore markers;
  late int issued;

  String claim(InMemoryTokenSessionStorage tab) => tabs.claim(
    tab: tab,
    markers: markers,
    newTabId: () => 'tab-${++issued}',
    now: now,
  );

  /// 복제처럼 [from] 의 값을 그대로 옮긴 새 탭 저장소.
  InMemoryTokenSessionStorage copyOf(InMemoryTokenSessionStorage from) {
    final InMemoryTokenSessionStorage copy = InMemoryTokenSessionStorage();
    for (final String key in <String>[
      access,
      refresh,
      legacyAccessTokenKey,
      legacyRefreshTokenKey,
      tabs.tabIdKey,
    ]) {
      final String? value = from.read(key);
      if (value != null) copy.write(key, value);
    }
    return copy;
  }

  SecureTokenStore storeOn(TokenSessionStorage tab) => SecureTokenStore(
    const FlutterSecureStorage(),
    sessionStorage: tabs.scoped(tab),
  );

  setUp(() {
    markers = InMemoryTabMarkerStore();
    issued = 0;
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('이 앱의 이름공간으로 판정한다', () {
    expect(tabs.space, SecureTokenStore.keyspace);
    expect(tabs.tokenKeys, <String>[access, refresh]);
  });

  test('복제한 탭은 로그인을 잇지 않고, 원래 탭은 그대로다', () async {
    final InMemoryTokenSessionStorage original = InMemoryTokenSessionStorage()
      ..write(access, 'a1')
      ..write(refresh, 'r1');
    claim(original);
    final InMemoryTokenSessionStorage duplicate = copyOf(original);

    claim(duplicate);

    expect(await storeOn(duplicate).readAccessToken(), isNull);
    expect(await storeOn(duplicate).readRefreshToken(), isNull);
    expect(await storeOn(original).readAccessToken(), 'a1');
    expect(await storeOn(original).readRefreshToken(), 'r1');
  });

  test('새로 고침은 복제가 아니라 로그인이 이어진다', () async {
    final InMemoryTokenSessionStorage tab = InMemoryTokenSessionStorage()
      ..write(access, 'a1')
      ..write(refresh, 'r1');
    final String id = claim(tab);

    tabs.release(markers, id); // pagehide
    claim(tab);

    expect(await storeOn(tab).readAccessToken(), 'a1');
  });

  test('복제한 탭의 토큰 저장소는 원래 탭의 옛 토큰을 옮겨 오지 않는다', () async {
    final InMemoryTokenSessionStorage original = InMemoryTokenSessionStorage()
      ..write(legacyAccessTokenKey, 'old-a')
      ..write(legacyRefreshTokenKey, 'old-r');
    claim(original);
    final InMemoryTokenSessionStorage duplicate = copyOf(original);
    claim(duplicate);

    final SecureTokenStore store = storeOn(duplicate);

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(duplicate.read(access), isNull);
    expect(duplicate.read(legacyAccessTokenKey), 'old-a');
  });
}

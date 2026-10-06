/// 복제한 탭이 원래 탭의 토큰을 함께 쓰지 않는다 (#3248, #3271).
///
/// 탭 복제는 sessionStorage 를 복사한다. 두 탭이 같은 refresh 토큰을 따로
/// 회전하면 서버가 재사용으로 보고 세션 전체를 끊어 두 탭이 함께 로그아웃됐다.
/// 두 앱이 같은 판정을 쓰고, 키 이름공간만 다르다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/storage/browser_tab_claim.dart';
import 'package:oncare_core/storage/token_keys.dart';
import 'package:oncare_core/storage/token_session_storage.dart';

/// 복제처럼 [from] 의 값을 그대로 옮긴 새 탭 저장소.
InMemoryTokenSessionStorage _copyOf(
  InMemoryTokenSessionStorage from,
  List<String> keys,
) {
  final InMemoryTokenSessionStorage copy = InMemoryTokenSessionStorage();
  for (final String key in keys) {
    final String? value = from.read(key);
    if (value != null) copy.write(key, value);
  }
  return copy;
}

void main() {
  final DateTime now = DateTime.utc(2026, 10, 5, 3);
  late InMemoryTabMarkerStore markers;
  late int issued;

  String newId() => 'tab-${++issued}';

  setUp(() {
    markers = InMemoryTabMarkerStore();
    issued = 0;
  });

  test('트레이너 웹의 키 이름은 공용으로 옮기기 전과 같다', () {
    // 배포 중인 탭이 남긴 id·표시를 그대로 읽어야 한다(#3248).
    const BrowserTabClaim trainer = BrowserTabClaim(TokenKeyspace.trainer);
    expect(trainer.tabIdKey, 'oncare.trainer.tab_id');
    expect(trainer.markerPrefix, 'oncare.trainer.open_tab.');
    expect(trainer.legacyBlindKey, 'oncare.trainer.legacy_keys_blind');
    expect(trainer.tokenKeys, <String>[
      'oncare.trainer.access_token',
      'oncare.trainer.refresh_token',
    ]);
  });

  test('회원 앱은 자기 이름공간을 쓴다', () {
    const BrowserTabClaim member = BrowserTabClaim(TokenKeyspace.member);
    expect(member.tabIdKey, 'oncare.member.tab_id');
    expect(member.markerPrefix, 'oncare.member.open_tab.');
    expect(member.legacyBlindKey, 'oncare.member.legacy_keys_blind');
    expect(member.tokenKeys, <String>[
      'oncare.member.access_token',
      'oncare.member.refresh_token',
    ]);
  });

  for (final TokenKeyspace space in TokenKeyspace.values) {
    group(space.prefix, () {
      final BrowserTabClaim tabs = BrowserTabClaim(space);

      String claim(InMemoryTokenSessionStorage tab, {DateTime? at}) =>
          tabs.claim(
            tab: tab,
            markers: markers,
            newTabId: newId,
            now: at ?? now,
          );

      InMemoryTokenSessionStorage signedInTab() => InMemoryTokenSessionStorage()
        ..write(space.accessKey, 'a1')
        ..write(space.refreshKey, 'r1');

      test('처음 연 탭은 id 를 받고 열린 탭으로 표시된다', () {
        final InMemoryTokenSessionStorage tab = signedInTab();

        final String id = claim(tab);

        expect(id, 'tab-1');
        expect(tab.read(tabs.tabIdKey), 'tab-1');
        expect(markers.read('${tabs.markerPrefix}tab-1'), isNotNull);
        expect(tab.read(space.refreshKey), 'r1');
      });

      test('열려 있는 탭을 복제하면 복제한 탭만 토큰을 버리고 새 id 를 받는다', () {
        final InMemoryTokenSessionStorage original = signedInTab();
        claim(original);
        final InMemoryTokenSessionStorage duplicate = _copyOf(original, <String>[
          ...tabs.tokenKeys,
          tabs.tabIdKey,
        ]);

        final String id = claim(duplicate);

        expect(id, 'tab-2');
        expect(duplicate.read(space.accessKey), isNull);
        expect(duplicate.read(space.refreshKey), isNull);
        // 원래 탭의 세션은 그대로다.
        expect(original.read(space.refreshKey), 'r1');
        expect(original.read(tabs.tabIdKey), 'tab-1');
      });

      test('새로 고침은 복제가 아니다 — 떠날 때 표시를 지운다', () {
        final InMemoryTokenSessionStorage tab = signedInTab();
        final String id = claim(tab);

        tabs.release(markers, id); // pagehide
        final String again = claim(tab);

        expect(again, id);
        expect(tab.read(space.refreshKey), 'r1');
      });

      test('비정상 종료로 남은 오래된 표시는 치운다', () {
        final InMemoryTokenSessionStorage tab = signedInTab();
        final String id = claim(
          tab,
          at: now.subtract(const Duration(days: 31)),
        );

        // 표시를 지우지 못한 채 한 달 뒤 같은 저장소로 되살아났다.
        final String again = claim(tab);

        expect(again, id);
        expect(tab.read(space.refreshKey), 'r1');
      });
    });
  }

  group('두 앱이 한 출처에서', () {
    const BrowserTabClaim member = BrowserTabClaim(TokenKeyspace.member);
    const BrowserTabClaim trainer = BrowserTabClaim(TokenKeyspace.trainer);

    test('한 앱의 판정은 다른 앱의 id·표시·토큰을 건드리지 않는다', () {
      final InMemoryTokenSessionStorage tab = InMemoryTokenSessionStorage()
        ..write(TokenKeyspace.member.accessKey, 'm-a')
        ..write(TokenKeyspace.trainer.accessKey, 't-a');
      final String trainerId = trainer.claim(
        tab: tab,
        markers: markers,
        newTabId: newId,
        now: now,
      );

      member.claim(tab: tab, markers: markers, newTabId: newId, now: now);

      expect(tab.read(trainer.tabIdKey), trainerId);
      expect(markers.read('${trainer.markerPrefix}$trainerId'), isNotNull);
      expect(tab.read(TokenKeyspace.trainer.accessKey), 't-a');
      expect(tab.read(TokenKeyspace.member.accessKey), 'm-a');
    });

    test('회원 앱이 연 탭을 복제하면 회원 토큰만 버린다', () {
      final InMemoryTokenSessionStorage original = InMemoryTokenSessionStorage()
        ..write(TokenKeyspace.member.accessKey, 'm-a')
        ..write(TokenKeyspace.trainer.accessKey, 't-a');
      member.claim(tab: original, markers: markers, newTabId: newId, now: now);
      final InMemoryTokenSessionStorage duplicate = _copyOf(original, <String>[
        TokenKeyspace.member.accessKey,
        TokenKeyspace.trainer.accessKey,
        member.tabIdKey,
      ]);

      member.claim(tab: duplicate, markers: markers, newTabId: newId, now: now);

      expect(duplicate.read(TokenKeyspace.member.accessKey), isNull);
      expect(duplicate.read(TokenKeyspace.trainer.accessKey), 't-a');
    });

    test('다른 앱의 표시는 치우지 않는다', () {
      markers.write('oncare.trainer.open_tab.old', '0');

      member.claim(
        tab: InMemoryTokenSessionStorage(),
        markers: markers,
        newTabId: newId,
        now: now,
      );

      expect(markers.read('oncare.trainer.open_tab.old'), '0');
    });
  });

  group('옛 키 (#3260)', () {
    const BrowserTabClaim tabs = BrowserTabClaim(TokenKeyspace.trainer);

    String claim(InMemoryTokenSessionStorage tab) =>
        tabs.claim(tab: tab, markers: markers, newTabId: newId, now: now);

    InMemoryTokenSessionStorage preNamespaceTab() =>
        InMemoryTokenSessionStorage()
          ..write(legacyAccessTokenKey, 'old-a')
          ..write(legacyRefreshTokenKey, 'old-r');

    InMemoryTokenSessionStorage duplicateOf(InMemoryTokenSessionStorage from) =>
        _copyOf(from, <String>[
          legacyAccessTokenKey,
          legacyRefreshTokenKey,
          tabs.tabIdKey,
        ]);

    test('복제한 탭은 옛 키를 지우지 않고 보지도 않는다', () {
      final InMemoryTokenSessionStorage original = preNamespaceTab();
      claim(original);
      final InMemoryTokenSessionStorage duplicate = duplicateOf(original);

      claim(duplicate);
      final TokenSessionStorage scoped = tabs.scoped(duplicate);

      expect(scoped.read(legacyAccessTokenKey), isNull);
      expect(scoped.read(legacyRefreshTokenKey), isNull);
      scoped
        ..remove(legacyAccessTokenKey)
        ..write(legacyRefreshTokenKey, 'x');
      // 탭 저장소의 옛 키는 그대로다 — 건드리지 않는다.
      expect(duplicate.read(legacyAccessTokenKey), 'old-a');
      expect(duplicate.read(legacyRefreshTokenKey), 'old-r');
      // 원래 탭은 지금처럼 옛 키를 본다.
      expect(tabs.scoped(original).read(legacyAccessTokenKey), 'old-a');
    });

    test('복제한 탭을 새로 고쳐도 옛 키를 보지 않는다', () {
      final InMemoryTokenSessionStorage original = preNamespaceTab();
      claim(original);
      final InMemoryTokenSessionStorage duplicate = duplicateOf(original);
      final String id = claim(duplicate);

      tabs.release(markers, id); // pagehide
      claim(duplicate);

      expect(tabs.scoped(duplicate).read(legacyAccessTokenKey), isNull);
    });

    test('옛 키 이전은 복제한 탭에서 아무것도 옮기지 않는다', () async {
      final InMemoryTokenSessionStorage original = preNamespaceTab();
      claim(original);
      final InMemoryTokenSessionStorage duplicate = duplicateOf(original);
      claim(duplicate);
      final TokenSessionStorage scoped = tabs.scoped(duplicate);

      final bool copied = await migrateLegacyTokenKeys(
        TokenKeyValueAccess(
          read: (String key) async => scoped.read(key),
          write: (String key, String value) async => scoped.write(key, value),
          delete: (String key) async => scoped.remove(key),
        ),
        TokenKeyspace.trainer,
      );

      expect(copied, isFalse);
      expect(duplicate.read(TokenKeyspace.trainer.accessKey), isNull);
      expect(duplicate.read(legacyAccessTokenKey), 'old-a');
    });
  });
}

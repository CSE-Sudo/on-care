/// 복제한 탭이 원래 탭의 토큰을 함께 쓰지 않는다 (#3248).
///
/// 탭 복제는 sessionStorage 를 복사한다. 두 탭이 같은 refresh 토큰을 따로
/// 회전하면 서버가 재사용으로 보고 세션 전체를 끊어 두 탭이 함께 로그아웃됐다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/browser_tab_claim.dart';
import 'package:oncare_trainer/core/storage/token_session_storage.dart';

const List<String> _tokenKeys = <String>['access', 'refresh'];

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

  String claim(InMemoryTokenSessionStorage tab, {DateTime? at}) =>
      BrowserTabClaim.claim(
        tab: tab,
        markers: markers,
        tokenKeys: _tokenKeys,
        newTabId: newId,
        now: at ?? now,
      );

  InMemoryTokenSessionStorage signedInTab() => InMemoryTokenSessionStorage()
    ..write('access', 'a1')
    ..write('refresh', 'r1');

  setUp(() {
    markers = InMemoryTabMarkerStore();
    issued = 0;
  });

  test('처음 연 탭은 id 를 받고 열린 탭으로 표시된다', () {
    final InMemoryTokenSessionStorage tab = signedInTab();

    final String id = claim(tab);

    expect(id, 'tab-1');
    expect(tab.read(BrowserTabClaim.tabIdKey), 'tab-1');
    expect(markers.read('${BrowserTabClaim.markerPrefix}tab-1'), isNotNull);
    expect(tab.read('refresh'), 'r1');
  });

  test('열려 있는 탭을 복제하면 복제한 탭만 토큰을 버리고 새 id 를 받는다', () {
    final InMemoryTokenSessionStorage original = signedInTab();
    claim(original);
    final InMemoryTokenSessionStorage duplicate = _copyOf(original, <String>[
      ..._tokenKeys,
      BrowserTabClaim.tabIdKey,
    ]);

    final String id = claim(duplicate);

    expect(id, 'tab-2');
    expect(duplicate.read('access'), isNull);
    expect(duplicate.read('refresh'), isNull);
    // 원래 탭의 세션은 그대로다.
    expect(original.read('refresh'), 'r1');
    expect(original.read(BrowserTabClaim.tabIdKey), 'tab-1');
  });

  test('새로 고침은 복제가 아니다 — 떠날 때 표시를 지운다', () {
    final InMemoryTokenSessionStorage tab = signedInTab();
    final String id = claim(tab);

    BrowserTabClaim.release(markers, id); // pagehide
    final String again = claim(tab);

    expect(again, id);
    expect(tab.read('refresh'), 'r1');
  });

  test('비정상 종료로 남은 오래된 표시는 치운다', () {
    final InMemoryTokenSessionStorage tab = signedInTab();
    final String id = claim(tab, at: now.subtract(const Duration(days: 31)));

    // 표시를 지우지 못한 채 한 달 뒤 같은 저장소로 되살아났다.
    final String again = claim(tab);

    expect(again, id);
    expect(tab.read('refresh'), 'r1');
  });

  test('다른 앱의 값은 건드리지 않는다', () {
    markers.write('oncare.member.something', 'x');
    final InMemoryTokenSessionStorage tab = signedInTab();

    claim(tab);

    expect(markers.read('oncare.member.something'), 'x');
  });
}

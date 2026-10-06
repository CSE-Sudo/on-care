import 'package:oncare_trainer/core/storage/token_session_storage.dart';

/// 여러 탭이 함께 보는 표시 저장소(웹 localStorage). 열린 탭의 표시를 둔다.
abstract interface class TabMarkerStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);

  /// 지금 있는 키 전부 — 오래된 표시를 치울 때 쓴다.
  Iterable<String> get keys;
}

/// 메모리에만 두는 [TabMarkerStore]. 테스트에서 쓴다.
class InMemoryTabMarkerStore implements TabMarkerStore {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;

  @override
  void remove(String key) => _values.remove(key);

  @override
  Iterable<String> get keys => List<String>.of(_values.keys);
}

/// 복제한 탭이 원래 탭의 토큰을 함께 쓰지 않게 한다(#3248).
///
/// 웹 토큰은 탭 단위 저장소(sessionStorage, #2828)에 있다. 그런데 브라우저의
/// `탭 복제` 는 sessionStorage 를 **복사**한다. 두 탭이 같은 refresh 토큰을 따로
/// 회전하다 한쪽이 유예(30초) 밖에서 이미 회전된 토큰을 쓰면, 서버는 재사용으로
/// 보고 그 세션 전체를 끊는다 — 두 탭이 함께 로그아웃된다.
///
/// 탭마다 id 를 탭 저장소에 두고, 열려 있는 동안 공유 저장소에 표시를 남긴다.
/// 시작할 때 내 id 의 표시가 이미 있으면 다른 탭이 같은 id 로 열려 있는 것이다
/// — 복사해 받은 저장소다. 그때는 받은 토큰을 버리고 새 id 를 쓴다. 복제한
/// 탭만 다시 로그인하고, 원래 탭의 세션은 그대로 이어진다.
///
/// 새로 고침·`닫은 탭 다시 열기` 는 복제가 아니다 — 떠날 때(`pagehide`) 표시를
/// 지우므로 다시 열 때 표시가 없다. 브라우저가 비정상 종료돼 표시가 남은 채로
/// 탭을 되살리면 복제로 보고 다시 로그인하게 한다. 세션을 끊는 쪽이 아니라
/// 다시 묻는 쪽으로 틀린다.
class BrowserTabClaim {
  BrowserTabClaim._();

  /// 탭 저장소에 둔 이 탭의 id.
  static const String tabIdKey = 'oncare.trainer.tab_id';

  /// 공유 저장소의 열린 탭 표시 키 앞부분. 값은 표시를 남긴 시각(ms)이다.
  static const String markerPrefix = 'oncare.trainer.open_tab.';

  /// 이보다 오래된 표시는 치운다 — 비정상 종료로 남은 것이다. refresh 토큰의
  /// 기본 수명(30일)이 지나면 남은 탭의 토큰도 어차피 쓸 수 없다.
  static const Duration markerLifetime = Duration(days: 30);

  /// 이 탭의 id 를 정하고 열린 탭으로 표시한다. 정한 id 를 돌려준다.
  ///
  /// 복사해 받은 저장소면 [tokenKeys] 를 탭 저장소에서 지운다. 공유 저장소를
  /// 쓸 수 없으면(사생활 보호 모드 등) 복제를 알아챌 수 없어 그대로 둔다.
  static String claim({
    required TokenSessionStorage tab,
    required TabMarkerStore markers,
    required List<String> tokenKeys,
    required String Function() newTabId,
    required DateTime now,
  }) {
    String? id = tab.read(tabIdKey);
    try {
      _prune(markers, now);
      if (id != null && markers.read('$markerPrefix$id') != null) {
        for (final String key in tokenKeys) {
          tab.remove(key);
        }
        id = null;
      }
      id ??= newTabId();
      tab.write(tabIdKey, id);
      mark(markers, id, now);
    } on Object {
      id ??= newTabId();
      tab.write(tabIdKey, id);
    }
    return id;
  }

  /// [id] 탭이 열려 있다고 표시한다(`pageshow` 로 돌아왔을 때도 부른다).
  static void mark(TabMarkerStore markers, String id, DateTime now) =>
      markers.write('$markerPrefix$id', '${now.millisecondsSinceEpoch}');

  /// [id] 탭이 떠난다(`pagehide`). 표시를 지운다.
  static void release(TabMarkerStore markers, String id) =>
      markers.remove('$markerPrefix$id');

  static void _prune(TabMarkerStore markers, DateTime now) {
    final int oldest = now.subtract(markerLifetime).millisecondsSinceEpoch;
    for (final String key in markers.keys) {
      if (!key.startsWith(markerPrefix)) continue;
      final int? at = int.tryParse(markers.read(key) ?? '');
      if (at == null || at < oldest) markers.remove(key);
    }
  }
}

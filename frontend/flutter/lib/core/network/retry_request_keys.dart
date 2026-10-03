import 'dart:convert';

/// 저장 시도 단위 멱등키 — 보낼 내용이 같으면 같은 키, 바뀌면 새 키(#3095).
///
/// 응답을 잃은 저장을 회원이 다시 누르면 같은 키로 나가야 서버가 처음 결과를
/// 돌려준다. 그런데 화면을 연 때 키를 하나로 고정하면, 실패 뒤 내용을 고쳐 다시
/// 보낸 저장도 같은 키로 나가 서버가 처음 기록을 돌려주고 고친 내용이 버려진다.
/// 그래서 키를 **보낼 본문의 지문**에 묶는다.
///
/// 지문마다 키를 기억하므로 A → B → A 로 고쳤다 돌아와도 A 는 처음 키다. 저장이
/// 성공하면 [clear] 로 모두 버린다 — 그 뒤의 저장은 새 시도다.
class RetryRequestKeys {
  RetryRequestKeys(this._prefix, {String Function()? newKey})
    : _newKey = newKey ?? _timeKey;

  final String _prefix;
  final String Function() _newKey;
  final Map<String, String> _keys = <String, String>{};

  static int _sequence = 0;

  static String _timeKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  /// [body] 를 보낼 때 쓸 키. JSON 으로 옮길 수 있는 값이어야 한다.
  String keyFor(Object? body) =>
      _keys.putIfAbsent(jsonEncode(body), () => '$_prefix-${_newKey()}');

  /// [body] 의 키를 버린다. 서버가 그 키를 다른 내용으로 거절했을 때(409) 쓴다.
  void forget(Object? body) => _keys.remove(jsonEncode(body));

  /// 저장이 끝났다 — 기억한 키를 모두 버린다.
  void clear() => _keys.clear();
}

/// 채팅 이모티콘 — 하나씩 사서 7일 동안 쓴다. (#2153)
///
/// 남은 기간은 서버가 준 **초**에서 센다. 만료 시각만 받아 기기 시계와 빼면,
/// 시계가 틀어진 기기에서 남은 기간이 엉뚱하게 보이거나 이미 끝난 것으로 보인다.
library;

class EmoteState {
  const EmoteState({
    required this.cost,
    required this.days,
    required this.balance,
    this.unlocked = const <String, Duration>{},
  });

  /// 이모티콘 하나의 값(포인트).
  final int cost;

  /// 하나를 사면 쓸 수 있는 날 수.
  final int days;

  /// 지금 포인트 잔액.
  final int balance;

  /// 지금 쓸 수 있는 이모티콘과 남은 기간. 먼저 끝나는 것이 앞이다.
  final Map<String, Duration> unlocked;

  bool isUnlocked(String id) => unlocked.containsKey(id);

  /// 모자란 포인트. 모자라지 않으면 0.
  int get shortfall => balance >= cost ? 0 : cost - balance;

  /// [elapsed] 가 지난 상태. 화면의 남은 기간을 서버에 다시 묻지 않고 센다.
  /// 끝난 이모티콘은 빠진다.
  EmoteState tick(Duration elapsed) => EmoteState(
    cost: cost,
    days: days,
    balance: balance,
    unlocked: <String, Duration>{
      for (final MapEntry<String, Duration> e in unlocked.entries)
        if (e.value - elapsed > Duration.zero) e.key: e.value - elapsed,
    },
  );

  factory EmoteState.fromJson(Map<String, Object?> json) {
    final Map<String, Duration> unlocked = <String, Duration>{};
    final Object? rows = json['unlocked'];
    if (rows is List<Object?>) {
      for (final Object? row in rows) {
        if (row is! Map<String, Object?>) continue;
        final Object? id = row['emote_id'];
        final int seconds = (row['remaining_seconds'] as num?)?.toInt() ?? 0;
        if (id is String && seconds > 0) {
          unlocked[id] = Duration(seconds: seconds);
        }
      }
    }
    return EmoteState(
      cost: (json['cost'] as num?)?.toInt() ?? 0,
      days: (json['days'] as num?)?.toInt() ?? 7,
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      unlocked: unlocked,
    );
  }
}

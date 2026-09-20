/// 채팅 이모티콘 이용권 상태. (#2020)
///
/// 남은 시간은 서버가 준 **초**에서 센다. 만료 시각만 받아 기기 시계와 빼면,
/// 시계가 틀어진 기기에서 남은 시간이 엉뚱하게 보이거나 이미 끝난 것으로 보인다.
library;

class EmoteState {
  const EmoteState({
    required this.cost,
    required this.hours,
    required this.balance,
    this.remaining,
    this.expiresAt,
  });

  /// 이용권 값(포인트).
  final int cost;

  /// 한 번 사면 쓸 수 있는 시간.
  final int hours;

  /// 지금 포인트 잔액.
  final int balance;

  /// 남은 시간. 이용권이 없으면 null.
  final Duration? remaining;
  final DateTime? expiresAt;

  bool get active => remaining != null && remaining! > Duration.zero;

  /// 지금 살 수 있는가 — 이용 중이 아니고 잔액이 된다.
  bool get canBuy => !active && balance >= cost;

  /// 모자란 포인트. 모자라지 않으면 0.
  int get shortfall => balance >= cost ? 0 : cost - balance;

  /// 1초가 지난 상태. 화면의 남은 시간을 서버에 다시 묻지 않고 센다.
  EmoteState tick(Duration elapsed) {
    final Duration? left = remaining;
    if (left == null) return this;
    final Duration next = left - elapsed;
    return EmoteState(
      cost: cost,
      hours: hours,
      balance: balance,
      remaining: next > Duration.zero ? next : null,
      expiresAt: expiresAt,
    );
  }

  factory EmoteState.fromJson(Map<String, Object?> json) {
    final Object? pass = json['pass'];
    Duration? remaining;
    DateTime? expiresAt;
    if (pass is Map<String, Object?>) {
      final int seconds = (pass['remaining_seconds'] as num?)?.toInt() ?? 0;
      if (seconds > 0) remaining = Duration(seconds: seconds);
      expiresAt = DateTime.tryParse((pass['expires_at'] as String?) ?? '');
    }
    return EmoteState(
      cost: (json['cost'] as num?)?.toInt() ?? 0,
      hours: (json['hours'] as num?)?.toInt() ?? 24,
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      remaining: remaining,
      expiresAt: expiresAt,
    );
  }
}

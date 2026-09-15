/// 연속 기록 보호권 — 운동 현황의 `보호권 쓰기` 상태와 내 혜택의 보유·사용한 날. (#1788)
///
/// 보호할 수 있는 날인지는 서버(`GET /exercise/weeks/current` 의 `streak_shield`)가
/// 정한다. 앱이 "어제 기록이 없고 보호권이 있다" 를 따로 계산하면, 월요일처럼 규칙이
/// 더 붙는 날에 화면만 옛 규칙으로 버튼을 띄운다.
library;

/// `YYYY-MM-DD` 를 그 날짜(시각 없음)로 읽는다. 읽지 못하면 null.
DateTime? _dateFrom(Object? raw) {
  final DateTime? parsed = raw is String ? DateTime.tryParse(raw) : null;
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// 운동 주간 응답의 보호권 상태 — **이번 주** 조회에만 온다.
class StreakShieldWeekState {
  const StreakShieldWeekState({required this.held, this.protectableDate});

  /// 쓰지 않은 보호권 수.
  final int held;

  /// 지금 보호할 수 있는 날(어제). null 이면 `보호권 쓰기` 를 띄우지 않는다.
  final DateTime? protectableDate;

  /// 이 필드가 없는 응답(지난 주·옛 서버)은 null 이다.
  static StreakShieldWeekState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, Object?> json = raw.cast<String, Object?>();
    return StreakShieldWeekState(
      held: (json['held'] as num?)?.toInt() ?? 0,
      protectableDate: _dateFrom(json['protectable_date']),
    );
  }
}

/// 보호권으로 이어 붙인 날 하나.
class StreakShieldUse {
  const StreakShieldUse({required this.date, this.usedAt});

  final DateTime date;
  final DateTime? usedAt;
}

/// `GET /me/streak-shields` — 쓰지 않은 보호권 수와 보호한 날(최근 먼저).
class StreakShields {
  const StreakShields({
    required this.held,
    required this.maxHeld,
    required this.cost,
    this.used = const <StreakShieldUse>[],
  });

  final int held;
  final int maxHeld;
  final int cost;
  final List<StreakShieldUse> used;

  factory StreakShields.fromJson(Map<String, Object?> json) => StreakShields(
    held: (json['held'] as num?)?.toInt() ?? 0,
    maxHeld: (json['max_held'] as num?)?.toInt() ?? 0,
    cost: (json['cost'] as num?)?.toInt() ?? 0,
    used: <StreakShieldUse>[
      for (final Object? raw in (json['used'] as List<Object?>?) ?? <Object?>[])
        if (raw is Map && _dateFrom(raw['date']) != null)
          StreakShieldUse(
            date: _dateFrom(raw['date'])!,
            usedAt: DateTime.tryParse((raw['used_at'] as String?) ?? ''),
          ),
    ],
  );
}

/// 연속 기록 보호권 — 보유 개수·보호한 날·기록 연속. (#1788)
///
/// 보호권이 지키는 **기록 연속**은 식단 한 끼든 운동 한 건이든 남긴 날이 이어진
/// 길이다. 운동 탭의 `N일 연속 운동` 과는 다른 값이라 운동 주간 응답에는 실리지
/// 않는다. 보호할 수 있는 날인지도 서버가 정한다 — 앱이 "어제 기록이 없고
/// 보호권이 있다" 를 따로 계산하면 화면만 옛 규칙으로 버튼을 띄운다.
library;

/// `YYYY-MM-DD` 를 그 날짜(시각 없음)로 읽는다. 읽지 못하면 null.
DateTime? _dateFrom(Object? raw) {
  final DateTime? parsed = raw is String ? DateTime.tryParse(raw) : null;
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// 보호권으로 이어 붙인 날 하나.
class StreakShieldUse {
  const StreakShieldUse({required this.date, this.usedAt});

  final DateTime date;
  final DateTime? usedAt;
}

/// `GET /me/streak-shields` — 보유 수·보호한 날(최근 먼저)·기록 연속.
class StreakShields {
  const StreakShields({
    required this.held,
    required this.maxHeld,
    required this.cost,
    this.used = const <StreakShieldUse>[],
    this.recordStreakDays = 0,
    this.protectableFrom,
    this.protectableTo,
  });

  final int held;
  final int maxHeld;
  final int cost;
  final List<StreakShieldUse> used;

  /// 식단이든 운동이든 기록한 날이 이어진 길이(보호한 날 포함).
  final int recordStreakDays;

  /// 지금 보호권을 쓸 수 있는 날의 구간(양끝 포함) — 어제부터 거슬러 30일.
  /// 보호권이 없으면 둘 다 null 이다. 어느 날이 실제로 비었는지는 기록 그래프
  /// (`ActivityCalendar`)이 말한다.
  final DateTime? protectableFrom;
  final DateTime? protectableTo;

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
    recordStreakDays: (json['record_streak_days'] as num?)?.toInt() ?? 0,
    protectableFrom: _dateFrom(json['protectable_from']),
    protectableTo: _dateFrom(json['protectable_to']),
  );
}

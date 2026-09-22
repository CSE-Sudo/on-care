/// 포인트로 받은 주간 리포트. (#2022)
///
/// 서버(`GET /me/weekly-reports`)는 **어느 주를 샀는지**만 들고 있다. 리포트 내용은
/// 앱이 회원 기록으로 세운다 — 트레이너가 채팅으로 등록한 리포트를 여는 방식과 같다.
library;

class WeeklyReportPurchases {
  const WeeklyReportPurchases({
    required this.weeks,
    required this.nextWeekStart,
    required this.cost,
  });

  /// 산 주의 월요일. 최근 주 먼저다.
  final List<DateTime> weeks;

  /// 지금 교환하면 받는 주의 월요일(지난주).
  final DateTime nextWeekStart;
  final int cost;

  factory WeeklyReportPurchases.fromJson(Map<String, Object?> json) =>
      WeeklyReportPurchases(
        weeks: <DateTime>[
          for (final Object? raw
              in (json['reports'] as List<Object?>?) ?? const <Object?>[])
            if (raw is Map) ?_day((raw.cast<String, Object?>())['week_start']),
        ],
        nextWeekStart: _day(json['next_week_start']) ?? DateTime(1970),
        cost: (json['cost'] as num?)?.toInt() ?? 0,
      );

  /// `YYYY-MM-DD` 를 날짜(0시)로. 모르는 값은 null.
  static DateTime? _day(Object? raw) {
    final DateTime? parsed = DateTime.tryParse(raw is String ? raw : '');
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }
}

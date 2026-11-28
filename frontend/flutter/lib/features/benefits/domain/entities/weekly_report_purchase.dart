/// 포인트로 받은 주간 리포트. (#2022)
///
/// 리포트는 앱이 세운다 — 트레이너가 채팅으로 등록한 리포트를 여는 방식과 같다.
/// 재료는 **살 때의 값**이다(#3349): 그 주의 수치는 서버가 굳혀 두었다가 리포트
/// 조회로 주고, 감지 기록은 이 목록(`GET /me/weekly-reports`)에 실려 온다.
library;

import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';

class WeeklyReportPurchases {
  const WeeklyReportPurchases({
    required this.weeks,
    required this.nextWeekStart,
    required this.cost,
    this.insights = const <DateTime, List<ChatInsightRecord>>{},
  });

  /// 산 주의 월요일. 최근 주 먼저다.
  final List<DateTime> weeks;

  /// 지금 교환하면 받는 주의 월요일(지난주).
  final DateTime nextWeekStart;
  final int cost;

  /// 주(월요일) → 살 때 그 주에 있던 감지 기록. (#3349)
  ///
  /// 감지가 없던 주는 빈 목록이고, **키가 없는 주는 남겨 둔 것이 없는 주**다
  /// (#3349 전에 산 리포트). 둘을 섞으면 옛 리포트가 "감지된 것이 없어요" 로
  /// 열린다 — [insightsOf] 로 읽는다.
  final Map<DateTime, List<ChatInsightRecord>> insights;

  /// [week] 를 살 때의 감지 기록. 남겨 둔 것이 없으면 null.
  List<ChatInsightRecord>? insightsOf(DateTime week) =>
      insights[DateTime(week.year, week.month, week.day)];

  factory WeeklyReportPurchases.fromJson(Map<String, Object?> json) {
    final List<DateTime> weeks = <DateTime>[];
    final Map<DateTime, List<ChatInsightRecord>> insights =
        <DateTime, List<ChatInsightRecord>>{};
    for (final Object? raw
        in (json['reports'] as List<Object?>?) ?? const <Object?>[]) {
      if (raw is! Map) continue;
      final Map<String, Object?> row = raw.cast<String, Object?>();
      final DateTime? week = _day(row['week_start']);
      if (week == null) continue;
      weeks.add(week);
      final Object? kept = row['insights'];
      // 목록이 아니면(null·옛 서버) 남겨 둔 것이 없는 주다.
      if (kept is! List) continue;
      insights[week] = <ChatInsightRecord>[
        for (final Object? item in kept)
          if (item is Map)
            ?ChatInsightRecord.fromJson(item.cast<String, Object?>()),
      ];
    }
    return WeeklyReportPurchases(
      weeks: weeks,
      nextWeekStart: _day(json['next_week_start']) ?? DateTime(1970),
      cost: (json['cost'] as num?)?.toInt() ?? 0,
      insights: insights,
    );
  }

  /// `YYYY-MM-DD` 를 날짜(0시)로. 모르는 값은 null.
  static DateTime? _day(Object? raw) {
    final DateTime? parsed = DateTime.tryParse(raw is String ? raw : '');
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }
}

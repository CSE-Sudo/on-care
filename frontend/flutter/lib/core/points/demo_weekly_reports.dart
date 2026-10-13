import 'package:oncare/core/points/demo_benefits_store.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 데모의 포인트로 받는 주간 리포트. 서버 `weekly_report_purchase_service` 의 대역이다.
/// (#2022)
///
/// 규칙은 서버와 같다:
/// - 담당 트레이너가 **없는** 회원만 산다. 담당이 있으면 사용처 목록에서 빠지고 교환도
///   막힌다.
/// - 사는 주는 지난주(가장 최근에 끝난 월~일)이고, 같은 주는 한 번만 산다.
/// - 리포트는 앱이 세운다. 살 때 그 주에 있던 감지 기록을 함께 남긴다(#3349) —
///   데모의 수치는 날마다 같은 픽스처라 굳힐 것이 없다.
///
/// 담당 여부는 쿠폰 원장이 들고 있는 값을 본다 — 데모에서 트레이너를 해제하면 그
/// 자리에서 항목이 열린다.
///
/// 받은 주는 쿠폰 원장의 구획에 함께 실려 새로고침 뒤에도 남는다(#2664).
class DemoWeeklyReportBook implements DemoPersistable {
  DemoWeeklyReportBook({
    required DemoPointsLedger ledger,
    required DateTime Function() now,
    required bool Function() hasTrainer,
  }) : _ledger = ledger,
       _now = now,
       _hasTrainer = hasTrainer;

  static const String itemId = 'weekly_report';
  static const int cost = 300;

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  final bool Function() _hasTrainer;
  final List<DateTime> _weeks = <DateTime>[];

  /// 주(월요일) → 받은 시각. 목록의 `purchased_at` 이다.
  final Map<DateTime, DateTime> _purchasedAt = <DateTime, DateTime>{};
  final Map<String, DateTime> _requests = <String, DateTime>{};

  /// 주(월요일) → 살 때 그 주에 있던 감지 기록(`{kind, body_part, created_at}`).
  /// 키가 없는 주는 남겨 둔 것이 없다(#3349 전에 받은 데모 기록) — 목록에 null 로
  /// 나간다.
  final Map<DateTime, List<Map<String, Object?>>> _insights =
      <DateTime, List<Map<String, Object?>>>{};
  int _sequence = 0;

  @override
  void Function()? onChanged;

  /// 지금 교환하면 받는 주 — 지난주 월요일.
  DateTime get targetWeek {
    final DateTime now = _now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return DateTime(today.year, today.month, today.day - today.weekday + 1 - 7);
  }

  /// 사용처에 항목을 싣는가 — 담당이 없을 때만.
  bool get listed => !_hasTrainer();

  /// 지난주를 이미 받았는가.
  bool get targetOwned => _weeks.contains(targetWeek);

  /// `GET /me/weekly-reports`.
  Map<String, Object?> listJson() {
    final List<DateTime> weeks = List<DateTime>.of(_weeks)
      ..sort((DateTime a, DateTime b) => b.compareTo(a));
    return <String, Object?>{
      'reports': <Map<String, Object?>>[
        for (final DateTime week in weeks)
          <String, Object?>{
            'week_start': wireDate(week),
            'purchased_at': (_purchasedAt[week] ?? _now()).toIso8601String(),
            'insights': _insights[week],
          },
      ],
      'next_week_start': wireDate(targetWeek),
      'cost': cost,
    };
  }

  /// `POST /me/points/exchange` 의 `item: weekly_report`.
  ///
  /// [insights] 는 지금의 감지 기록(`GET /ai-coach/insights` 의 줄들)이다. 그중
  /// 받는 주의 것만 남긴다 — 실서버가 살 때 굳히는 것과 같다(#3349).
  DemoCouponResult exchange({
    String? clientRequestId,
    List<Map<String, Object?>> insights = const <Map<String, Object?>>[],
  }) {
    if (clientRequestId != null && _requests.containsKey(clientRequestId)) {
      return DemoCouponResult(201, _exchangeJson(_requests[clientRequestId]!));
    }
    if (_hasTrainer()) return _error(409, '담당 트레이너가 주간 리포트를 보내 줘요.');
    final DateTime week = targetWeek;
    if (_weeks.contains(week)) return _error(409, '이 주의 리포트는 이미 받았어요.');
    final int shortfall = cost - _ledger.balance;
    if (shortfall > 0) return _error(409, '포인트가 ${shortfall}P 부족해요.');
    if (!_ledger.spend(
      'weekly-report-demo-${++_sequence}',
      cost,
      reason: itemId,
    )) {
      return _error(409, '포인트가 부족해요.');
    }
    _weeks.add(week);
    _purchasedAt[week] = _now();
    _insights[week] = _insightsOf(week, insights);
    if (clientRequestId != null) _requests[clientRequestId] = week;
    onChanged?.call();
    return DemoCouponResult(201, _exchangeJson(week));
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': _sequence,
    'weeks': <Map<String, Object?>>[
      for (final DateTime week in _weeks)
        <String, Object?>{
          'week_start': week.toIso8601String(),
          'purchased_at': _purchasedAt[week]?.toIso8601String(),
          'insights': _insights[week],
        },
    ],
  };

  @override
  void restore(Map<String, Object?> json) {
    _sequence = (json['sequence'] as num?)?.toInt() ?? 0;
    _weeks.clear();
    _purchasedAt.clear();
    _insights.clear();
    for (final Map<String, Object?> row in demoRows(json['weeks'])) {
      final DateTime week = demoParseTime(row['week_start']);
      _weeks.add(week);
      final DateTime? at = demoParseTimeOrNull(row['purchased_at']);
      if (at != null) _purchasedAt[week] = at;
      final Object? kept = row['insights'];
      if (kept is List) _insights[week] = demoRows(kept);
    }
  }

  /// [rows] 에서 [week] 주(월~일)의 감지만, 오래된 것 먼저. 회원의 문장은 뺀다.
  static List<Map<String, Object?>> _insightsOf(
    DateTime week,
    List<Map<String, Object?>> rows,
  ) {
    final DateTime nextWeek = DateTime(week.year, week.month, week.day + 7);
    final List<(DateTime, Map<String, Object?>)> inWeek =
        <(DateTime, Map<String, Object?>)>[
          for (final Map<String, Object?> row in rows)
            if (DateTime.tryParse(row['created_at'] as String? ?? '')
                case final DateTime at
                when !toKst(at).isBefore(week) && toKst(at).isBefore(nextWeek))
              (toKst(at), row),
        ]..sort(
          (
            (DateTime, Map<String, Object?>) a,
            (DateTime, Map<String, Object?>) b,
          ) => a.$1.compareTo(b.$1),
        );
    return <Map<String, Object?>>[
      for (final (DateTime _, Map<String, Object?> row) in inWeek)
        <String, Object?>{
          'kind': row['kind'],
          'body_part': row['body_part'],
          'created_at': row['created_at'],
        },
    ];
  }

  Map<String, Object?> _exchangeJson(DateTime week) => <String, Object?>{
    'coupon': null,
    'weekly_report_week': wireDate(week),
    'spent': cost,
    'balance': _ledger.balance,
  };

  static DemoCouponResult _error(int status, String detail) =>
      DemoCouponResult(status, <String, Object?>{'detail': detail});
}

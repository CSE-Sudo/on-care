import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';

/// 데모의 포인트로 받는 주간 리포트. 서버 `weekly_report_purchase_service` 의 대역이다.
/// (#2022)
///
/// 규칙은 서버와 같다:
/// - 담당 트레이너가 **없는** 회원만 산다. 담당이 있으면 사용처 목록에서 빠지고 교환도
///   막힌다.
/// - 사는 주는 지난주(가장 최근에 끝난 월~일)이고, 같은 주는 한 번만 산다.
/// - 어느 주를 샀는지만 들고 있다. 리포트 내용은 앱이 회원 기록으로 세운다.
///
/// 담당 여부는 쿠폰 원장이 들고 있는 값을 본다 — 데모에서 트레이너를 해제하면 그
/// 자리에서 항목이 열린다.
class DemoWeeklyReportBook {
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
  final Map<String, DateTime> _requests = <String, DateTime>{};
  int _sequence = 0;

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
            'week_start': _ymd(week),
            'purchased_at': _now().toIso8601String(),
          },
      ],
      'next_week_start': _ymd(targetWeek),
      'cost': cost,
    };
  }

  /// `POST /me/points/exchange` 의 `item: weekly_report`.
  DemoCouponResult exchange({String? clientRequestId}) {
    if (clientRequestId != null && _requests.containsKey(clientRequestId)) {
      return DemoCouponResult(201, _exchangeJson(_requests[clientRequestId]!));
    }
    if (_hasTrainer()) return _error(409, '담당 트레이너가 리포트를 등록해 줘요.');
    final DateTime week = targetWeek;
    if (_weeks.contains(week)) return _error(409, '이 주의 리포트는 이미 받았어요.');
    final int shortfall = cost - _ledger.balance;
    if (shortfall > 0) return _error(409, '포인트가 ${shortfall}P 부족해요.');
    if (!_ledger.spend('weekly-report-demo-${++_sequence}', cost)) {
      return _error(409, '포인트가 부족해요.');
    }
    _weeks.add(week);
    if (clientRequestId != null) _requests[clientRequestId] = week;
    return DemoCouponResult(201, _exchangeJson(week));
  }

  Map<String, Object?> _exchangeJson(DateTime week) => <String, Object?>{
    'coupon': null,
    'weekly_report_week': _ymd(week),
    'spent': cost,
    'balance': _ledger.balance,
  };

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DemoCouponResult _error(int status, String detail) =>
      DemoCouponResult(status, <String, Object?>{'detail': detail});
}

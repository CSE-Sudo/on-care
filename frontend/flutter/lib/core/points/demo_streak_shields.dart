import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';

/// 목업 API 의 연속 기록 보호권. 서버 `streak_shield_service` 의 대역이다. (#1788)
///
/// 규칙은 서버와 같다:
/// - 교환 300P. 쓰지 않은 보호권은 최대 2개.
/// - 보호할 수 있는 날은 **어제** 하나. 어제가 지난주(오늘이 월요일)면 안 된다 —
///   연속 기록은 이번 주 안에서 세므로 이어지지 않는다. 운동 기록이 있는 날은
///   보호하지 않고, 하루에 보호는 한 번. 가장 먼저 교환한 보호권부터 쓴다.
/// - 같은 날을 다시 보호하면 보호권을 더 쓰지 않고 같은 응답이다.
///
/// 운동 기록은 이 원장이 들고 있지 않다. 데모에서 기록을 가진 곳(목업 운동 저장소,
/// 로컬 목업 API 의 drift)이 그날 기록이 있는지를 `hasExerciseOn` 으로 알려 준다.
class DemoStreakShieldBook {
  DemoStreakShieldBook({
    required DemoPointsLedger ledger,
    DateTime Function()? now,
  }) : _ledger = ledger,
       _now = now ?? nowKst;

  /// 포인트 사용처의 항목 id·가격·최대 보유 수 — 서버와 같은 값이다.
  static const String itemId = 'streak_shield';
  static const int cost = 300;
  static const int maxHeld = 2;

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  final List<_DemoShield> _shields = <_DemoShield>[];
  int _sequence = 0;

  /// 쓰지 않은 보호권 수.
  int get held => _shields.where((_DemoShield s) => s.protectedOn == null).length;

  /// 사용처 카드의 막힌 이유. 보유 한도가 잔액 부족보다 먼저다(서버와 같은 순서).
  String? blockReason(int balance) {
    if (held >= maxHeld) return 'shield_limit';
    if (balance < cost) return 'insufficient_points';
    return null;
  }

  /// `POST /me/points/exchange` 의 `item: streak_shield`.
  DemoCouponResult exchange({String? clientRequestId}) {
    if (clientRequestId != null) {
      final _DemoShield? existing = _shields
          .where((_DemoShield s) => s.clientRequestId == clientRequestId)
          .firstOrNull;
      if (existing != null) return DemoCouponResult(201, _exchangeJson(existing));
    }
    if (held >= maxHeld) {
      return _error(409, '보호권은 최대 $maxHeld개까지 가질 수 있어요.');
    }
    final int shortfall = cost - _ledger.balance;
    if (shortfall > 0) return _error(409, '포인트가 ${shortfall}P 부족해요.');
    final _DemoShield shield = _DemoShield(
      id: 'shd-demo-${++_sequence}',
      acquiredAt: _now(),
      clientRequestId: clientRequestId,
    );
    if (!_ledger.spend(shield.id, cost)) return _error(409, '포인트가 부족해요.');
    _shields.add(shield);
    return DemoCouponResult(201, _exchangeJson(shield));
  }

  /// `GET /me/streak-shields`.
  Map<String, Object?> statusJson() {
    final List<_DemoShield> used =
        _shields.where((_DemoShield s) => s.protectedOn != null).toList()
          ..sort((_DemoShield a, _DemoShield b) => b.protectedOn!.compareTo(a.protectedOn!));
    return <String, Object?>{
      'held': held,
      'max_held': maxHeld,
      'cost': cost,
      'used': <Map<String, Object?>>[
        for (final _DemoShield s in used)
          <String, Object?>{
            'date': _ymd(s.protectedOn!),
            'used_at': s.usedAt?.toIso8601String(),
          },
      ],
    };
  }

  /// 운동 주간 응답의 `streak_shield` — 이번 주를 볼 때만 싣는다.
  Map<String, Object?> weekStateJson(bool Function(DateTime day) hasExerciseOn) {
    final DateTime yesterday = _yesterday();
    return <String, Object?>{
      'held': held,
      'protectable_date':
          held > 0 && _blockReason(yesterday, hasExerciseOn) == null
          ? _ymd(yesterday)
          : null,
    };
  }

  /// [monday] 주의 요일별 보호 여부 — 월=0 … 일=6.
  List<bool> protectedDaysOf(DateTime monday) => <bool>[
    for (int i = 0; i < 7; i++)
      isProtected(DateTime(monday.year, monday.month, monday.day + i)),
  ];

  bool isProtected(DateTime day) {
    final DateTime d = _dateOnly(day);
    return _shields.any((_DemoShield s) => s.protectedOn == d);
  }

  /// `POST /me/streak-shields/use`.
  DemoCouponResult use(
    DateTime day, {
    required bool Function(DateTime day) hasExerciseOn,
  }) {
    final DateTime d = _dateOnly(day);
    if (isProtected(d)) return DemoCouponResult(200, statusJson());
    final String? blocked = _blockReason(d, hasExerciseOn);
    if (blocked != null) return _error(409, blocked);
    final _DemoShield? shield = _shields
        .where((_DemoShield s) => s.protectedOn == null)
        .firstOrNull;
    if (shield == null) return _error(409, '보호권이 없어요.');
    shield
      ..protectedOn = d
      ..usedAt = _now();
    return DemoCouponResult(200, statusJson());
  }

  /// [day] 에 운동 기록이 생겼다 — 그날 쓴 보호권을 되돌린다. 되돌렸으면 true.
  ///
  /// 서버 `refund_for_exercise` 와 같다. 멱등이고, 보유 한도(2개)는 교환의 규칙이라
  /// 여기서는 보지 않는다 — 되돌려 받아 3개가 될 수 있고, 그동안은 교환이 막힌다.
  /// 되돌린 뒤 그 기록을 지워도 보호는 다시 걸리지 않는다.
  bool refundFor(DateTime day) {
    final DateTime d = _dateOnly(day);
    final _DemoShield? shield = _shields
        .where((_DemoShield s) => s.protectedOn == d)
        .firstOrNull;
    if (shield == null) return false;
    shield
      ..protectedOn = null
      ..usedAt = null;
    return true;
  }

  // ---- 내부 ----

  /// 보호할 수 없는 이유(문구). 보유 수는 보지 않는다.
  String? _blockReason(DateTime day, bool Function(DateTime day) hasExerciseOn) {
    final DateTime today = _dateOnly(_now());
    if (day != _yesterday()) return '어제만 보호할 수 있어요.';
    if (_monday(day) != _monday(today)) {
      return '지난주 날짜는 이번 주 연속 기록에 이어지지 않아요.';
    }
    if (isProtected(day)) return '이미 보호한 날이에요.';
    if (hasExerciseOn(day)) return '운동 기록이 있는 날은 보호하지 않아도 돼요.';
    return null;
  }

  DateTime _yesterday() {
    final DateTime today = _dateOnly(_now());
    return DateTime(today.year, today.month, today.day - 1);
  }

  Map<String, Object?> _exchangeJson(_DemoShield shield) => <String, Object?>{
    'coupon': null,
    'shield': <String, Object?>{
      'id': shield.id,
      'cost': cost,
      'status': shield.protectedOn == null ? 'held' : 'used',
      'acquired_at': shield.acquiredAt.toIso8601String(),
      'protected_on': shield.protectedOn == null
          ? null
          : _ymd(shield.protectedOn!),
      'used_at': shield.usedAt?.toIso8601String(),
    },
    'spent': cost,
    'balance': _ledger.balance,
  };

  static DemoCouponResult _error(int status, String detail) =>
      DemoCouponResult(status, <String, Object?>{'detail': detail});

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _monday(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static String _ymd(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

class _DemoShield {
  _DemoShield({required this.id, required this.acquiredAt, this.clientRequestId});

  final String id;
  final DateTime acquiredAt;
  final String? clientRequestId;

  /// 보호한 날. 쓰지 않았으면 null.
  DateTime? protectedOn;
  DateTime? usedAt;
}

/// 목업 경로가 함께 쓰는 보호권 원장 하나 — 목업 API(사용처 교환)와 목업 운동
/// 저장소(연속 일수·`보호권 쓰기`)가 같은 인스턴스를 본다. 포인트는
/// [demoPointsLedgerProvider] 에서 빠진다.
final demoStreakShieldBookProvider = Provider<DemoStreakShieldBook>(
  (ref) => DemoStreakShieldBook(ledger: ref.watch(demoPointsLedgerProvider)),
  name: 'demoStreakShieldBook',
);

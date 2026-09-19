import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';

/// 목업 API 의 연속 기록 보호권. 서버 `streak_shield_service` 의 대역이다. (#1788)
///
/// 보호권이 지키는 것은 **기록 연속**이다: 식단 한 끼든 운동 한 건이든 남긴 날이
/// 이어진 길이. 운동 탭의 `N일 연속 운동` 과는 다른 값이고, 보호한 날은 그쪽에
/// 들어가지 않는다.
///
/// 규칙은 서버와 같다:
/// - 교환 300P. 쓰지 않은 보호권은 최대 4개.
/// - 보호할 수 있는 날은 **어제** 하나. 식단이든 운동이든 기록이 있는 날은
///   보호하지 않고, 하루에 보호는 한 번. 가장 먼저 교환한 보호권부터 쓴다.
///   기록 연속은 주 단위가 아니라 날짜를 거슬러 이어지므로 월요일에도 어제를
///   보호할 수 있다.
/// - 같은 날을 다시 보호하면 보호권을 더 쓰지 않고 같은 응답이다.
///
/// 기록은 이 원장이 들고 있지 않다. 데모에서 기록을 가진 곳(목업 저장소, 로컬
/// 목업 API 의 drift)이 그날 기록이 있는지를 `hasRecordOn` 으로 알려 준다.
class DemoStreakShieldBook {
  DemoStreakShieldBook({
    required DemoPointsLedger ledger,
    DateTime Function()? now,
  }) : _ledger = ledger,
       _now = now ?? nowKst;

  /// 포인트 사용처의 항목 id·가격·최대 보유 수 — 서버와 같은 값이다.
  static const String itemId = 'streak_shield';
  static const int cost = 300;
  static const int maxHeld = 4;

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

  /// `GET /me/streak-shields` — 보유·보호한 날·기록 연속·보호할 수 있는 날.
  ///
  /// [hasRecordOn] 은 그날 식단이나 운동 기록이 있는지다. 주지 않으면 기록 연속은
  /// 보호한 날만 세고 보호할 수 있는 날은 비운다(기록을 모르면 판단하지 않는다).
  Map<String, Object?> statusJson({bool Function(DateTime day)? hasRecordOn}) {
    final List<_DemoShield> used =
        _shields.where((_DemoShield s) => s.protectedOn != null).toList()
          ..sort((_DemoShield a, _DemoShield b) => b.protectedOn!.compareTo(a.protectedOn!));
    final DateTime yesterday = _yesterday();
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
      'record_streak_days': hasRecordOn == null
          ? 0
          : recordStreakDays(hasRecordOn),
      'protectable_date':
          hasRecordOn != null &&
              held > 0 &&
              _blockReason(yesterday, hasRecordOn) == null
          ? _ymd(yesterday)
          : null,
    };
  }

  /// 오늘부터 거슬러 올라가며 이어진 기록 일수. 보호한 날도 기록한 날로 센다.
  ///
  /// 오늘이 비어 있으면 어제부터 센다 — 자정이 지나는 순간 어제까지 쌓은 연속이
  /// 0 으로 보이지 않게 한다. 서버 `record_activity.record_streak_days` 와 같다.
  int recordStreakDays(bool Function(DateTime day) hasRecordOn, {int limit = 365}) {
    bool recorded(DateTime day) => isProtected(day) || hasRecordOn(day);
    final DateTime today = _dateOnly(_now());
    DateTime cursor = recorded(today)
        ? today
        : DateTime(today.year, today.month, today.day - 1);
    int count = 0;
    while (count < limit && recorded(cursor)) {
      count += 1;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return count;
  }

  bool isProtected(DateTime day) {
    final DateTime d = _dateOnly(day);
    return _shields.any((_DemoShield s) => s.protectedOn == d);
  }

  /// `POST /me/streak-shields/use`.
  DemoCouponResult use(
    DateTime day, {
    required bool Function(DateTime day) hasRecordOn,
  }) {
    final DateTime d = _dateOnly(day);
    if (isProtected(d)) {
      return DemoCouponResult(200, statusJson(hasRecordOn: hasRecordOn));
    }
    final String? blocked = _blockReason(d, hasRecordOn);
    if (blocked != null) return _error(409, blocked);
    final _DemoShield? shield = _shields
        .where((_DemoShield s) => s.protectedOn == null)
        .firstOrNull;
    if (shield == null) return _error(409, '보호권이 없어요.');
    shield
      ..protectedOn = d
      ..usedAt = _now();
    return DemoCouponResult(200, statusJson(hasRecordOn: hasRecordOn));
  }

  /// [day] 에 기록(식단·운동)이 생겼다 — 그날 쓴 보호권을 되돌린다. 되돌렸으면 true.
  ///
  /// 서버 `refund_for_record` 와 같다. 멱등이고, 보유 한도(2개)는 교환의 규칙이라
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
  String? _blockReason(DateTime day, bool Function(DateTime day) hasRecordOn) {
    if (day != _yesterday()) return '어제만 보호할 수 있어요.';
    if (isProtected(day)) return '이미 보호한 날이에요.';
    if (hasRecordOn(day)) return '기록이 있는 날은 보호하지 않아도 돼요.';
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

/// 목업 경로가 함께 쓰는 보호권 원장 하나 — 목업 API(사용처 교환·보호권 조회)와
/// 목업 저장소(보호한 날 되돌리기)가 같은 인스턴스를 본다. 포인트는
/// [demoPointsLedgerProvider] 에서 빠진다.
final demoStreakShieldBookProvider = Provider<DemoStreakShieldBook>(
  (ref) => DemoStreakShieldBook(ledger: ref.watch(demoPointsLedgerProvider)),
  name: 'demoStreakShieldBook',
);

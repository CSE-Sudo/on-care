import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';

/// 목업 API 의 포인트 사용처·쿠폰. 서버 `points_coupon_service` 의 대역이다. (#1787)
///
/// 규칙은 서버와 같다:
/// - PT 재등록 할인 쿠폰(5000P)은 담당 트레이너가 있어야 교환하고, 사용하지 않은
///   쿠폰은 한 장뿐이다. 건강식·보충제 쿠폰(각 1000P)도 종류마다 사용하지 않은
///   쿠폰은 한 장뿐이고, 회원이 사용 처리한다.
/// - 쓸 수 있는 마지막 날은 교환일 + 30일. 지나면 만료되고 포인트는 돌려주지 않는다.
/// - 사용 처리는 한 번뿐이고 다시 누르면 같은 응답이다.
/// - 담당 트레이너 연결이 끊기면([endTrainerLink]) 사용 가능한 재등록 쿠폰을 취소하고
///   포인트를 돌려준다.
///
/// 만료 3일 전 알림은 목업에 없다 — 데모에서 교환한 쿠폰은 30일 뒤에야 그 창에
/// 들어가고, 목업 알림함은 이 원장과 따로 논다.
///
/// 모든 쿠폰을 회원 휴대폰에서 사용 처리한다 — PT 재등록 쿠폰도 트레이너·헬스장
/// 직원이 확인한 뒤 회원 화면의 `사용 완료` 를 누른다.
class DemoCouponBook {
  DemoCouponBook({
    required DemoPointsLedger ledger,
    DateTime Function()? now,
    math.Random? random,
    bool hasTrainer = true,
  }) : _ledger = ledger,
       _now = now ?? nowKst,
       _random = random ?? math.Random(),
       _hasTrainer = hasTrainer;

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  final math.Random _random;
  bool _hasTrainer;
  int _sequence = 0;

  final List<_DemoCoupon> _coupons = <_DemoCoupon>[];

  /// 데모 회원(김민수)에게 담당 트레이너가 있는가. 목업 헬스장 저장소의 연결과 같다.
  bool get hasTrainer => _hasTrainer;

  /// 담당 트레이너 연결이 끊겼다 — 재등록 쿠폰을 취소하고 포인트를 돌려준다.
  ///
  /// 목업 헬스장 저장소가 헬스장·트레이너 해제에서 부른다.
  void endTrainerLink() {
    _hasTrainer = false;
    final DateTime today = _today();
    for (final _DemoCoupon coupon in _coupons) {
      if (coupon.item != kDemoPtRenewal.id || coupon.status != 'issued') {
        continue;
      }
      if (today.isAfter(coupon.lastDay)) {
        coupon.status = 'expired';
        continue;
      }
      coupon
        ..status = 'cancelled'
        ..cancelledAt = _now();
      _ledger.refund(coupon.id);
    }
  }

  /// `GET /me/points/shop`.
  Map<String, Object?> shopJson() {
    _expireStale();
    final int balance = _ledger.balance;
    return <String, Object?>{
      'balance': balance,
      'has_trainer': _hasTrainer,
      'items': <Map<String, Object?>>[
        for (final DemoShopItem item in kDemoShopCatalog)
          _itemJson(item, balance),
      ],
    };
  }

  /// `POST /me/points/exchange`.
  DemoCouponResult exchange(String itemId, {String? clientRequestId}) {
    final DemoShopItem? item = _item(itemId);
    if (item == null) return _error(404, '없는 교환 항목이에요.');
    if (clientRequestId != null) {
      final _DemoCoupon? existing = _coupons
          .where((_DemoCoupon c) => c.clientRequestId == clientRequestId)
          .firstOrNull;
      if (existing != null) return DemoCouponResult(201, _exchangeJson(existing));
    }
    _expireStale();
    if (item.requiresTrainer && !_hasTrainer) {
      return _error(409, '담당 트레이너가 있어야 교환할 수 있어요.');
    }
    if (item.oneActive && _activeOf(item.id) != null) {
      return _error(409, '사용하지 않은 쿠폰이 이미 있어요.');
    }
    final int shortfall = item.cost - _ledger.balance;
    if (shortfall > 0) return _error(409, '포인트가 ${shortfall}P 부족해요.');

    final DateTime today = _today();
    final _DemoCoupon coupon = _DemoCoupon(
      id: 'cpn-demo-${++_sequence}',
      item: item.id,
      cost: item.cost,
      code: _newCode(),
      issuedAt: _now(),
      issuedOn: today,
      lastDay: DateTime(today.year, today.month, today.day + item.validDays),
      trainerName: item.requiresTrainer ? kDemoTrainerName : '',
      gymName: item.requiresTrainer ? kDemoTrainerGym : '',
      clientRequestId: clientRequestId,
    );
    if (!_ledger.spend(coupon.id, item.cost)) {
      return _error(409, '포인트가 부족해요.');
    }
    _coupons.add(coupon);
    return DemoCouponResult(201, _exchangeJson(coupon));
  }

  /// `GET /me/coupons` — 사용 가능한 것 먼저, 그다음 최신순.
  List<Map<String, Object?>> couponsJson() {
    _expireStale();
    final List<_DemoCoupon> ordered = _coupons.reversed.toList()
      ..sort(
        (_DemoCoupon a, _DemoCoupon b) =>
            (a.status == 'issued' ? 0 : 1) - (b.status == 'issued' ? 0 : 1),
      );
    return <Map<String, Object?>>[
      for (final _DemoCoupon coupon in ordered) _couponJson(coupon),
    ];
  }

  /// `POST /me/coupons/{id}/use`.
  DemoCouponResult use(String couponId) {
    _expireStale();
    final _DemoCoupon? coupon = _coupons
        .where((_DemoCoupon c) => c.id == couponId)
        .firstOrNull;
    if (coupon == null) return _error(404, '쿠폰을 찾을 수 없어요.');
    final DemoShopItem? item = _item(coupon.item);
    if (item == null || item.redeemer != 'member') {
      return _error(409, '담당 트레이너가 사용 처리하는 쿠폰이에요.');
    }
    switch (coupon.status) {
      case 'issued':
        coupon
          ..status = 'used'
          ..usedAt = _now();
        return DemoCouponResult(200, _couponJson(coupon));
      case 'used':
        return DemoCouponResult(200, _couponJson(coupon));
      case 'expired':
        return _error(409, '만료된 쿠폰이에요.');
      default:
        return _error(409, '취소된 쿠폰이에요.');
    }
  }

  // ---- 내부 ----

  DateTime _today() {
    final DateTime now = _now();
    return DateTime(now.year, now.month, now.day);
  }

  void _expireStale() {
    final DateTime today = _today();
    for (final _DemoCoupon coupon in _coupons) {
      if (coupon.status == 'issued' && today.isAfter(coupon.lastDay)) {
        coupon.status = 'expired';
      }
    }
  }

  _DemoCoupon? _activeOf(String itemId) => _coupons
      .where((_DemoCoupon c) => c.item == itemId && c.status == 'issued')
      .firstOrNull;

  static DemoShopItem? _item(String itemId) => kDemoShopCatalog
      .where((DemoShopItem item) => item.id == itemId)
      .firstOrNull;

  Map<String, Object?> _itemJson(DemoShopItem item, int balance) {
    final int shortfall = math.max(item.cost - balance, 0);
    final String? blocked = item.requiresTrainer && !_hasTrainer
        ? 'no_trainer'
        : item.oneActive && _activeOf(item.id) != null
        ? 'active_coupon'
        : shortfall > 0
        ? 'insufficient_points'
        : null;
    return <String, Object?>{
      'id': item.id,
      'title': item.title,
      'benefit': item.benefit,
      'description': item.description,
      'cost': item.cost,
      'valid_days': item.validDays,
      'redeemer': item.redeemer,
      'requires_trainer': item.requiresTrainer,
      'available': blocked == null,
      'blocked_reason': blocked,
      'shortfall': shortfall,
    };
  }

  Map<String, Object?> _exchangeJson(_DemoCoupon coupon) => <String, Object?>{
    'coupon': _couponJson(coupon),
    'spent': coupon.cost,
    'balance': _ledger.balance,
  };

  Map<String, Object?> _couponJson(_DemoCoupon coupon) {
    final DemoShopItem? item = _item(coupon.item);
    final bool usable = coupon.status == 'issued';
    final int daysLeft = usable
        ? math.max((coupon.lastDay.difference(_today()).inHours / 24).round(), 0)
        : 0;
    return <String, Object?>{
      'id': coupon.id,
      'item': coupon.item,
      'title': item?.title ?? coupon.item,
      'benefit': item?.benefit ?? coupon.item,
      'cost': coupon.cost,
      'code': coupon.code,
      'status': coupon.status,
      'redeemer': item?.redeemer ?? 'member',
      'trainer_name': coupon.trainerName,
      'gym_name': coupon.gymName,
      'issued_at': coupon.issuedAt.toIso8601String(),
      'issued_on': _ymd(coupon.issuedOn),
      'expires_on': _ymd(coupon.lastDay),
      'days_left': daysLeft,
      'used_at': coupon.usedAt?.toIso8601String(),
      'cancelled_at': coupon.cancelledAt?.toIso8601String(),
    };
  }

  String _newCode() {
    while (true) {
      final String code = String.fromCharCodes(
        List<int>.generate(
          8,
          (_) => _kCodeAlphabet.codeUnitAt(_random.nextInt(_kCodeAlphabet.length)),
        ),
      );
      if (_coupons.every((_DemoCoupon c) => c.code != code)) return code;
    }
  }

  static DemoCouponResult _error(int status, String detail) =>
      DemoCouponResult(status, <String, Object?>{'detail': detail});

  static String _ymd(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

/// 목업 응답 — 상태코드와 본문.
class DemoCouponResult {
  const DemoCouponResult(this.statusCode, this.body);

  final int statusCode;
  final Object? body;
}

/// 교환 항목 하나. 서버 카탈로그(`points_coupon_service.CATALOG`)와 같은 값이다.
class DemoShopItem {
  const DemoShopItem({
    required this.id,
    required this.title,
    required this.benefit,
    required this.description,
    required this.cost,
    required this.validDays,
    required this.redeemer,
    this.requiresTrainer = false,
    this.oneActive = false,
  });

  final String id;
  final String title;
  final String benefit;
  final String description;
  final int cost;
  final int validDays;
  final String redeemer;
  final bool requiresTrainer;
  final bool oneActive;
}

const DemoShopItem kDemoPtRenewal = DemoShopItem(
  id: 'pt_renewal',
  title: 'PT 재등록 할인 쿠폰',
  benefit: 'PT 재등록 10,000원 할인',
  description: '담당 트레이너에게 PT를 다시 등록할 때 10,000원을 할인받아요.',
  cost: 5000,
  validDays: 30,
  // 헬스장에서 직원이 확인한 뒤 회원 휴대폰에서 사용 완료를 누른다.
  redeemer: 'member',
  requiresTrainer: true,
  oneActive: true,
);

const List<DemoShopItem> kDemoShopCatalog = <DemoShopItem>[
  kDemoPtRenewal,
  DemoShopItem(
    id: 'salad_discount',
    title: '샐러드 10% 할인',
    benefit: '샐러드 10% 할인',
    description: '건강식 샐러드를 주문할 때 10% 할인받아요.',
    cost: 1000,
    validDays: 30,
    redeemer: 'member',
    oneActive: true,
  ),
  DemoShopItem(
    id: 'protein_discount',
    title: '프로틴 3,000원 할인',
    benefit: '프로틴 3,000원 할인',
    description: '프로틴 보충제를 살 때 3,000원 할인받아요.',
    cost: 1000,
    validDays: 30,
    redeemer: 'member',
    oneActive: true,
  ),
];

/// 데모 담당 트레이너 — `MockGymRepository` 의 김트레이너·온케어짐 신촌점과 같다.
const String kDemoTrainerName = '김트레이너';
const String kDemoTrainerGym = '온케어짐 신촌점';

/// 코드 글자 — 헷갈리는 0·O·1·I 를 뺐다(서버와 같다).
const String _kCodeAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

class _DemoCoupon {
  _DemoCoupon({
    required this.id,
    required this.item,
    required this.cost,
    required this.code,
    required this.issuedAt,
    required this.issuedOn,
    required this.lastDay,
    required this.trainerName,
    required this.gymName,
    this.clientRequestId,
  });

  final String id;
  final String item;
  final int cost;
  final String code;
  final DateTime issuedAt;
  final DateTime issuedOn;

  /// 쓸 수 있는 마지막 날.
  final DateTime lastDay;
  final String trainerName;
  final String gymName;
  final String? clientRequestId;
  String status = 'issued';
  DateTime? usedAt;
  DateTime? cancelledAt;
}

/// 목업 경로가 함께 쓰는 쿠폰 원장 하나 — 목업 API 와 목업 헬스장 저장소가 같은
/// 인스턴스를 본다. 포인트는 [demoPointsLedgerProvider] 에서 빠진다.
final demoCouponBookProvider = Provider<DemoCouponBook>(
  (ref) => DemoCouponBook(ledger: ref.watch(demoPointsLedgerProvider)),
  name: 'demoCouponBook',
);

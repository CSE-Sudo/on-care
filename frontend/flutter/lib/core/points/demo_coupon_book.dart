import 'dart:math' as math;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_graph_colors.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_profile_pet.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/points/demo_weekly_reports.dart';
import 'package:oncare/core/utils/clock.dart';

/// 목업 API 의 포인트 사용처·쿠폰. 서버 `points_coupon_service` 의 대역이다. (#1787)
///
/// 사용처는 헬스장이 현장에서 주는 혜택이고, 가격은 혜택 1만원 = 7,000P 기준이다.
/// 규칙은 서버와 같다:
/// - PT 재등록 3만원 할인 쿠폰(21,000P)은 담당 트레이너가 있어야 교환하고, 사용하지
///   않은 쿠폰은 한 장뿐이다.
/// - 개인 락커 1개월 무료 쿠폰(7,000P)은 헬스장이 연결돼 있어야 교환하고, 사용하지
///   않은 쿠폰은 한 장뿐이며, 교환은 한 달(KST)에 한 번이다. 취소돼 포인트를
///   돌려받은 쿠폰은 세지 않는다.
/// - 막힌 이유는 담당 없음·헬스장 없음 → 사용하지 않은 같은 쿠폰 → 보호권 최대
///   보유 → 이번 달 교환 → 잔액 부족 순으로 하나만 준다.
/// - 쓸 수 있는 마지막 날은 교환일 + 30일. 지나면 만료되고 포인트는 돌려주지 않는다.
/// - 사용 처리는 한 번뿐이고 다시 누르면 같은 응답이다.
/// - 담당 트레이너 연결이 끊기면([endTrainerLink]) 재등록 쿠폰을, 헬스장 연결이
///   끊기면([endGymLink]) 락커 쿠폰을 취소하고 포인트를 돌려준다.
/// - 분석용 식판(#2150)은 교환 항목이 아니라 달성 보상이다. 서버
///   `diet_tray_service` 와 같이 최근 28일 중 식단 사진을 남긴 날이 20일 이상이고
///   담당이 있으면 기한 없는 0P 쿠폰으로 받는다([dietTrayJson]·[claimDietTray]). 사진
///   기록일은 목업 API 가 drift 에서 세어 넘긴다. 담당이 끊기면 받지 않은 쿠폰을
///   취소한다.
///
/// 만료 3일 전 알림은 목업에 없다 — 데모에서 교환한 쿠폰은 30일 뒤에야 그 창에
/// 들어가고, 목업 알림함은 이 원장과 따로 논다.
///
/// 모든 쿠폰은 헬스장 직원(PT 재등록은 트레이너·헬스장 직원)이 확인한 뒤 회원
/// 화면의 `사용 완료` 를 누른다.
class DemoCouponBook {
  DemoCouponBook({
    required DemoPointsLedger ledger,
    DateTime Function()? now,
    bool hasTrainer = true,
    bool hasGym = true,
    DemoStreakShieldBook? shields,
    DemoGraphColorBook? palette,
    DemoProfilePetBook? pets,
  }) : _ledger = ledger,
       _now = now ?? nowKst,
       _hasTrainer = hasTrainer,
       _hasGym = hasGym,
       _shields = shields ?? DemoStreakShieldBook(ledger: ledger, now: now),
       _palette = palette ?? DemoGraphColorBook(ledger: ledger),
       _pets = pets ?? DemoProfilePetBook(ledger: ledger, now: now);

  /// 연속 기록 보호권(#1788) — 사용처 목록에 함께 서고, 교환은 이 원장이 받는다.
  /// 목업 운동 저장소가 같은 인스턴스를 봐야 교환한 보호권을 운동 현황에서 쓴다.
  final DemoStreakShieldBook _shields;
  DemoStreakShieldBook get shields => _shields;

  /// 그래프 색(#2076) — 사용처 목록에 함께 서고, 교환은 이 원장이 받는다. 기록 그래프
  /// 저장소가 같은 인스턴스를 봐야 교환한 색이 바로 그래프에 보인다.
  final DemoGraphColorBook _palette;
  DemoGraphColorBook get grass => _palette;

  /// MY 프로필 펫 이모지(#2021) — 쿠폰이 아니다. MY 프로필 카드와 같은 것을 봐야
  /// 사용처에서 단 펫이 이름 옆에 보인다.
  final DemoProfilePetBook _pets;
  DemoProfilePetBook get pets => _pets;

  /// 포인트로 받는 주간 리포트(#2022) — 담당이 없을 때만 사용처에 선다. 담당 여부를
  /// 이 원장이 들고 있어서 여기서 만든다.
  late final DemoWeeklyReportBook reports = DemoWeeklyReportBook(
    ledger: _ledger,
    now: _now,
    hasTrainer: () => _hasTrainer,
  );

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  bool _hasTrainer;
  bool _hasGym;
  int _sequence = 0;

  final List<_DemoCoupon> _coupons = <_DemoCoupon>[];

  /// 데모 회원(김민수)에게 담당 트레이너가 있는가. 목업 헬스장 저장소의 연결과 같다.
  bool get hasTrainer => _hasTrainer;

  /// 데모 회원에게 연결한 헬스장이 있는가. 목업 헬스장 저장소의 연결과 같다.
  bool get hasGym => _hasGym;

  /// 담당 트레이너 연결이 끊겼다 — 재등록 쿠폰을 취소하고 포인트를 돌려준다.
  ///
  /// 목업 헬스장 저장소가 헬스장·트레이너 해제에서 부른다.
  void endTrainerLink() {
    _hasTrainer = false;
    _cancelUnused(kDemoPtRenewal.id);
    // 식판(#2150)도 담당 트레이너의 헬스장에서 받는다. 0P 라 돌려줄 포인트는 없다.
    _cancelUnused(kDemoDietTray.id);
  }

  /// 헬스장 연결이 끊겼다 — 락커 쿠폰을 취소하고 포인트를 돌려준다.
  ///
  /// 목업 헬스장 저장소가 헬스장 해제에서 부른다.
  void endGymLink() {
    _hasGym = false;
    _cancelUnused(kDemoLockerMonth.id);
  }

  /// `GET /me/points/shop`.
  Map<String, Object?> shopJson() {
    _expireStale();
    final int balance = _ledger.balance;
    return <String, Object?>{
      'balance': balance,
      'has_trainer': _hasTrainer,
      'has_gym': _hasGym,
      'items': <Map<String, Object?>>[
        // 네 색을 모두 연 회원에게는 그래프 색 항목을 싣지 않는다(#2076) — 더 살 게
        // 없는 카드를 막힌 채 남겨 두지 않는다. 색 바꾸기는 기록 그래프에서 한다.
        for (final DemoShopItem item in kDemoShopCatalog)
          if (!(item.id == kDemoGraphColor.id && _palette.allUnlocked) &&
              // 담당이 있으면 트레이너가 리포트를 등록해 준다 — 싣지 않는다(#2022).
              !(item.id == kDemoWeeklyReport.id && !reports.listed))
            _itemJson(item, balance),
      ],
    };
  }

  /// `POST /me/points/exchange`.
  ///
  /// [option] 은 항목이 여러 갈래일 때 고른 갈래다 — 지금은 그래프 색(#2076) 하나다.
  DemoCouponResult exchange(
    String itemId, {
    String? option,
    String? clientRequestId,
  }) {
    final DemoShopItem? item = _item(itemId);
    if (item == null) return _error(404, '없는 교환 항목이에요.');
    if (item.id == kDemoGraphColor.id) {
      // 쿠폰이 아니라 그래프 색 하나가 열린다 — 고른 색은 `option` 이 싣는다(#2076).
      return _palette.exchange(option, clientRequestId: clientRequestId);
    }
    if (item.id == kDemoWeeklyReport.id) {
      // 쿠폰이 아니라 지난주 리포트 한 주를 받는다 — 담당이 없는 회원만(#2022).
      return reports.exchange(clientRequestId: clientRequestId);
    }
    if (item.id == kDemoProfilePet.id) {
      // 쿠폰이 아니라 고른 펫이 7일 동안 이름 옆에 붙는다(#2021).
      return _pets.exchange(option, clientRequestId: clientRequestId);
    }
    if (item.id == kDemoStreakShield.id) {
      // 쿠폰이 아니라 보호권 한 장이 생긴다 — 보유 한도와 원장이 따로다(#1788).
      return _shields.exchange(clientRequestId: clientRequestId);
    }
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
    if (item.requiresGym && !_hasGym) {
      return _error(409, '헬스장을 연결해야 교환할 수 있어요.');
    }
    if (item.oneActive && _activeOf(item.id) != null) {
      return _error(409, '사용하지 않은 쿠폰이 이미 있어요.');
    }
    if (item.monthlyLimit && _exchangedThisMonth(item.id)) {
      return _error(409, '이번 달에는 이미 교환했어요.');
    }
    final int shortfall = item.cost - _ledger.balance;
    if (shortfall > 0) return _error(409, '포인트가 ${shortfall}P 부족해요.');

    final DateTime today = _today();
    final _DemoCoupon coupon = _DemoCoupon(
      id: 'cpn-demo-${++_sequence}',
      item: item.id,
      cost: item.cost,
      issuedAt: _now(),
      issuedOn: today,
      lastDay: DateTime(today.year, today.month, today.day + item.validDays),
      trainerName: item.requiresTrainer ? kDemoTrainerName : '',
      gymName: item.requiresTrainer || item.requiresGym ? kDemoGymName : '',
      clientRequestId: clientRequestId,
    );
    if (!_ledger.spend(coupon.id, item.cost, reason: 'coupon_${item.id}')) {
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

  // ---- 분석용 식판 (#2150) ----

  /// 사진 기록일을 세는 구간(오늘 포함)과 필요한 날 수. 서버와 같은 값이다.
  static const int dietTrayWindowDays = 28;
  static const int dietTrayRequiredDays = 20;

  /// 사진 기록일을 세는 구간의 첫날 — 오늘에서 27일 전.
  DateTime dietTrayWindowFrom() {
    final DateTime today = _today();
    return DateTime(
      today.year,
      today.month,
      today.day - (dietTrayWindowDays - 1),
    );
  }

  /// 사진 기록일을 세는 구간의 마지막 날 — 오늘.
  DateTime dietTrayWindowTo() => _today();

  /// `GET /me/diet-tray`. [photoDays] 는 구간 안에서 식단 사진을 남긴 날 수다.
  Map<String, Object?> dietTrayJson({required int photoDays}) {
    _expireStale();
    final _DemoCoupon? received = _coupons
        .where(
          (_DemoCoupon c) => c.item == kDemoDietTray.id && c.status == 'used',
        )
        .firstOrNull;
    final _DemoCoupon? active = received == null
        ? _activeOf(kDemoDietTray.id)
        : null;
    final String status = received != null
        ? 'received'
        : active != null
        ? 'issued'
        : _hasTrainer && photoDays >= dietTrayRequiredDays
        ? 'claimable'
        : 'progress';
    final _DemoCoupon? row = received ?? active;
    return <String, Object?>{
      'status': status,
      'photo_days': photoDays,
      'required_days': dietTrayRequiredDays,
      'window_days': dietTrayWindowDays,
      'window_from': _ymd(dietTrayWindowFrom()),
      'window_to': _ymd(dietTrayWindowTo()),
      'has_trainer': _hasTrainer,
      'coupon': row == null ? null : _couponJson(row),
    };
  }

  /// `POST /me/diet-tray/claim`. 조건을 다시 확인하고 0P 쿠폰을 발급한다.
  DemoCouponResult claimDietTray({
    required int photoDays,
    String? clientRequestId,
  }) {
    if (clientRequestId != null &&
        _coupons.any(
          (_DemoCoupon c) =>
              c.item == kDemoDietTray.id &&
              c.clientRequestId == clientRequestId,
        )) {
      return DemoCouponResult(201, dietTrayJson(photoDays: photoDays));
    }
    _expireStale();
    if (_coupons.any(
      (_DemoCoupon c) => c.item == kDemoDietTray.id && c.status == 'used',
    )) {
      return _error(409, '식판은 이미 받았어요.');
    }
    if (_activeOf(kDemoDietTray.id) != null) {
      return _error(409, '받지 않은 식판 쿠폰이 이미 있어요.');
    }
    if (!_hasTrainer) return _error(409, '담당 트레이너가 있어야 받을 수 있어요.');
    final int shortfall = dietTrayRequiredDays - photoDays;
    if (shortfall > 0) return _error(409, '식단 사진 기록이 $shortfall일 더 필요해요.');
    final DateTime today = _today();
    _coupons.add(
      _DemoCoupon(
        id: 'cpn-demo-${++_sequence}',
        item: kDemoDietTray.id,
        cost: 0,
        issuedAt: _now(),
        issuedOn: today,
        lastDay: _noExpiry,
        trainerName: kDemoTrainerName,
        gymName: kDemoGymName,
        clientRequestId: clientRequestId,
      ),
    );
    return DemoCouponResult(201, dietTrayJson(photoDays: photoDays));
  }

  /// 기한 없는 쿠폰(식판)의 마지막 날 — 서버 `NO_EXPIRY` 와 같이 닿지 않는 날이다.
  static final DateTime _noExpiry = DateTime(9998, 12, 31);

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

  /// [itemId] 의 사용 가능한 쿠폰을 취소하고 포인트를 돌려준다. 기한이 지난 쿠폰은
  /// 돌려주지 않고 만료로 내린다. 이미 취소된 쿠폰은 건너뛰어 두 번 돌려주지 않는다.
  void _cancelUnused(String itemId) {
    final DateTime today = _today();
    for (final _DemoCoupon coupon in _coupons) {
      if (coupon.item != itemId || coupon.status != 'issued') {
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

  _DemoCoupon? _activeOf(String itemId) => _coupons
      .where((_DemoCoupon c) => c.item == itemId && c.status == 'issued')
      .firstOrNull;

  /// 이번 달(KST)에 [itemId] 를 교환했는가. 사용 가능·사용·만료 쿠폰은 세고, 취소돼
  /// 포인트를 돌려받은 쿠폰은 세지 않는다.
  bool _exchangedThisMonth(String itemId) {
    final DateTime today = _today();
    return _coupons.any(
      (_DemoCoupon c) =>
          c.item == itemId &&
          c.status != 'cancelled' &&
          c.issuedOn.year == today.year &&
          c.issuedOn.month == today.month,
    );
  }

  static DemoShopItem? _item(String itemId) => kDemoShopCatalog
      .where((DemoShopItem item) => item.id == itemId)
      .firstOrNull;

  Map<String, Object?> _itemJson(DemoShopItem item, int balance) {
    final int shortfall = math.max(item.cost - balance, 0);
    final String? blocked = item.requiresTrainer && !_hasTrainer
        ? 'no_trainer'
        : item.requiresGym && !_hasGym
        ? 'no_gym'
        : item.oneActive && _activeOf(item.id) != null
        ? 'active_coupon'
        : item.id == kDemoProfilePet.id && _pets.active
        ? 'active_pet'
        : item.id == kDemoWeeklyReport.id && reports.targetOwned
        ? 'week_owned'
        : item.id == kDemoStreakShield.id &&
              _shields.held >= DemoStreakShieldBook.maxHeld
        ? 'shield_limit'
        : item.monthlyLimit && _exchangedThisMonth(item.id)
        ? 'monthly_limit'
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
      'requires_trainer': item.requiresTrainer,
      'requires_gym': item.requiresGym,
      'available': blocked == null,
      'blocked_reason': blocked,
      'shortfall': shortfall,
      if (item.id == kDemoProfilePet.id) ..._pets.activeFieldsJson(),
    };
  }

  Map<String, Object?> _exchangeJson(_DemoCoupon coupon) => <String, Object?>{
    'coupon': _couponJson(coupon),
    'spent': coupon.cost,
    'balance': _ledger.balance,
  };

  Map<String, Object?> _couponJson(_DemoCoupon coupon) {
    final DemoShopItem? item = coupon.item == kDemoDietTray.id
        ? kDemoDietTray
        : _item(coupon.item);
    final bool usable = coupon.status == 'issued';
    final bool noExpiry = coupon.lastDay == _noExpiry;
    final int daysLeft = usable && !noExpiry
        ? math.max((coupon.lastDay.difference(_today()).inHours / 24).round(), 0)
        : 0;
    return <String, Object?>{
      'id': coupon.id,
      'item': coupon.item,
      'title': item?.title ?? coupon.item,
      'benefit': item?.benefit ?? coupon.item,
      'cost': coupon.cost,
      'status': coupon.status,
      'trainer_name': coupon.trainerName,
      'gym_name': coupon.gymName,
      'issued_at': coupon.issuedAt.toIso8601String(),
      'issued_on': _ymd(coupon.issuedOn),
      'expires_on': _ymd(coupon.lastDay),
      'days_left': daysLeft,
      'no_expiry': noExpiry,
      'used_at': coupon.usedAt?.toIso8601String(),
      'cancelled_at': coupon.cancelledAt?.toIso8601String(),
    };
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
    this.requiresTrainer = false,
    this.requiresGym = false,
    this.oneActive = false,
    this.monthlyLimit = false,
  });

  final String id;
  final String title;
  final String benefit;
  final String description;
  final int cost;
  final int validDays;
  final bool requiresTrainer;
  final bool requiresGym;
  final bool oneActive;

  /// 한 달(KST)에 한 번만 교환할 수 있는가.
  final bool monthlyLimit;
}

const DemoShopItem kDemoPtRenewal = DemoShopItem(
  id: 'pt_renewal',
  title: 'PT 재등록 3만원 할인',
  benefit: 'PT 재등록 30,000원 할인',
  description: '담당 트레이너에게 PT를 다시 등록할 때 30,000원을 할인받아요.',
  cost: 21000,
  validDays: 30,
  requiresTrainer: true,
  oneActive: true,
);

const DemoShopItem kDemoLockerMonth = DemoShopItem(
  id: 'locker_month',
  title: '개인 락커 1개월 무료',
  benefit: '개인 락커 1개월 무료',
  description: '연결한 헬스장에서 개인 락커를 한 달 동안 무료로 써요.',
  cost: 7000,
  validDays: 30,
  requiresGym: true,
  oneActive: true,
  monthlyLimit: true,
);

const List<DemoShopItem> kDemoShopCatalog = <DemoShopItem>[
  kDemoPtRenewal,
  kDemoLockerMonth,
  kDemoStreakShield,
  kDemoGraphColor,
  kDemoProfilePet,
  kDemoWeeklyReport,
];

/// 분석용 식판(#2150) — 교환 항목이 아니라 달성 보상이라 [kDemoShopCatalog] 에 없다.
/// 쿠폰 목록·상세가 이름을 찾을 때만 쓴다. 서버 `points_coupon_service.DIET_TRAY` 와
/// 같은 값이다.
const DemoShopItem kDemoDietTray = DemoShopItem(
  id: 'diet_tray',
  title: '분석용 식판',
  benefit: '분석용 규격 식판',
  description: '식단 사진 분석에 맞춘 규격 식판을 담당 트레이너의 헬스장에서 받아요.',
  cost: 0,
  // 기한 없음 — 식판이 헬스장에 언제 닿을지는 우리 사정이다.
  validDays: 0,
  requiresTrainer: true,
  oneActive: true,
);

/// 포인트로 받는 주간 리포트(#2022) — 쿠폰이 아니다. 기한이 없어 `validDays` 는
/// 0 이고, 규칙은 [DemoWeeklyReportBook] 이 들고 있다.
const DemoShopItem kDemoWeeklyReport = DemoShopItem(
  id: DemoWeeklyReportBook.itemId,
  title: '주간 리포트',
  benefit: '지난주 식단·운동 리포트',
  description: '지난주 식단·운동 기록과 참고 기록으로 한 주를 돌아보는 리포트를 만들어요.',
  cost: DemoWeeklyReportBook.cost,
  validDays: 0,
);

/// MY 프로필 펫 이모지(#2021) — 쿠폰이 아니다. 규칙은 [DemoProfilePetBook] 이 들고
/// 있다.
const DemoShopItem kDemoProfilePet = DemoShopItem(
  id: DemoProfilePetBook.itemId,
  title: '프로필 펫 이모지',
  benefit: 'MY 프로필 이름 옆 펫 이모지 7일',
  description: '강아지나 고양이를 골라 7일 동안 MY 프로필 이름 옆에 달아요.',
  cost: DemoProfilePetBook.cost,
  validDays: DemoProfilePetBook.days,
);

/// 연속 기록 보호권(#1788) — 쿠폰이 아니다. 기한이 없어 `validDays` 는 0 이고,
/// 교환·사용 규칙은 [DemoStreakShieldBook] 이 들고 있다.
const DemoShopItem kDemoStreakShield = DemoShopItem(
  id: DemoStreakShieldBook.itemId,
  title: '연속 기록 보호권',
  benefit: '운동을 못 한 하루를 연속 기록에 이어 붙이기',
  description:
      '아무것도 기록하지 못한 날을 연속 기록에 이어 붙여요. 최근 30일 안에서 쓰고, 최대 4개까지 가질 수 있어요.',
  cost: DemoStreakShieldBook.cost,
  validDays: 0,
);

/// 그래프 색 바꾸기(#2076) — 쿠폰이 아니다. 기한이 없어 `validDays` 는 0 이고,
/// 색 목록·교환 규칙은 [DemoGraphColorBook] 이 들고 있다.
const DemoShopItem kDemoGraphColor = DemoShopItem(
  id: DemoGraphColorBook.itemId,
  title: '그래프 색 바꾸기',
  benefit: '기록 그래프를 다른 색으로',
  description: '포인트 화면 기록 그래프의 색을 골라 바꿔요. 한 번 연 색은 계속 쓸 수 있어요.',
  cost: DemoGraphColorBook.cost,
  validDays: 0,
);

/// 데모 헬스장 — `MockGymRepository` 의 온케어짐 신촌점과 같다. 담당 트레이너
/// 이름은 두 앱이 함께 읽는 `demo_fixture` 의 [kDemoTrainerName] 이다.
const String kDemoGymName = '온케어짐 신촌점';

class _DemoCoupon {
  _DemoCoupon({
    required this.id,
    required this.item,
    required this.cost,
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
///
/// 보호권은 목업 운동 저장소와 같은 원장을 쓴다(#1788).
final demoCouponBookProvider = Provider<DemoCouponBook>(
  (ref) => DemoCouponBook(
    ledger: ref.watch(demoPointsLedgerProvider),
    shields: ref.watch(demoStreakShieldBookProvider),
    // 기록 그래프가 보는 것과 같은 색 원장 — 사용처에서 연 색이 바로 그래프에 뜬다(#2076).
    palette: ref.watch(demoGraphColorBookProvider),
    pets: ref.watch(demoProfilePetBookProvider),
  ),
  name: 'demoCouponBook',
);

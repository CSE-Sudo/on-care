/// 포인트 사용처 — 교환 항목과 지금 교환할 수 있는지. (#1787)
///
/// 가격·기한·교환 가능 여부는 서버(`GET /me/points/shop`)가 정한다. 앱이 담당
/// 트레이너 여부나 "사용하지 않은 재등록 쿠폰은 한 장" 규칙을 따로 들고 있으면,
/// 규칙이 바뀔 때 화면만 옛 규칙으로 남는다.
library;

import 'package:oncare/features/benefits/domain/entities/coupon.dart';

/// 교환 버튼을 막는 이유. 앱이 모르는 값은 [unknown] 이고 버튼만 막는다.
///
/// [shieldLimit] 은 쓰지 않은 연속 기록 보호권을 이미 최대로 가진 경우다(#1788).
enum ShopBlockReason {
  noTrainer,
  activeCoupon,
  shieldLimit,
  insufficientPoints,
  unknown,
}

ShopBlockReason? _blockFrom(Object? raw) => switch (raw) {
  null => null,
  'no_trainer' => ShopBlockReason.noTrainer,
  'active_coupon' => ShopBlockReason.activeCoupon,
  'shield_limit' => ShopBlockReason.shieldLimit,
  'insufficient_points' => ShopBlockReason.insufficientPoints,
  _ => ShopBlockReason.unknown,
};

class ShopItem {
  const ShopItem({
    required this.id,
    required this.title,
    required this.benefit,
    required this.description,
    required this.cost,
    required this.validDays,
    required this.redeemer,
    required this.available,
    this.requiresTrainer = false,
    this.blockReason,
    this.shortfall = 0,
  });

  /// pt_renewal|salad_discount|protein_discount.
  final String id;

  /// 서버 문구. 아는 항목은 앱이 현지화 문구로 바꿔 그린다.
  final String title;
  final String benefit;
  final String description;
  final int cost;

  /// 교환한 날부터 쓸 수 있는 날 수.
  final int validDays;
  final CouponRedeemer redeemer;
  final bool requiresTrainer;

  /// 지금 교환할 수 있는가.
  final bool available;
  final ShopBlockReason? blockReason;

  /// 모자란 포인트. 모자라지 않으면 0.
  final int shortfall;

  factory ShopItem.fromJson(Map<String, Object?> json) => ShopItem(
    id: json['id']! as String,
    title: (json['title'] as String?) ?? '',
    benefit: (json['benefit'] as String?) ?? '',
    description: (json['description'] as String?) ?? '',
    cost: (json['cost']! as num).toInt(),
    validDays: (json['valid_days'] as num?)?.toInt() ?? 0,
    redeemer: couponRedeemerFrom(json['redeemer']),
    requiresTrainer: json['requires_trainer'] == true,
    available: json['available'] == true,
    blockReason: _blockFrom(json['blocked_reason']),
    shortfall: (json['shortfall'] as num?)?.toInt() ?? 0,
  );
}

class PointsShop {
  const PointsShop({
    required this.balance,
    required this.hasTrainer,
    required this.items,
  });

  final int balance;
  final bool hasTrainer;
  final List<ShopItem> items;

  factory PointsShop.fromJson(Map<String, Object?> json) => PointsShop(
    balance: (json['balance'] as num?)?.toInt() ?? 0,
    hasTrainer: json['has_trainer'] == true,
    items: <ShopItem>[
      for (final Object? raw
          in (json['items'] as List<Object?>?) ?? <Object?>[])
        ShopItem.fromJson(
          (raw! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
    ],
  );
}

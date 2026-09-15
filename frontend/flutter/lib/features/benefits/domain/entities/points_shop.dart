/// 포인트 사용처 — 교환 항목과 지금 교환할 수 있는지. (#1787)
///
/// 가격·기한·교환 가능 여부는 서버(`GET /me/points/shop`)가 정한다. 앱이 담당
/// 트레이너·헬스장 여부나 "사용하지 않은 쿠폰은 한 장", "락커는 한 달에 한 번"
/// 규칙을 따로 들고 있으면, 규칙이 바뀔 때 화면만 옛 규칙으로 남는다.
library;

/// 교환 버튼을 막는 이유. 앱이 모르는 값은 [unknown] 이고 버튼만 막는다.
enum ShopBlockReason {
  noTrainer,
  noGym,
  activeCoupon,
  monthlyLimit,
  insufficientPoints,
  unknown,
}

ShopBlockReason? _blockFrom(Object? raw) => switch (raw) {
  null => null,
  'no_trainer' => ShopBlockReason.noTrainer,
  'no_gym' => ShopBlockReason.noGym,
  'active_coupon' => ShopBlockReason.activeCoupon,
  'monthly_limit' => ShopBlockReason.monthlyLimit,
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
    required this.available,
    this.requiresTrainer = false,
    this.requiresGym = false,
    this.blockReason,
    this.shortfall = 0,
  });

  /// pt_renewal|locker_month.
  final String id;

  /// 서버 문구. 아는 항목은 앱이 현지화 문구로 바꿔 그린다.
  final String title;
  final String benefit;
  final String description;
  final int cost;

  /// 교환한 날부터 쓸 수 있는 날 수.
  final int validDays;
  final bool requiresTrainer;

  /// 연결한 헬스장이 있어야 교환할 수 있는가.
  final bool requiresGym;

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
    requiresTrainer: json['requires_trainer'] == true,
    requiresGym: json['requires_gym'] == true,
    available: json['available'] == true,
    blockReason: _blockFrom(json['blocked_reason']),
    shortfall: (json['shortfall'] as num?)?.toInt() ?? 0,
  );
}

class PointsShop {
  const PointsShop({
    required this.balance,
    required this.hasTrainer,
    required this.hasGym,
    required this.items,
  });

  final int balance;
  final bool hasTrainer;

  /// 회원이 헬스장을 연결했는가(`GET /me/gym` 과 같은 링크).
  final bool hasGym;
  final List<ShopItem> items;

  factory PointsShop.fromJson(Map<String, Object?> json) => PointsShop(
    balance: (json['balance'] as num?)?.toInt() ?? 0,
    hasTrainer: json['has_trainer'] == true,
    hasGym: json['has_gym'] == true,
    items: <ShopItem>[
      for (final Object? raw in (json['items'] as List<Object?>?) ?? <Object?>[])
        ShopItem.fromJson((raw! as Map<Object?, Object?>).cast<String, Object?>()),
    ],
  );
}

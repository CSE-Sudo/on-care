import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/domain/repositories/benefits_repository.dart';

/// 위젯 테스트용 사용처·쿠폰 저장소 — 넣어 준 목록을 돌려주고 호출을 기록한다.
class FakeBenefitsRepository implements BenefitsRepository {
  FakeBenefitsRepository({PointsShop? shop, List<Coupon>? coupons})
    : shop = shop ?? shopWith(balance: 1240),
      coupons = coupons ?? <Coupon>[];

  PointsShop shop;
  List<Coupon> coupons;

  final List<String> exchanged = <String>[];
  final List<String> used = <String>[];

  /// 서버처럼 사용 가능한 쿠폰의 종류를 반영해 목록을 다시 만든다.
  void _refreshShop(int balance) {
    shop = shopWith(
      balance: balance,
      hasTrainer: shop.hasTrainer,
      activeItems: <String>{
        for (final Coupon c in coupons)
          if (c.usable) c.item,
      },
    );
  }

  @override
  Future<PointsShop> fetchShop() async => shop;

  @override
  Future<CouponExchange> exchange(
    String itemId, {
    String? clientRequestId,
  }) async {
    exchanged.add(itemId);
    final ShopItem item = shop.items.firstWhere((ShopItem i) => i.id == itemId);
    final int balance = shop.balance - item.cost;
    final Coupon coupon = couponOf(
      id: 'cpn-new-${exchanged.length}',
      item: itemId,
    );
    coupons = <Coupon>[coupon, ...coupons];
    _refreshShop(balance);
    return CouponExchange(coupon: coupon, spent: item.cost, balance: balance);
  }

  @override
  Future<List<Coupon>> fetchCoupons() async => coupons;

  @override
  Future<Coupon> useCoupon(String couponId) async {
    used.add(couponId);
    coupons = <Coupon>[
      for (final Coupon c in coupons)
        c.id == couponId ? couponOf(id: c.id, item: c.item, status: CouponStatus.used) : c,
    ];
    _refreshShop(shop.balance);
    return coupons.firstWhere((Coupon c) => c.id == couponId);
  }
}

/// 서버 규칙대로 막힌 이유를 계산한 교환 목록.
///
/// 순서도 서버와 같다 — 담당 없음, 사용하지 않은 같은 종류 쿠폰 보유(종류마다 한 장),
/// 잔액 부족.
PointsShop shopWith({
  required int balance,
  bool hasTrainer = true,
  Set<String> activeItems = const <String>{},
}) {
  ShopItem item(String id, int cost, {bool requiresTrainer = false}) {
    final int shortfall = cost > balance ? cost - balance : 0;
    final ShopBlockReason? blocked = requiresTrainer && !hasTrainer
        ? ShopBlockReason.noTrainer
        : activeItems.contains(id)
        ? ShopBlockReason.activeCoupon
        : shortfall > 0
        ? ShopBlockReason.insufficientPoints
        : null;
    return ShopItem(
      id: id,
      title: id,
      benefit: id,
      description: id,
      cost: cost,
      validDays: 30,
      redeemer: CouponRedeemer.member,
      requiresTrainer: requiresTrainer,
      available: blocked == null,
      blockReason: blocked,
      shortfall: shortfall,
    );
  }

  return PointsShop(
    balance: balance,
    hasTrainer: hasTrainer,
    items: <ShopItem>[
      item('pt_renewal', 5000, requiresTrainer: true),
      item('salad_discount', 1000),
      item('protein_discount', 1000),
    ],
  );
}

/// 사용한 쿠폰의 사용 시각(KST 벽시계).
final DateTime kFakeUsedAt = DateTime(2026, 9, 20, 14, 30);

Coupon couponOf({
  required String id,
  required String item,
  CouponStatus status = CouponStatus.issued,
  int daysLeft = 30,
}) {
  final bool renewal = item == 'pt_renewal';
  return Coupon(
    id: id,
    item: item,
    title: item,
    benefit: item,
    cost: renewal ? 5000 : 1000,
    status: status,
    // 모든 쿠폰을 회원 휴대폰에서 사용 처리한다.
    redeemer: CouponRedeemer.member,
    trainerName: renewal ? '김트레이너' : '',
    gymName: renewal ? '온케어짐 신촌점' : '',
    issuedOn: DateTime(2026, 9, 15),
    expiresOn: DateTime(2026, 10, 15),
    daysLeft: status == CouponStatus.issued ? daysLeft : 0,
    usedAt: status == CouponStatus.used ? kFakeUsedAt : null,
  );
}

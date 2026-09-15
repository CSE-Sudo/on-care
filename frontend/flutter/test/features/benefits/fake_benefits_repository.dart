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
    shop = shopWith(balance: balance, hasTrainer: shop.hasTrainer);
    final Coupon coupon = couponOf(
      id: 'cpn-new-${exchanged.length}',
      item: itemId,
    );
    coupons = <Coupon>[coupon, ...coupons];
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
    return coupons.firstWhere((Coupon c) => c.id == couponId);
  }
}

/// 서버 규칙대로 막힌 이유를 계산한 교환 목록.
PointsShop shopWith({required int balance, bool hasTrainer = true}) {
  ShopItem item(
    String id,
    int cost,
    CouponRedeemer redeemer, {
    bool requiresTrainer = false,
  }) {
    final int shortfall = cost > balance ? cost - balance : 0;
    final ShopBlockReason? blocked = requiresTrainer && !hasTrainer
        ? ShopBlockReason.noTrainer
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
      redeemer: redeemer,
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
      item('pt_renewal', 5000, CouponRedeemer.trainer, requiresTrainer: true),
      item('salad_discount', 1000, CouponRedeemer.member),
      item('protein_discount', 1000, CouponRedeemer.member),
    ],
  );
}

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
    code: 'ABCD2345',
    status: status,
    redeemer: renewal ? CouponRedeemer.trainer : CouponRedeemer.member,
    trainerName: renewal ? '김트레이너' : '',
    gymName: renewal ? '온케어짐 신촌점' : '',
    issuedOn: DateTime(2026, 9, 15),
    expiresOn: DateTime(2026, 10, 15),
    daysLeft: status == CouponStatus.issued ? daysLeft : 0,
  );
}

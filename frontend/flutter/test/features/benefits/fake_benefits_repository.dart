import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/domain/entities/profile_pet.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_report_purchase.dart';
import 'package:oncare/features/benefits/domain/repositories/benefits_repository.dart';

/// 위젯 테스트용 사용처·쿠폰 저장소 — 넣어 준 목록을 돌려주고 호출을 기록한다.
///
/// 기본 잔액은 9,000P 다 — PT 재등록(21,000P)은 모자라고 개인 락커(7,000P)는
/// 교환할 수 있어, 두 상태가 한 화면에 함께 선다.
class FakeBenefitsRepository implements BenefitsRepository {
  FakeBenefitsRepository({PointsShop? shop, List<Coupon>? coupons, this.pet})
    : shop = shop ?? shopWith(balance: 9000),
      coupons = coupons ?? <Coupon>[];

  PointsShop shop;
  List<Coupon> coupons;

  /// MY 이름 옆에 단 펫(#2021). null 이면 달고 있지 않다.
  ProfilePet? pet;

  final List<String> exchanged = <String>[];
  final List<String> used = <String>[];

  /// 서버처럼 사용 가능한 쿠폰의 종류와 이번 달 교환을 반영해 목록을 다시 만든다.
  void _refreshShop(int balance) {
    shop = shopWith(
      balance: balance,
      hasTrainer: shop.hasTrainer,
      hasGym: shop.hasGym,
      activeItems: <String>{
        for (final Coupon c in coupons)
          if (c.usable) c.item,
      },
      // 가짜 쿠폰은 모두 이번 달에 교환한 것으로 본다.
      monthlyUsed: <String>{
        for (final Coupon c in coupons)
          if (c.status != CouponStatus.cancelled) c.item,
      },
    );
  }

  @override
  Future<PointsShop> fetchShop() async => shop;

  @override
  Future<CouponExchange> exchange(
    String itemId, {
    String? option,
    String? clientRequestId,
  }) async {
    exchanged.add(option == null ? itemId : '$itemId:$option');
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
  Future<ProfilePet?> fetchProfilePet() async => pet;

  /// 포인트로 받은 주간 리포트(#2022). 기본은 받은 주가 없다.
  WeeklyReportPurchases reports = WeeklyReportPurchases(
    weeks: const <DateTime>[],
    nextWeekStart: DateTime(2026, 9, 14),
    cost: 300,
  );

  @override
  Future<WeeklyReportPurchases> fetchWeeklyReports() async => reports;

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
/// 순서도 서버와 같다 — 담당 없음·헬스장 없음, 사용하지 않은 같은 종류 쿠폰 보유
/// (종류마다 한 장), 이번 달 교환(락커), 잔액 부족.
PointsShop shopWith({
  required int balance,
  bool hasTrainer = true,
  bool hasGym = true,
  Set<String> activeItems = const <String>{},
  Set<String> monthlyUsed = const <String>{},
}) {
  ShopItem item(
    String id,
    int cost, {
    bool requiresTrainer = false,
    bool requiresGym = false,
    bool monthlyLimit = false,
  }) {
    final int shortfall = cost > balance ? cost - balance : 0;
    final ShopBlockReason? blocked = requiresTrainer && !hasTrainer
        ? ShopBlockReason.noTrainer
        : requiresGym && !hasGym
        ? ShopBlockReason.noGym
        : activeItems.contains(id)
        ? ShopBlockReason.activeCoupon
        : monthlyLimit && monthlyUsed.contains(id)
        ? ShopBlockReason.monthlyLimit
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
      requiresTrainer: requiresTrainer,
      requiresGym: requiresGym,
      available: blocked == null,
      blockReason: blocked,
      shortfall: shortfall,
    );
  }

  return PointsShop(
    balance: balance,
    hasTrainer: hasTrainer,
    hasGym: hasGym,
    items: <ShopItem>[
      item('pt_renewal', 21000, requiresTrainer: true),
      item('locker_month', 7000, requiresGym: true, monthlyLimit: true),
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
  final bool locker = item == 'locker_month';
  return Coupon(
    id: id,
    item: item,
    title: item,
    benefit: item,
    cost: renewal ? 21000 : 7000,
    status: status,
    trainerName: renewal ? '김트레이너' : '',
    gymName: renewal || locker ? '온케어짐 신촌점' : '',
    issuedOn: DateTime(2026, 9, 15),
    expiresOn: DateTime(2026, 10, 15),
    daysLeft: status == CouponStatus.issued ? daysLeft : 0,
    usedAt: status == CouponStatus.used ? kFakeUsedAt : null,
  );
}

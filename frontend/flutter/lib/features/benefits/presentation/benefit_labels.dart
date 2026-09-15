import 'package:flutter/material.dart';

import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 교환 항목·쿠폰의 화면 문구와 아이콘. (#1787)
///
/// 서버는 한국어 문구만 준다. 아는 항목은 현지화 문구로 그리고, 앱이 모르는 새
/// 항목만 서버 문구를 그대로 쓴다 — 새 항목이 생겨도 빈 카드가 되지 않는다.
const String kPtRenewalItem = 'pt_renewal';
const String kSaladDiscountItem = 'salad_discount';
const String kProteinDiscountItem = 'protein_discount';

String shopItemTitle(AppLocalizations l, ShopItem item) => switch (item.id) {
  kPtRenewalItem => l.myShopPtRenewalTitle,
  kSaladDiscountItem => l.myShopSaladTitle,
  kProteinDiscountItem => l.myShopProteinTitle,
  _ => item.title,
};

String shopItemDescription(AppLocalizations l, ShopItem item) =>
    switch (item.id) {
      kPtRenewalItem => l.myShopPtRenewalDescription,
      kSaladDiscountItem => l.myShopSaladDescription,
      kProteinDiscountItem => l.myShopProteinDescription,
      _ => item.description,
    };

/// 교환 목록 카드에 적는 막힌 이유. 막히지 않았으면 null.
String? shopBlockLabel(AppLocalizations l, ShopItem item) {
  if (item.available) return null;
  return switch (item.blockReason) {
    ShopBlockReason.noTrainer => l.myPointsNeedTrainer,
    ShopBlockReason.activeCoupon => l.myPointsActiveCoupon,
    ShopBlockReason.insufficientPoints => l.myPointsShortfall(
      l.myPointsCost(item.shortfall),
    ),
    ShopBlockReason.unknown || null => null,
  };
}

/// 쿠폰의 혜택 한 줄.
String couponBenefit(AppLocalizations l, Coupon coupon) => switch (coupon.item) {
  kPtRenewalItem => l.myCouponPtRenewalBenefit,
  kSaladDiscountItem => l.myShopSaladTitle,
  kProteinDiscountItem => l.myShopProteinTitle,
  _ => coupon.benefit.isNotEmpty ? coupon.benefit : coupon.title,
};

IconData benefitIcon(String itemId) => switch (itemId) {
  kPtRenewalItem => Icons.card_membership_rounded,
  kSaladDiscountItem => Icons.eco_rounded,
  kProteinDiscountItem => Icons.local_drink_rounded,
  _ => Icons.redeem_rounded,
};

/// 목록 태그의 짧은 상태 — 사용 가능이면 D-n.
String couponStatusShort(AppLocalizations l, Coupon coupon) =>
    switch (coupon.status) {
      CouponStatus.issued => couponDday(l, coupon.daysLeft),
      CouponStatus.used => l.myCouponStatusUsed,
      CouponStatus.expired => l.myCouponStatusExpired,
      CouponStatus.cancelled => l.myCouponStatusCancelled,
    };

/// 상세의 상태 줄.
String couponStatusLabel(AppLocalizations l, Coupon coupon) =>
    switch (coupon.status) {
      CouponStatus.issued => l.myCouponStatusUsable,
      CouponStatus.used => l.myCouponStatusUsed,
      CouponStatus.expired => l.myCouponStatusExpired,
      CouponStatus.cancelled => l.myCouponStatusCancelled,
    };

String couponDday(AppLocalizations l, int daysLeft) =>
    daysLeft <= 0 ? l.myCouponDDay : l.myCouponDaysLeft(daysLeft);

/// `2026.10.15`.
String formatCouponDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}.'
    '${day.month.toString().padLeft(2, '0')}.'
    '${day.day.toString().padLeft(2, '0')}';

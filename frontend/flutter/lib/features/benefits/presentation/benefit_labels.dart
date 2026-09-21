import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 교환 항목·쿠폰의 화면 문구와 아이콘. (#1787)
///
/// 서버는 한국어 문구만 준다. 아는 항목은 현지화 문구로 그리고, 앱이 모르는 새
/// 항목만 서버 문구를 그대로 쓴다 — 새 항목이 생겨도 빈 카드가 되지 않는다.
const String kPtRenewalItem = 'pt_renewal';
const String kLockerMonthItem = 'locker_month';

/// 연속 기록 보호권(#1788) — 쿠폰이 아니라 포인트 화면 기록 그래프에서 쓴다(#2075).
const String kStreakShieldItem = 'streak_shield';

/// 그래프 색 바꾸기(#2076) — 쿠폰이 아니라 그래프 색 하나를 연다. 교환 전에 어느 색을
/// 열지 고르는 단계가 하나 더 있다.
const String kGraphColorItem = 'graph_color';

/// 프로필 펫 이모지(#2021) — 쿠폰이 아니라 7일 동안 MY 이름 옆에 펫을 단다. 교환 전에
/// 어느 펫을 달지 고르는 단계가 하나 더 있다.
const String kProfilePetItem = 'profile_pet';

/// 고를 수 있는 펫. 고르는 창에 서는 순서 그대로다(서버 `KINDS` 와 같다).
const List<String> kProfilePetKinds = <String>['dog', 'cat'];

String shopItemTitle(AppLocalizations l, ShopItem item) => switch (item.id) {
  kPtRenewalItem => l.myShopPtRenewalTitle,
  kLockerMonthItem => l.myShopLockerTitle,
  kStreakShieldItem => l.myShopStreakShieldTitle,
  kGraphColorItem => l.myShopGraphColorTitle,
  kProfilePetItem => l.myShopProfilePetTitle,
  _ => item.title,
};

String shopItemDescription(AppLocalizations l, ShopItem item) =>
    switch (item.id) {
      kPtRenewalItem => l.myShopPtRenewalDescription,
      kLockerMonthItem => l.myShopLockerDescription,
      kStreakShieldItem => l.myShopStreakShieldDescription,
      kGraphColorItem => l.myShopGraphColorDescription,
      kProfilePetItem => l.myShopProfilePetDescription,
      _ => item.description,
    };

/// 교환 목록 카드에 적는 막힌 이유. 막히지 않았으면 null.
String? shopBlockLabel(AppLocalizations l, ShopItem item) {
  if (item.available) return null;
  return switch (item.blockReason) {
    ShopBlockReason.noTrainer => l.myPointsNeedTrainer,
    ShopBlockReason.noGym => l.myPointsNeedGym,
    ShopBlockReason.activeCoupon => l.myPointsActiveCoupon,
    ShopBlockReason.shieldLimit => l.myPointsShieldLimit,
    // 달고 있는 펫과 남은 기간 — 사용처에서 남은 기간을 보는 자리다(#2021).
    ShopBlockReason.activePet => l.myProfilePetActive(
      profilePetName(l, item.activeOption ?? ''),
      profilePetLeft(l, item.remainingSeconds),
    ),
    ShopBlockReason.monthlyLimit => l.myPointsMonthlyLimit,
    ShopBlockReason.insufficientPoints => l.myPointsShortfall(
      l.myPointsCost(item.shortfall),
    ),
    ShopBlockReason.unknown || null => null,
  };
}

/// 그래프 색 이름 — 팔레트와 색 고르기 시트가 쓴다(#2076). 앱이 모르는 색이 오면
/// 서버가 준 이름을 그대로 적는다(빈 칸이 되지 않게).
String graphColorName(AppLocalizations l, String color) => switch (color) {
  'blue' => l.myGraphColorBlue,
  'green' => l.myGraphColorGreen,
  'purple' => l.myGraphColorPurple,
  'orange' => l.myGraphColorOrange,
  'pink' => l.myGraphColorPink,
  _ => color,
};

/// 펫 이름 — 고르는 창·사용처 카드·확인창이 쓴다(#2021).
String profilePetName(AppLocalizations l, String kind) => switch (kind) {
  'dog' => l.myProfilePetDog,
  'cat' => l.myProfilePetCat,
  _ => kind,
};

/// 펫을 그리는 이모티콘 그림 — 채팅 이모티콘(#2020)의 강아지·고양이 얼굴이다.
/// 앱이 모르는 펫이면 null 이고 아무것도 그리지 않는다.
String? profilePetEmote(String kind) => switch (kind) {
  'dog' => 'dog_hehe',
  'cat' => 'cat_meh',
  _ => null,
};

/// 남은 기간 — 하루 이상이면 날, 하루가 안 남았으면 시간. 둘 다 올림이라 막 단
/// 펫은 `7일 남음`, 끝나기 직전은 `1시간 남음` 이다.
String profilePetLeft(AppLocalizations l, int remainingSeconds) {
  const int hour = 3600;
  const int day = 24 * hour;
  if (remainingSeconds >= day) {
    return l.myProfilePetDaysLeft((remainingSeconds + day - 1) ~/ day);
  }
  final int hours = (remainingSeconds + hour - 1) ~/ hour;
  return l.myProfilePetHoursLeft(hours < 1 ? 1 : hours);
}

/// 쿠폰의 혜택 한 줄.
String couponBenefit(AppLocalizations l, Coupon coupon) => switch (coupon.item) {
  kPtRenewalItem => l.myCouponPtRenewalBenefit,
  kLockerMonthItem => l.myShopLockerTitle,
  _ => coupon.benefit.isNotEmpty ? coupon.benefit : coupon.title,
};

IconData benefitIcon(String itemId) => switch (itemId) {
  kPtRenewalItem => AppIcons.ptRenewal,
  kLockerMonthItem => AppIcons.locker,
  kStreakShieldItem => AppIcons.streakShield,
  kGraphColorItem => AppIcons.palette,
  kProfilePetItem => AppIcons.pets,
  _ => AppIcons.coupon,
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

/// `2026.10.15 14:30` — [at] 은 이미 KST 벽시계 값이다([Coupon.usedAt]).
String formatCouponDateTime(DateTime at) =>
    '${formatCouponDate(at)} '
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

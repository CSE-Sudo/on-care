import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_history.dart';
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

/// 주간 리포트(#2022) — 담당 트레이너가 없는 회원이 지난주 리포트를 받는다. 담당이
/// 있으면 서버가 목록에 싣지 않는다.
const String kWeeklyReportItem = 'weekly_report';

/// 분석용 식판(#2150) — 교환 항목이 아니라 사진 기록 달성 보상이다. 사용처 목록에는
/// 없고, 포인트 화면의 식판 카드에서 받은 0P 수령 쿠폰으로만 보인다.
const String kDietTrayItem = 'diet_tray';

/// 고를 수 있는 펫. 고르는 창에 서는 순서 그대로다(서버 `KINDS` 와 같다).
const List<String> kProfilePetKinds = <String>['dog', 'cat'];

String shopItemTitle(AppLocalizations l, ShopItem item) => switch (item.id) {
  kPtRenewalItem => l.myShopPtRenewalTitle,
  kLockerMonthItem => l.myShopLockerTitle,
  kStreakShieldItem => l.myShopStreakShieldTitle,
  kGraphColorItem => l.myShopGraphColorTitle,
  kProfilePetItem => l.myShopProfilePetTitle,
  kWeeklyReportItem => l.myShopWeeklyReportTitle,
  _ => item.title,
};

String shopItemDescription(AppLocalizations l, ShopItem item) =>
    switch (item.id) {
      kPtRenewalItem => l.myShopPtRenewalDescription,
      kLockerMonthItem => l.myShopLockerDescription,
      kStreakShieldItem => l.myShopStreakShieldDescription,
      kGraphColorItem => l.myShopGraphColorDescription,
      kProfilePetItem => l.myShopProfilePetDescription,
      kWeeklyReportItem => l.myShopWeeklyReportDescription(
        reportWeekRange(l, lastWeekMonday()),
      ),
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
    ShopBlockReason.weekOwned => l.myWeeklyReportOwned,
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

/// 지금 주간 리포트를 받으면 가리키는 주 — 지난주 월요일(KST). 서버
/// `weekly_report_purchase_service.target_week` 와 같은 규칙이다(#2022).
DateTime lastWeekMonday() {
  final DateTime today = todayKst();
  return DateTime(today.year, today.month, today.day - today.weekday + 1 - 7);
}

/// `9월 14일 – 9월 20일` — 채팅의 리포트 카드와 같은 표기다.
String reportWeekRange(AppLocalizations l, DateTime monday) {
  final DateTime sunday = DateTime(monday.year, monday.month, monday.day + 6);
  return l.coachChatReportWeek(
    monday.month,
    monday.day,
    sunday.month,
    sunday.day,
  );
}

/// 포인트 내역 한 줄의 이름(#2146). 회수·반환이면 무엇이 되돌려졌는지 덧붙인다.
String pointsEntryLabel(AppLocalizations l, PointsHistoryEntry entry) {
  final String base = switch (entry.reason) {
    'diet_entry' => l.myPointsReasonDiet,
    'exercise_manual' => l.myPointsReasonExercise,
    'routine_complete' => l.myPointsReasonRoutine,
    'coupon_$kPtRenewalItem' => l.myPointsReasonPtRenewal,
    'coupon_$kLockerMonthItem' => l.myPointsReasonLocker,
    kStreakShieldItem => l.myPointsReasonShield,
    kGraphColorItem => l.myPointsReasonGraphColor,
    'emote_pass_24h' => l.myPointsReasonEmotePass,
    kProfilePetItem => l.myPointsReasonProfilePet,
    kWeeklyReportItem => l.myPointsReasonWeeklyReport,
    'challenge_stake' => l.myPointsReasonChallengeStake,
    'challenge_reward' => l.myPointsReasonChallengeReward,
    'ai_chat' => l.myPointsReasonAiChat(entry.count),
    _ => l.myPointsReasonOther,
  };
  return switch (entry.kind) {
    PointsEntryKind.revoke => l.myPointsKindRevoked(base),
    PointsEntryKind.refund => l.myPointsKindRefunded(base),
    PointsEntryKind.earn || PointsEntryKind.spend => base,
  };
}

/// 포인트 내역 한 줄의 아이콘 — 사용처 항목은 사용처 카드와 같은 아이콘이다.
IconData pointsEntryIcon(PointsHistoryEntry entry) => switch (entry.reason) {
  'diet_entry' => AppIcons.diet,
  'exercise_manual' || 'routine_complete' => AppIcons.exercise,
  'challenge_stake' || 'challenge_reward' => AppIcons.challenge,
  'ai_chat' => AppIcons.ai,
  'emote_pass_24h' => AppIcons.emote,
  final String reason when reason.startsWith('coupon_') => benefitIcon(
    reason.substring('coupon_'.length),
  ),
  final String reason => benefitIcon(reason),
};

/// `+50P` / `−50P`. 0 은 부호 없이 적는다.
String pointsDelta(AppLocalizations l, int delta) {
  final String amount = l.myPointsCost(delta.abs());
  if (delta > 0) return '+$amount';
  if (delta < 0) return '−$amount';
  return amount;
}

/// 폭 없는 줄바꿈 금지 문자(U+2060 WORD JOINER).
const String _wordJoiner = '\u2060';

/// 줄이 **띄어쓰기에서만** 바뀌게 한다. 사용처 화면의 카드(분석용 식판 #2150,
/// 주간 챌린지 #1789)가 설명·안내 줄에 쓴다.
///
/// 한 덩어리 Text 로 두면 한글은 음절 사이 어디서나 끊겨 `분석` / `에 맞춘`,
/// `받아` / `요` 처럼 갈린다. 낱말 안의 글자 사이마다 줄바꿈 금지 문자를 끼워
/// 낱말을 통째로 넘긴다(식단 화면의 `_keepTogether` 와 같은 방법을 낱말 단위로).
/// 한 낱말이 한 줄보다 길면 Flutter 가 그 안에서 끊는다.
String keepWords(String text) => text
    .split(' ')
    .map((String word) => word.runes.map(String.fromCharCode).join(_wordJoiner))
    .join(' ');

/// 쿠폰의 혜택 한 줄.
String couponBenefit(AppLocalizations l, Coupon coupon) => switch (coupon.item) {
  kPtRenewalItem => l.myCouponPtRenewalBenefit,
  kLockerMonthItem => l.myShopLockerTitle,
  kDietTrayItem => l.myDietTrayCouponBenefit,
  _ => coupon.benefit.isNotEmpty ? coupon.benefit : coupon.title,
};

IconData benefitIcon(String itemId) => switch (itemId) {
  kPtRenewalItem => AppIcons.ptRenewal,
  kLockerMonthItem => AppIcons.locker,
  kDietTrayItem => AppIcons.dietTray,
  kStreakShieldItem => AppIcons.streakShield,
  kGraphColorItem => AppIcons.palette,
  kProfilePetItem => AppIcons.pets,
  kWeeklyReportItem => AppIcons.document,
  _ => AppIcons.coupon,
};

/// 목록 태그의 짧은 상태 — 사용 가능이면 D-n.
String couponStatusShort(AppLocalizations l, Coupon coupon) =>
    switch (coupon.status) {
      // 기한이 없으면 D-n 대신 사용 가능이다(식판, #2150).
      CouponStatus.issued when coupon.noExpiry => l.myCouponStatusUsable,
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

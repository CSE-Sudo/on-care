import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 혜택 카드 앞의 아이콘 자리 — MY 설정 행과 같은 모양이다. 배경 없이 칸 크기만
/// 잡아 글줄 정렬을 지킨다(#1781).
class BenefitIconTile extends StatelessWidget {
  const BenefitIconTile({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: OnCareSize.avatarLarge,
      height: OnCareSize.avatarLarge,
      alignment: Alignment.center,
      child: AppIcon(
        icon,
        size: OnCareSize.iconMedium,
        color: tokens.brand.primary,
      ),
    );
  }
}

/// 사용처 화면의 교환 카드 — 제목·설명·포인트·`교환` 버튼. (#1787)
///
/// 교환할 수 없으면 버튼을 막고 이유(모자란 포인트 등)를 버튼 왼쪽에 적는다.
class ShopItemCard extends StatelessWidget {
  const ShopItemCard({
    super.key,
    required this.item,
    required this.onExchange,
    this.busy = false,
  });

  final ShopItem item;

  /// null 이면 버튼이 막힌다(교환 불가이거나 다른 교환이 진행 중).
  final VoidCallback? onExchange;

  /// 이 항목의 교환 요청이 나가 있다.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final String? blocked = shopBlockLabel(l, item);
    return AppCard(
      key: ValueKey<String>('shop-item-${item.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              BenefitIconTile(icon: benefitIcon(item.id)),
              const SizedBox(width: OnCareSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            shopItemTitle(l, item),
                            style: tokens
                                .text(OnCareTypography.titleSmall)
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: OnCareSpacing.s8),
                        AppTag(
                          label: l.myPointsCost(item.cost),
                          tone: AppTagTone.brand,
                        ),
                      ],
                    ),
                    const SizedBox(height: OnCareSpacing.s4),
                    Text(
                      shopItemDescription(l, item),
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                    if (item.validDays > 0) ...<Widget>[
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(
                        l.myPointsValidDays(item.validDays),
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: blocked == null
                    ? const SizedBox.shrink()
                    : Text(
                        blocked,
                        key: ValueKey<String>('shop-blocked-${item.id}'),
                        style: tokens
                            .text(OnCareTypography.strong(OnCareTypography.caption))
                            .copyWith(color: OnCareColors.textSecondary),
                      ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              AppButton(
                key: ValueKey<String>('shop-exchange-${item.id}'),
                label: l.myPointsExchange,
                size: OnCareButtonSize.small,
                loading: busy,
                onPressed: item.available ? onExchange : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 쿠폰 상태 태그 — 사용 가능이면 D-n(브랜드), 아니면 상태(회색).
class CouponStatusTag extends StatelessWidget {
  const CouponStatusTag({super.key, required this.coupon});

  final Coupon coupon;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTag(
      key: ValueKey<String>('coupon-status-${coupon.id}'),
      label: couponStatusShort(l, coupon),
      tone: coupon.usable ? AppTagTone.brand : AppTagTone.neutral,
    );
  }
}

/// 내 혜택 목록의 쿠폰 한 줄 — 혜택, 마지막 사용일, 상태. 누르면 쿠폰 화면.
class CouponListCard extends StatelessWidget {
  const CouponListCard({super.key, required this.coupon, required this.onTap});

  final Coupon coupon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return Semantics(
      button: true,
      child: AppCard(
        key: ValueKey<String>('coupon-${coupon.id}'),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            BenefitIconTile(icon: benefitIcon(coupon.item)),
            const SizedBox(width: OnCareSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    couponBenefit(l, coupon),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.titleSmall)
                        .copyWith(
                          color: coupon.usable
                              ? OnCareColors.textPrimary
                              : OnCareColors.textTertiary,
                        ),
                  ),
                  const SizedBox(height: OnCareSpacing.s4),
                  Text(
                    l.myCouponUntil(formatCouponDate(coupon.expiresOn)),
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            CouponStatusTag(coupon: coupon),
            const SizedBox(width: OnCareSpacing.s4),
            const AppIcon(
              AppIcons.chevronRight,
              size: OnCareSize.iconMedium,
              color: OnCareColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

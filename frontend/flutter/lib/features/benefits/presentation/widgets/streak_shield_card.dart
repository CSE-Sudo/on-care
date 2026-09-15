import 'package:flutter/material.dart';

import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 내 혜택의 연속 기록 보호권 카드 — 보유 수와 보호한 날. (#1788)
///
/// 보호권은 쿠폰처럼 코드·기한이 없다. 한 장씩 늘어놓지 않고 몇 개 있는지와
/// 어느 날을 이어 붙였는지만 보여 준다. 쓰는 곳은 운동 현황이라 그 안내를 함께 적는다.
class StreakShieldSummaryCard extends StatelessWidget {
  const StreakShieldSummaryCard({super.key, required this.shields});

  final StreakShields shields;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      key: const ValueKey<String>('streak-shield-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              BenefitIconTile(icon: benefitIcon(kStreakShieldItem)),
              const SizedBox(width: OnCareSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.myShopStreakShieldTitle,
                      style: tokens
                          .text(OnCareTypography.titleSmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                    const SizedBox(height: OnCareSpacing.s4),
                    Text(
                      l.myBenefitsShieldGuide,
                      style: tokens
                          .text(OnCareTypography.caption)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              AppTag(
                key: const ValueKey<String>('streak-shield-held'),
                label: l.myBenefitsShieldHeld(shields.held, shields.maxHeld),
                tone: shields.held > 0 ? AppTagTone.brand : AppTagTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s16),
          Text(
            l.myBenefitsShieldUsedTitle,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          if (shields.used.isEmpty)
            Text(
              l.myBenefitsShieldNoneUsed,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textTertiary),
            )
          else
            for (final StreakShieldUse use in shields.used)
              Padding(
                key: ValueKey<String>('streak-shield-used-${use.date}'),
                padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        formatCouponDate(use.date),
                        style: tokens
                            .text(OnCareTypography.numeric(OnCareTypography.bodySmall))
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                    Text(
                      l.exStreakProtected,
                      style: tokens
                          .text(OnCareTypography.caption)
                          .copyWith(color: OnCareColors.textTertiary),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

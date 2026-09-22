import 'package:flutter/material.dart';

import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/diet_tray.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 포인트 화면의 분석용 식판 카드. (#2150)
///
/// 교환 카드가 아니라 달성 보상 카드다 — 포인트 가격 대신 `무료` 태그를 달고, 최근
/// 28일 사진 기록일을 막대로 보여 준다. 기록 그래프 바로 아래에 서서 "며칠 더 찍으면
/// 받는가" 가 기록 흐름과 한눈에 이어진다.
///
/// 상태마다 아래 줄이 바뀐다:
/// - 진행 중 — 남은 날(담당이 없으면 연결하라는 안내), 버튼 없음
/// - 받을 수 있음 — `받기`
/// - 쿠폰 받음 — 어느 헬스장에서 받는지, 가기 전에 트레이너에게 물어보라는 안내와
///   `쿠폰 보기`. 쿠폰은 기한이 없다.
/// - 식판 받음 — 받았다는 한 줄. 1인 1회라 더 할 것이 없다.
///
/// 카드 맨 아래에 유의사항(1인 1회·세는 날·수령 기한·조건 변경)을 늘 적는다.
class DietTrayCard extends StatelessWidget {
  const DietTrayCard({
    super.key,
    required this.tray,
    required this.onClaim,
    required this.onViewCoupon,
    this.busy = false,
  });

  final DietTray tray;

  /// null 이면 `받기` 가 막힌다(다른 요청이 진행 중).
  final VoidCallback? onClaim;

  /// 받은 수령 쿠폰을 연다.
  final ValueChanged<Coupon> onViewCoupon;

  /// 받기 요청이 나가 있다.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final Coupon? coupon = tray.coupon;
    final bool received = tray.status == DietTrayStatus.received;
    return AppCard(
      key: const Key('dietTrayCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              BenefitIconTile(icon: benefitIcon(kDietTrayItem)),
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
                            l.myDietTrayTitle,
                            style: tokens
                                .text(OnCareTypography.titleSmall)
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: OnCareSpacing.s8),
                        AppTag(label: l.myDietTrayFree, tone: AppTagTone.brand),
                      ],
                    ),
                    const SizedBox(height: OnCareSpacing.s4),
                    Text(
                      keepWords(
                        l.myDietTrayDescription(
                          tray.windowDays,
                          tray.requiredDays,
                        ),
                      ),
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 받은 뒤에는 막대를 두지 않는다 — 더 채울 것이 없다.
          if (!received && tray.status != DietTrayStatus.issued) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l.myDietTrayProgressLabel(tray.windowDays),
                    style: tokens
                        .text(OnCareTypography.label)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Text(
                  // 채운 뒤에는 `20 / 20일` 에서 멈춘다 — `27 / 20일` 은 목표를 넘긴
                  // 것이 아니라 셈이 틀린 것처럼 읽힌다.
                  l.myDietTrayProgress(
                    tray.photoDays.clamp(0, tray.requiredDays),
                    tray.requiredDays,
                  ),
                  key: const Key('dietTrayProgress'),
                  style: OnCareTypography.numeric(
                    tokens.text(OnCareTypography.titleSmall),
                  ).copyWith(color: tokens.brand.primary),
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s8),
            AppProgressBar(
              value: tray.requiredDays <= 0
                  ? 0
                  : tray.photoDays / tray.requiredDays,
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  keepWords(_statusLine(l, coupon)),
                  key: const Key('dietTrayStatusLine'),
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.caption))
                      .copyWith(
                        color:
                            received || tray.status == DietTrayStatus.claimable
                            ? tokens.brand.primary
                            : OnCareColors.textSecondary,
                      ),
                ),
              ),
              if (tray.status == DietTrayStatus.claimable) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                AppButton(
                  key: const Key('dietTrayClaim'),
                  label: l.myDietTrayClaim,
                  size: OnCareButtonSize.small,
                  loading: busy,
                  onPressed: onClaim,
                ),
              ],
              if (tray.status == DietTrayStatus.issued &&
                  coupon != null) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                AppButton(
                  key: const Key('dietTrayViewCoupon'),
                  label: l.myDietTrayViewCoupon,
                  variant: AppButtonVariant.secondary,
                  size: OnCareButtonSize.small,
                  onPressed: () => onViewCoupon(coupon),
                ),
              ],
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            keepWords(l.myDietTrayNotice),
            key: const Key('dietTrayNotice'),
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ],
      ),
    );
  }

  String _statusLine(AppLocalizations l, Coupon? coupon) =>
      switch (tray.status) {
        DietTrayStatus.received => l.myDietTrayReceived,
        DietTrayStatus.issued when coupon != null => l.myDietTrayIssued(
          coupon.gymName,
        ),
        DietTrayStatus.claimable => l.myDietTrayClaimable,
        _ when !tray.hasTrainer => l.myDietTrayNeedTrainer,
        _ => l.myDietTrayDaysLeft(tray.daysLeft),
      };
}

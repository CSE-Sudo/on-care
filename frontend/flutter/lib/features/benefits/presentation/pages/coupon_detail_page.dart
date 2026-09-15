import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 쿠폰 한 장 — 혜택, 코드, (PT 재등록이면) 담당 트레이너·헬스장, 교환일,
/// 만료일(D-n), 상태. (#1787)
///
/// PT 재등록 쿠폰은 트레이너가 회원 상세에서 사용 처리하므로 여기에 버튼이 없다.
/// 건강식·보충제 쿠폰은 회원이 매장에서 코드를 보여 준 뒤 `사용 완료` 를 누른다 —
/// 파란 확인창을 한 번 거친다. 되돌리기는 없다.
///
/// 목록([myCouponsProvider])에서 이 쿠폰을 찾아 그린다. 사용 처리 뒤 목록을 다시
/// 읽으면 이 화면도 같은 값으로 바뀐다.
class CouponDetailPage extends ConsumerStatefulWidget {
  const CouponDetailPage({super.key, required this.couponId});

  final String couponId;

  @override
  ConsumerState<CouponDetailPage> createState() => _CouponDetailPageState();
}

class _CouponDetailPageState extends ConsumerState<CouponDetailPage> {
  bool _using = false;

  Future<void> _use(Coupon coupon) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.myCouponUseConfirmTitle,
      message: l.myCouponUseConfirmMessage,
      confirmLabel: l.myCouponUse,
      cancelLabel: l.myCancel,
    );
    if (!ok || !mounted || _using) return;
    setState(() => _using = true);
    try {
      await ref.read(benefitsRepositoryProvider).useCoupon(coupon.id);
      if (!mounted) return;
      ref.invalidate(myCouponsProvider);
      showAppToast(context, l.myCouponUseDone, type: AppToastType.success);
    } on Object {
      if (!mounted) return;
      ref.invalidate(myCouponsProvider);
      showAppToast(context, l.myCouponUseFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _using = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<Coupon>> coupons = ref.watch(myCouponsProvider);
    final Coupon? coupon = coupons.valueOrNull
        ?.where((Coupon c) => c.id == widget.couponId)
        .firstOrNull;
    return AppPage(
      key: const Key('couponDetailPage'),
      bottomInset: MediaQuery.paddingOf(context).bottom,
      header: AppTopBar(title: l.myBenefitsCoupons),
      children: coupon != null
          ? _details(context, l, coupon)
          : <Widget>[
              if (coupons.hasError && !coupons.hasValue)
                AppCard(
                  child: AppErrorState(
                    title: l.myBenefitsLoadFailed,
                    retryLabel: l.actionRetry,
                    onRetry: () => ref.invalidate(myCouponsProvider),
                    placement: AppStatePlacement.card,
                  ),
                )
              else if (!coupons.hasValue)
                const AppCard(
                  child: AppLoading(placement: AppStatePlacement.card),
                )
              else
                AppCard(
                  child: AppEmptyState(
                    title: l.myCouponNotFound,
                    icon: Icons.redeem_rounded,
                    placement: AppStatePlacement.card,
                  ),
                ),
            ],
    );
  }

  List<Widget> _details(BuildContext context, AppLocalizations l, Coupon coupon) {
    final OnCareTokens tokens = context.oncare;
    final bool byTrainer = coupon.redeemer == CouponRedeemer.trainer;
    final String expiry = formatCouponDate(coupon.expiresOn);
    return <Widget>[
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                BenefitIconTile(icon: benefitIcon(coupon.item)),
                const SizedBox(width: OnCareSpacing.s12),
                Expanded(
                  child: Text(
                    couponBenefit(l, coupon),
                    key: const Key('couponBenefit'),
                    style: tokens
                        .text(OnCareTypography.titleMedium)
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                CouponStatusTag(coupon: coupon),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s16),
            Container(
              padding: const EdgeInsets.all(OnCareSpacing.s16),
              decoration: const BoxDecoration(
                color: OnCareColors.surfaceInput,
                borderRadius: OnCareRadius.mdAll,
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    l.myCouponCode,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                  const SizedBox(height: OnCareSpacing.s4),
                  Text(
                    coupon.displayCode,
                    key: const Key('couponCode'),
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.titleLarge),
                    ).copyWith(
                      color: coupon.usable
                          ? OnCareColors.textPrimary
                          : OnCareColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: OnCareSpacing.s16),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s8),
            if (byTrainer) ...<Widget>[
              _InfoRow(label: l.myCouponTrainer, value: coupon.trainerName),
              _InfoRow(label: l.myCouponGym, value: coupon.gymName),
            ],
            _InfoRow(
              label: l.myCouponIssuedOn,
              value: formatCouponDate(coupon.issuedOn),
            ),
            _InfoRow(
              key: const Key('couponExpiry'),
              label: l.myCouponExpiry,
              value: coupon.usable
                  ? l.myCouponExpiryWithDday(
                      expiry,
                      couponDday(l, coupon.daysLeft),
                    )
                  : expiry,
            ),
            _InfoRow(label: l.myCouponStatus, value: couponStatusLabel(l, coupon)),
          ],
        ),
      ),
      const SizedBox(height: OnCareSpacing.s16),
      _Guide(text: byTrainer ? l.myCouponTrainerGuide : l.myCouponMemberGuide),
      const SizedBox(height: OnCareSpacing.s4),
      _Guide(text: l.myCouponExpireNotice),
      if (!byTrainer && coupon.usable) ...<Widget>[
        const SizedBox(height: OnCareSpacing.s16),
        AppButton(
          key: const Key('couponUseButton'),
          label: l.myCouponUse,
          size: OnCareButtonSize.large,
          fullWidth: true,
          loading: _using,
          onPressed: _using ? null : () => _use(coupon),
        ),
      ],
    ];
  }
}

/// 쿠폰 정보 한 줄 — 왼쪽 항목 이름, 오른쪽 값.
class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 안내 한 줄 — 작은 정보 아이콘과 설명.
class _Guide extends StatelessWidget {
  const _Guide({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.info_outline_rounded,
          size: OnCareSize.iconSmall,
          color: OnCareColors.textTertiary,
        ),
        const SizedBox(width: OnCareSpacing.s4),
        Expanded(
          child: Text(
            text,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

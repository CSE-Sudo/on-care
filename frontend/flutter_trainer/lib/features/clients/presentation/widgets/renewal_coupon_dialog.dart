import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_coupon_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/renewal_coupon.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원 상세의 `재등록 쿠폰` 배지가 여는 확인창. (#1787)
Future<void> showRenewalCouponDialog(
  BuildContext context, {
  required String clientId,
  required RenewalCoupon coupon,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => RenewalCouponDialog(clientId: clientId, coupon: coupon),
);

/// PT 재등록 할인 쿠폰 확인 — 혜택·교환일·만료일(D-n)과 되돌릴 수 없다는 경고,
/// `취소 / 사용 완료` 2열 버튼.
///
/// 코드 입력 단계가 없다. 트레이너가 이미 회원을 특정한 상세 화면에서 여는 창이라,
/// 코드를 받아 적는 일은 확인을 늘릴 뿐 잘못 처리할 여지를 줄이지 않는다.
///
/// `사용 완료` 는 빨간 채움이다 — 회원의 포인트로 산 쿠폰을 되돌릴 수 없게 쓰는,
/// 결과가 무거운 확정이기 때문이다(팀 확인창 규칙).
class RenewalCouponDialog extends ConsumerStatefulWidget {
  const RenewalCouponDialog({
    super.key,
    required this.clientId,
    required this.coupon,
  });

  final String clientId;
  final RenewalCoupon coupon;

  @override
  ConsumerState<RenewalCouponDialog> createState() =>
      _RenewalCouponDialogState();
}

class _RenewalCouponDialogState extends ConsumerState<RenewalCouponDialog> {
  /// 사용 처리 요청이 나가 있다. 두 번 눌러도 요청은 한 번이다(서버도 한 번만
  /// 처리하지만, 화면이 두 번째 응답을 기다리며 버튼을 열어 둘 이유가 없다).
  bool _saving = false;

  Future<void> _redeem() async {
    if (_saving) return;
    setState(() => _saving = true);
    final AppLocalizations l = AppLocalizations.of(context);
    String? failure;
    try {
      await ref
          .read(clientCouponRepositoryProvider)
          .redeem(widget.clientId, widget.coupon.id);
    } on AppError catch (error) {
      failure = serverDetailOr(
        l,
        error.message,
        l.clientRenewalCouponRedeemFailed,
      );
    } on Object {
      failure = l.clientRenewalCouponRedeemFailed;
    }
    if (!mounted) return;
    // 성공이든 실패든(그사이 만료·취소됐을 수 있다) 배지를 다시 읽는다.
    ref.invalidate(clientRenewalCouponsProvider(widget.clientId));
    // 알림은 창을 닫기 **전에** 띄운다. 루트 오버레이에 올라가므로 창이 닫혀도
    // 남는다 — 닫은 뒤에는 이 창의 context 로 오버레이를 찾을 수 없다.
    showAppToast(
      context,
      failure ?? l.clientRenewalCouponRedeemed,
      type: failure == null ? AppToastType.success : AppToastType.error,
    );
    Navigator.of(context).pop();
  }

  static String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}.'
      '${day.month.toString().padLeft(2, '0')}.'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final RenewalCoupon coupon = widget.coupon;
    final String expiresOn = _date(coupon.expiresOn);
    return AppDialog(
      key: const ValueKey<String>('renewal-coupon-dialog'),
      title: l.clientRenewalCouponTitle,
      showClose: false,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        confirmLabel: l.clientRenewalCouponRedeem,
        onConfirm: _saving ? null : _redeem,
        destructive: true,
        confirmLoading: _saving,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _InfoRow(
            label: l.clientRenewalCouponBenefitLabel,
            value: coupon.item == 'pt_renewal'
                ? l.clientRenewalCouponBenefit
                : coupon.benefit,
          ),
          _InfoRow(
            label: l.clientRenewalCouponIssuedOn,
            value: _date(coupon.issuedOn),
          ),
          _InfoRow(
            key: const ValueKey<String>('renewal-coupon-expiry'),
            label: l.clientRenewalCouponExpiry,
            value: coupon.daysLeft <= 0
                ? l.clientRenewalCouponExpiryToday(expiresOn)
                : l.clientRenewalCouponExpiryValue(expiresOn, coupon.daysLeft),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Container(
            padding: const EdgeInsets.all(OnCareSpacing.s12),
            decoration: BoxDecoration(
              color: OnCareColors.onWhite(
                OnCareColors.danger,
                OnCareAlpha.subtle,
              ),
              borderRadius: OnCareRadius.mdAll,
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  size: OnCareSize.iconSmall,
                  color: OnCareColors.danger,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Text(
                    l.clientRenewalCouponWarning,
                    key: const ValueKey<String>('renewal-coupon-warning'),
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                        .copyWith(color: OnCareColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

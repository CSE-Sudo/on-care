import 'package:flutter/material.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 위치정보 이용 동의 시트를 띄운다(#3136). 회원이 동의하면 `true`, 거부하거나
/// 닫으면 `false`.
///
/// 시트는 동의를 묻기만 한다 — 저장은 부르는 쪽이 `LocationConsentController`
/// 로 한다. 동의를 받아 저장한 다음에만 OS 위치 권한 창으로 넘어간다.
///
/// 찾기 화면은 하단 탭이 있는 셸 안쪽 내비게이터에 있다. 그 내비게이터로 띄우면
/// 하단 탭이 시트 위에 그려져 [동의]·[거부] 버튼을 덮는다 — 그래서 루트
/// 내비게이터로 띄운다.
Future<bool> showLocationConsentSheet(BuildContext context) async {
  final bool? agreed = await showAppSheet<bool>(
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (BuildContext context) => const LocationConsentSheet(),
  );
  return agreed ?? false;
}

/// 목적·항목·보관·제공·거부 시 영향을 한 장에 보이고 동의 여부를 묻는다.
class LocationConsentSheet extends StatelessWidget {
  const LocationConsentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle lead = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);
    final TextStyle label = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textPrimary);
    final TextStyle value = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textSecondary);
    final List<(String, String)> rows = <(String, String)>[
      (l.locationConsentPurposeLabel, l.locationConsentPurpose),
      (l.locationConsentItemsLabel, l.locationConsentItems),
      (l.locationConsentRetentionLabel, l.locationConsentRetention),
      (l.locationConsentRecipientLabel, l.locationConsentRecipient),
      (l.locationConsentRefuseLabel, l.locationConsentRefuse),
    ];
    return AppSheet(
      key: const ValueKey<String>('location-consent-sheet'),
      title: l.locationConsentTitle,
      footer: AppButtonPair(
        cancelKey: const ValueKey<String>('location-consent-decline'),
        confirmKey: const ValueKey<String>('location-consent-agree'),
        cancelLabel: l.locationConsentDecline,
        onCancel: () => Navigator.of(context).pop(false),
        confirmLabel: l.locationConsentAgree,
        onConfirm: () => Navigator.of(context).pop(true),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l.locationConsentLead, style: lead),
          const SizedBox(height: OnCareSpacing.s12),
          Container(
            key: const ValueKey<String>('location-consent-details'),
            padding: const EdgeInsets.all(OnCareSpacing.s12),
            decoration: BoxDecoration(
              color: OnCareColors.surfaceCard,
              borderRadius: OnCareRadius.mdAll,
              border: Border.all(color: OnCareColors.lineSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final (int i, (String, String) row)
                    in rows.indexed) ...<Widget>[
                  if (i > 0) const SizedBox(height: OnCareSpacing.s8),
                  Text(row.$1, style: label),
                  const SizedBox(height: OnCareSpacing.s2),
                  Text(row.$2, style: value),
                ],
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              key: const ValueKey<String>('location-consent-terms'),
              label: l.locationConsentViewTerms,
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
              // 시트를 닫지 않고 그 위로 약관을 연다 — 읽고 돌아와 바로 고른다.
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const LegalDocumentPage(document: 'location'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

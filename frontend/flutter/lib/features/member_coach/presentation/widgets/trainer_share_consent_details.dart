import 'package:flutter/material.dart';

import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너 데이터 공유 동의의 '자세히' 펼침. (#2826)
///
/// 담당 연결이 성립하는 두 순간 — 동기화 코드 발급 시트와 담당 요청 수락 동의창 —
/// 이 같은 내용을 같은 모양으로 보여 준다. 짧은 본문은 각 화면이 그대로 두고,
/// 받는 사람·공유 항목·이용 목적·이용 기간(철회 뒤에도 남는 기록)·거부할 권리를
/// 한 줄씩 여기에 모은다. 처음에는 접혀 있어 시트·동의창이 길어지지 않는다.
///
/// 공유 항목과 철회 뒤 남는 기록은 개인정보 처리방침 5항과 같은 말이어야 한다.
class TrainerShareConsentDetails extends StatefulWidget {
  const TrainerShareConsentDetails({super.key});

  @override
  State<TrainerShareConsentDetails> createState() =>
      _TrainerShareConsentDetailsState();
}

class _TrainerShareConsentDetailsState
    extends State<TrainerShareConsentDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle label = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textPrimary);
    final TextStyle value = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textSecondary);
    final List<(String, String)> rows = <(String, String)>[
      (l.trainerShareRecipientLabel, l.trainerShareRecipient),
      (l.trainerShareItemsLabel, l.trainerShareItems),
      (l.trainerSharePurposeLabel, l.trainerSharePurpose),
      (l.trainerSharePeriodLabel, l.trainerSharePeriod),
      (l.trainerShareRefuseLabel, l.trainerShareRefuse),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppButton(
          key: const ValueKey<String>('trainer-share-details-toggle'),
          label: _open ? l.trainerShareDetailLess : l.trainerShareDetailMore,
          onPressed: () => setState(() => _open = !_open),
          variant: AppButtonVariant.text,
          size: OnCareButtonSize.small,
        ),
        if (_open)
          Container(
            key: const ValueKey<String>('trainer-share-details'),
            width: double.infinity,
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
      ],
    );
  }
}

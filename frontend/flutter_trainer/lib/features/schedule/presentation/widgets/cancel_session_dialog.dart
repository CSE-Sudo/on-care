import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 취소 확인 — 주체를 고르고 (선택) 사유를 남긴다. (#871)
///
/// 주체에 기본값을 두지 않는다. 무엇이든 기본으로 저장되면 그 값이 사실인지 알
/// 수 없고, 나중에 "고객 취소가 몇 건이었나" 를 읽을 때 그대로 거짓이 된다.
class CancelSessionDialog extends StatefulWidget {
  const CancelSessionDialog({super.key, required this.session});

  final ScheduleSession session;

  @override
  State<CancelSessionDialog> createState() => _CancelSessionDialogState();
}

class _CancelSessionDialogState extends State<CancelSessionDialog> {
  final TextEditingController _reason = TextEditingController();
  String? _source;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final s = widget.session;
    return AppDialog(
      title: l.schedCancelTitle,
      showClose: false,
      // AppButtonPair 와 같은 배치 — 확정 버튼에 키를 달아야 해서 직접 둔다.
      footer: Row(
        children: <Widget>[
          Expanded(
            child: AppButton(
              label: l.actionCancel,
              onPressed: () => Navigator.of(context).pop(),
              variant: AppButtonVariant.secondary,
              fullWidth: true,
            ),
          ),
          const SizedBox(width: OnCareSpacing.buttonGap),
          Expanded(
            child: AppButton(
              key: const ValueKey<String>('session-cancel-confirm'),
              label: l.schedCancel,
              variant: AppButtonVariant.destructive,
              fullWidth: true,
              // 주체를 고르기 전에는 저장할 수 없다 — 기본값으로 채우면 그 값이
              // 사실인지 알 수 없다.
              onPressed: _source == null
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop((source: _source!, reason: _reason.text.trim())),
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.schedCancelConfirm(s.time, s.clientName)),
          const SizedBox(height: OnCareSpacing.s16),
          Text(
            l.schedCancelSource,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              for (final source in CancellationSource.all)
                AppChoiceChip(
                  key: ValueKey<String>('cancel-source-$source'),
                  label: cancellationSourceLabel(l, source),
                  selected: _source == source,
                  onSelected: (_) => setState(() => _source = source),
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppTextField(
            key: const ValueKey<String>('cancel-reason-input'),
            controller: _reason,
            maxLength: 200,
            hint: l.schedCancelReasonHint,
          ),
        ],
      ),
    );
  }
}

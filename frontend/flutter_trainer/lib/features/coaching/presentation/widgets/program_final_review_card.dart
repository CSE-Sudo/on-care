import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `일정 추가` 를 누르기 전 한 번 더 확인한다(#1029) — 이 버튼 하나가
/// 배정과 PT 일정 등록을 함께 하므로, 어느 날짜·시각으로 스케줄에
/// 올라가는지 미리 말해야 한다. `showRoutineSuggestionConfirmDialog` 와
/// 같은 모양을 쓴다.
Future<bool?> showProgramAssignConfirmDialog(
  BuildContext context, {
  required String clientName,
  required DateTime registerDate,
  required TimeOfDay registerStartTime,
  required TimeOfDay registerEndTime,
}) {
  return showAppDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final AppLocalizations l = AppLocalizations.of(dialogContext);
      return AppDialog(
        key: const ValueKey<String>('program-assign-confirm'),
        title: l.programAssignConfirmTitle,
        showClose: false,
        // 버튼마다 테스트가 찾는 Key 가 있어 AppButtonPair 대신 같은 모양의
        // Row 로 둔다.
        footer: Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                key: const ValueKey<String>('program-assign-confirm-cancel'),
                label: l.actionCancel,
                variant: AppButtonVariant.secondary,
                fullWidth: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
            ),
            const SizedBox(width: OnCareSpacing.buttonGap),
            Expanded(
              child: AppButton(
                key: const ValueKey<String>('program-assign-confirm-submit'),
                label: l.programEditorAddSchedule,
                fullWidth: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ),
          ],
        ),
        child: Text(
          l.programAssignConfirmBody(
            clientName,
            ymd(registerDate),
            '${registerStartTime.format(dialogContext)} – '
            '${registerEndTime.format(dialogContext)}',
          ),
          style: dialogContext.oncare
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
      );
    },
  );
}

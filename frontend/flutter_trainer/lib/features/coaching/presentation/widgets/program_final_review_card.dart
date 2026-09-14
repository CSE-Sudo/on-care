import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 확인창에서 고른 결과 — 연결할 기존 세션 id, 새 일정이면 null(#1581).
typedef ProgramAssignConfirmation = ({String? sessionId});

/// `일정 추가` 를 누르기 전 한 번 더 확인한다(#1029) — 이 버튼 하나가
/// 배정과 PT 일정 등록을 함께 하므로, 어느 날짜·시각으로 스케줄에
/// 올라가는지 미리 말해야 한다. `showRoutineSuggestionConfirmDialog` 와
/// 같은 모양을 쓴다.
///
/// [candidates] 는 고른 시간대와 겹치는 그날 예정 PT 다(#1581). 없으면 고른
/// 시간으로 새 일정을 만든다고, 하나면 그 회차에 연결되고 고른 시간은 쓰지
/// 않는다고 저장 전에 말한다. 여럿이면 연결할 회차를 고르기 전까지 확인 버튼이
/// 잠긴다 — 가장 이른 회차를 멋대로 고르지 않는다. 취소하면 null.
Future<ProgramAssignConfirmation?> showProgramAssignConfirmDialog(
  BuildContext context, {
  required String clientName,
  required DateTime registerDate,
  required TimeOfDay registerStartTime,
  required TimeOfDay registerEndTime,
  List<ScheduleSession> candidates = const <ScheduleSession>[],
}) {
  String? chosen = candidates.length == 1 ? candidates.single.id : null;
  return showAppDialog<ProgramAssignConfirmation>(
    context: context,
    builder: (dialogContext) {
      final AppLocalizations l = AppLocalizations.of(dialogContext);
      final selectedRange =
          '${registerStartTime.format(dialogContext)} – '
          '${registerEndTime.format(dialogContext)}';
      final TextStyle bodyStyle = dialogContext.oncare
          .text(OnCareTypography.bodySmall)
          .copyWith(color: OnCareColors.textSecondary);
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final Widget body;
          if (candidates.isEmpty) {
            body = Text(
              l.programAssignConfirmBody(
                clientName,
                ymd(registerDate),
                selectedRange,
              ),
              style: bodyStyle,
            );
          } else if (candidates.length == 1) {
            body = Text(
              l.programAssignConfirmAttachBody(
                clientName,
                ymd(registerDate),
                timeRangeLabel(l, candidates.single),
                selectedRange,
              ),
              key: const ValueKey<String>('program-assign-confirm-attach'),
              style: bodyStyle,
            );
          } else {
            body = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l.programAssignConfirmChooseBody(
                    clientName,
                    ymd(registerDate),
                    selectedRange,
                  ),
                  style: bodyStyle,
                ),
                const SizedBox(height: OnCareSpacing.s8),
                for (final session in candidates)
                  AppListRow(
                    key: ValueKey<String>(
                      'program-attach-candidate-${session.id}',
                    ),
                    selected: chosen == session.id,
                    leading: Icon(
                      chosen == session.id
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: OnCareSize.iconMedium,
                      color: chosen == session.id
                          ? context.oncare.brand.primary
                          : OnCareColors.textTertiary,
                    ),
                    title: timeRangeLabel(l, session),
                    onTap: () => setDialogState(() => chosen = session.id),
                  ),
              ],
            );
          }
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
                    key: const ValueKey<String>(
                      'program-assign-confirm-cancel',
                    ),
                    label: l.actionCancel,
                    variant: AppButtonVariant.secondary,
                    fullWidth: true,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
                const SizedBox(width: OnCareSpacing.buttonGap),
                Expanded(
                  child: AppButton(
                    key: const ValueKey<String>(
                      'program-assign-confirm-submit',
                    ),
                    label: l.programEditorAddSchedule,
                    fullWidth: true,
                    onPressed: candidates.length > 1 && chosen == null
                        ? null
                        : () => Navigator.of(
                            dialogContext,
                          ).pop((sessionId: chosen)),
                  ),
                ),
              ],
            ),
            child: body,
          );
        },
      );
    },
  );
}

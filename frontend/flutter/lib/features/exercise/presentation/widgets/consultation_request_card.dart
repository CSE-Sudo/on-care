import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/utils/exercise_goal_label.dart';
import 'package:oncare/features/exercise/presentation/utils/preferred_time_format.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 카드 왼쪽 아이콘 칸 크기.
const double _leadingSize = 40;

/// 목표·메시지 줄의 라벨 칸 폭.
const double _detailLabelWidth = 72;

/// 상담 요청 한 건의 카드 표시. 운동 탭 요약(`gym_tab.dart`)과 "내 상담 요청"
/// 전체 내역 화면이 같은 모양을 쓴다 — 두 화면이 각자 그리면 상태 배지·거절
/// 사유 문구가 조용히 갈라진다(#948).
class ConsultationRequestCard extends StatelessWidget {
  const ConsultationRequestCard({
    required this.request,
    this.onCancel,
    super.key,
  });

  final ConsultationRequest request;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String targetName = request.trainerName ?? '';
    final String targetType =
        request.trainerGymName ?? request.trainerName ?? '';
    final (String status, AppTagTone statusTone) = switch (request.status) {
      ConsultationStatus.pending => (
        l.exConsultPendingStatus,
        AppTagTone.brand,
      ),
      ConsultationStatus.accepted => (
        l.exConsultAcceptedStatus,
        AppTagTone.success,
      ),
      ConsultationStatus.rejected => (
        l.exConsultRejectedStatus,
        AppTagTone.danger,
      ),
      ConsultationStatus.cancelled => (l.errorCancelled, AppTagTone.neutral),
      // 트레이너가 시간 안에 확인하지 않아 자리가 풀린 요청 — 거절과 구분한다.
      // 회원이 할 일이 다르다: 다른 시간으로 다시 신청하면 된다. (#1873)
      ConsultationStatus.expired => (l.exConsultExpired, AppTagTone.neutral),
    };
    final Widget? outcome = _outcomeNote(context, l);

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: _leadingSize,
            height: _leadingSize,
            alignment: Alignment.center,
            child: AppIcon(
              AppIcons.gym,
              size: OnCareSize.iconMedium,
              color: tokens.brand.primary,
            ),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        targetName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    AppTag(label: status, tone: statusTone),
                  ],
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  targetType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                Text(
                  // 자리를 고른 요청은 그 자리의 시작–종료를 그리고, 승인되면
                  // **확정 일시**로 밝힌다 — 승인 뒤에도 회원이 언제로 잡혔는지
                  // 여기서 확인한다(#1873). 자리 선택 이전 요청은 적어 보낸 희망
                  // 시각이 그대로 보인다.
                  request.status == ConsultationStatus.accepted &&
                          request.slotStartsAt != null
                      ? '${l.exConsultConfirmedAt} · '
                            '${consultationTimeLabel(context, l, request)}'
                      : consultationTimeLabel(context, l, request),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                _DetailLine(label: l.exExerciseGoal, value: _goalLabel(l)),
                if ((request.message ?? '').trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s4),
                  _DetailLine(
                    label: l.exConsultMessage,
                    value: request.message!.trim(),
                  ),
                ],
                if (onCancel != null) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      key: ValueKey<String>(
                        'cancel-consultation-${request.id}',
                      ),
                      label: l.actionCancel,
                      onPressed: onCancel,
                      variant: AppButtonVariant.destructiveText,
                      size: OnCareButtonSize.small,
                    ),
                  ),
                ],
                if (outcome != null) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s8),
                  outcome,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 처리된 요청에 붙는 결과 안내. 대기 중이면 null. (#473)
  Widget? _outcomeNote(BuildContext context, AppLocalizations l) {
    switch (request.status) {
      case ConsultationStatus.pending:
        return null;
      case ConsultationStatus.accepted:
        return _OutcomeNote(
          key: const Key('consult-outcome-accepted'),
          tone: context.oncare.brand.primary,
          text: l.exConsultAcceptedGuide,
        );
      case ConsultationStatus.rejected:
        final String? note = request.decisionNote;
        return _OutcomeNote(
          key: const Key('consult-outcome-rejected'),
          tone: OnCareColors.textTertiary,
          label: note == null ? null : l.exConsultRejectedReasonLabel,
          text: note ?? l.exConsultRejectedNoReason,
        );
      case ConsultationStatus.cancelled:
        return null;
      case ConsultationStatus.expired:
        return _OutcomeNote(
          key: const Key('consult-outcome-expired'),
          tone: OnCareColors.textTertiary,
          text: l.exConsultExpiredBody,
        );
    }
  }

  String _goalLabel(AppLocalizations l) =>
      exerciseGoalLabel(l, request.exerciseGoal);
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = context.oncare.text(OnCareTypography.bodySmall);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: _detailLabelWidth,
          child: Text(
            label,
            style: style.copyWith(color: OnCareColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: style.copyWith(color: OnCareColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// 상태 카드 하단의 결과 안내 한 덩어리 — 승인 안내 또는 거절 사유.
class _OutcomeNote extends StatelessWidget {
  const _OutcomeNote({
    required this.tone,
    required this.text,
    this.label,
    super.key,
  });

  final Color tone;
  final String? label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
      decoration: BoxDecoration(
        color: OnCareColors.onWhite(tone, OnCareAlpha.subtle),
        borderRadius: OnCareRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (label != null) ...<Widget>[
            Text(
              label!,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: tone),
            ),
            const SizedBox(height: OnCareSpacing.s2),
          ],
          Text(
            text,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

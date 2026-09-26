/// 내가 보낸 주간 피드백 한 주치 — 고른 그 문장으로 되읽어 준다. (#2232)
///
/// 보여 주는 주는 **직전 주 하나**다. 더 옛 답을 쌓아 보여 줄 수도 있지만,
/// 회원이 되돌아볼 이유가 있는 것은 방금 낸 답이다. 그보다 옛 답은 트레이너가
/// 이미 읽고 다음 주 처방에 썼으니, 회원 화면에서 그것은 목록이 아니라
/// 지나간 일이다.
library;

import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/weekly_feedback_labels.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 보낸 답 한 장. 아직 안 낸 주면 안내와 함께 빈 카드가 선다.
class SentWeeklyFeedbackCard extends StatelessWidget {
  /// Creates the card.
  const SentWeeklyFeedbackCard({
    required this.feedback,
    required this.onSendNow,
    super.key,
  });

  /// 직전 주 답. `submitted` 가 false 면 아직 안 낸 주다.
  final MemberWeeklyFeedback feedback;

  /// `지금 피드백 보내기`. 이미 낸 주에서는 다시 보내는 길이 된다 —
  /// 일요일을 놓쳐도, 답을 고쳐 적고 싶어도 여기서 열 수 있어야 한다.
  final VoidCallback onSendNow;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      key: const ValueKey<String>('my-weekly-feedback-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(title: l.myWeeklyFeedbackSectionTitle),
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            '${weekRangeLabel(l, feedback.weekStart)} · '
            '${l.myWeeklyFeedbackOnlyLastWeek}',
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (!feedback.submitted)
            AppEmptyState(
              title: l.myWeeklyFeedbackEmpty,
              icon: AppIcons.document,
              placement: AppStatePlacement.card,
            )
          else ...<Widget>[
            _Answer(
              id: 'condition',
              label: l.myWeeklyFeedbackConditionLabel,
              value:
                  '${feedback.condition!.emoji} '
                  '${weekConditionLabel(l, feedback.condition!)}',
              // 답한 문장 그대로 두되, 트레이너가 눈여겨볼 답만 색을 준다.
              // 매주 무언가를 빨갛게 짚으면 그 색이 아무 뜻도 없어진다.
              alarming: feedback.condition!.needsAttention,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _Answer(
              id: 'intensity',
              label: l.myWeeklyFeedbackIntensityLabel,
              value: weekIntensityLabel(l, feedback.intensity!),
              alarming: feedback.intensity!.needsAttention,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _Answer(
              id: 'pain',
              label: l.myWeeklyFeedbackPainLabel,
              value: _painText(l),
              alarming: feedback.hasPain,
            ),
            if (feedback.note.isNotEmpty) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s12),
              AppTile(
                key: const ValueKey<String>('my-weekly-feedback-note'),
                tone: AppTileTone.neutral,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.myWeeklyFeedbackNoteLabel,
                      style: tokens
                          .text(OnCareTypography.caption)
                          .copyWith(color: OnCareColors.textTertiary),
                    ),
                    const SizedBox(height: OnCareSpacing.s4),
                    Text(
                      feedback.note,
                      style: tokens.text(OnCareTypography.bodySmall),
                    ),
                  ],
                ),
              ),
            ],
            if (feedback.submittedAt != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              Text(
                l.myWeeklyFeedbackSentAt(
                  feedback.submittedAt!.month,
                  feedback.submittedAt!.day,
                ),
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
          ],
          const SizedBox(height: OnCareSpacing.s16),
          AppButton(
            key: const ValueKey<String>('my-weekly-feedback-send-now'),
            label: feedback.submitted
                ? l.weeklyFeedbackResend
                : l.weeklyFeedbackNowButton,
            variant: feedback.submitted
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            onPressed: onSendNow,
            fullWidth: true,
          ),
        ],
      ),
    );
  }

  /// 통증 한 줄 — 없으면 `없음`, 날짜를 적었으면 함께.
  String _painText(AppLocalizations l) {
    if (!feedback.hasPain) return l.myWeeklyFeedbackPainNone;
    final DateTime? on = feedback.painOn;
    if (on == null) return feedback.painArea;
    return l.myWeeklyFeedbackPainWithDate(feedback.painArea, on.month, on.day);
  }
}

/// `컨디션 — 지쳤어요` 한 줄.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.id,
    required this.label,
    required this.value,
    required this.alarming,
  });

  final String id;
  final String label;
  final String value;
  final bool alarming;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      key: ValueKey<String>('my-weekly-feedback-$id'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: OnCareSpacing.s48 + OnCareSpacing.s24,
          child: Text(
            label,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                .copyWith(
                  color: alarming
                      ? OnCareColors.danger
                      : OnCareColors.textPrimary,
                ),
          ),
        ),
      ],
    );
  }
}

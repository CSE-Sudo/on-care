import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_card_header.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// ① 회원이 낸 세 문항. (#2232)
///
/// 확인 단계의 **첫 카드**다. 수치를 먼저 읽으면 같은 한 주가 `게으름` 으로
/// 읽히고, 그 판정을 세운 뒤에 회원의 말을 보면 이미 늦다 — `무릎이 아팠어요`
/// 는 수치를 다시 읽게 만드는 말이지 수치를 확인해 주는 말이 아니다.
///
/// 여기 없는 것이 중요하다 — **트레이너가 고쳐 쓸 수 있는 자리가 없다.**
/// 회원이 한 말이지 트레이너가 정리한 말이 아니라서, 고칠 수 있게 두면 다음
/// 주에 무엇이 회원의 말이고 무엇이 우리 해석인지 아무도 구분하지 못한다.
class MemberFeedbackCard extends StatelessWidget {
  /// Creates the card.
  const MemberFeedbackCard({super.key, required this.feedback});

  /// 아직 안 냈으면 null.
  final MemberWeeklyFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final MemberWeeklyFeedback? given = feedback;
    if (given == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ReportCardHeader(number: 1, title: l.reportsMemberFeedbackTitle),
            const SizedBox(height: OnCareSpacing.s12),
            AppEmptyState(
              key: const ValueKey<String>('report-feedback-empty'),
              title: l.reportsMemberFeedbackNone,
              // 빈 자리가 무엇을 뜻하는지 말해 준다 — 기능이 고장 난 것이 아니라
              // 회원이 아직 답하지 않은 것이다.
              message: l.reportsMemberFeedbackNoneHint,
              icon: Icons.chat_bubble_outline_rounded,
              placement: AppStatePlacement.card,
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ReportCardHeader(
            number: 1,
            title: l.reportsMemberFeedbackTitle,
            // 언제 낸 답인지를 제목 줄에 적는다 — 주가 끝난 뒤에 받는 답이라,
            // 날짜가 없으면 이번 주 도중에 쓴 말처럼 읽힌다.
            subtitle: l.reportsMemberFeedbackMeta(
              l.dateMonthDay(given.submittedOn.month, given.submittedOn.day),
            ),
            trailing: given.needsAttention
                ? AppTag(
                    label: l.reportsMemberFeedbackAttention,
                    tone: AppTagTone.danger,
                  )
                : null,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
              final Widget answers = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Answer(
                    keyName: 'report-feedback-condition',
                    label: l.reportsMemberFeedbackConditionLabel,
                    value:
                        '${conditionEmoji(given.condition)} ${conditionLabel(l, given.condition)}',
                    alarming: given.condition.needsAttention,
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  _Answer(
                    keyName: 'report-feedback-intensity',
                    label: l.reportsMemberFeedbackIntensityLabel,
                    value: intensityLabel(l, given.intensity),
                    alarming: given.intensity.needsAttention,
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  _Answer(
                    keyName: 'report-feedback-pain',
                    label: l.reportsMemberFeedbackPainLabel,
                    // 통증은 `없음` 도 답이다. 비워 두면 안 물어본 것처럼 보인다.
                    value: given.hasPain
                        ? (given.painOn == null
                              ? given.painArea
                              : l.reportsMemberFeedbackPainOn(
                                  given.painArea,
                                  l.dateMonthDay(
                                    given.painOn!.month,
                                    given.painOn!.day,
                                  ),
                                ))
                        : l.reportsMemberFeedbackPainNone,
                    alarming: given.hasPain,
                  ),
                ],
              );
              if (given.note.isEmpty) return answers;
              final Widget note = AppTile(
                tone: AppTileTone.neutral,
                child: Text(
                  given.note,
                  key: const ValueKey<String>('report-feedback-note'),
                  style: tokens.text(OnCareTypography.bodySmall),
                ),
              );
              // 넓은 화면에서는 세 답과 회원이 쓴 말을 **나란히** 둔다. 위아래로
              // 쌓으면 짧은 답 세 줄 옆이 통째로 비고, 정작 가장 긴 글인 회원의
              // 말은 그 아래로 밀린다.
              if (constraints.maxWidth < _sideBySideMinWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    answers,
                    const SizedBox(height: OnCareSpacing.s12),
                    note,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: _answersWidth, child: answers),
                    const SizedBox(width: OnCareSpacing.s16),
                    Expanded(child: note),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 세 답 칸의 폭 — 가장 긴 답(`오른 무릎 (9월 17일)`)이 한 줄에 서는 폭.
const double _answersWidth = 300;

/// 회원의 말을 세 답 옆에 둘 수 있는 최소 폭.
const double _sideBySideMinWidth = 560;

/// 컨디션 답의 얼굴 — 회원 앱에서 고른 그 얼굴 그대로. (#2232)
String conditionEmoji(WeekCondition condition) => switch (condition) {
  WeekCondition.great => '😄',
  WeekCondition.good => '🙂',
  WeekCondition.ok => '😐',
  WeekCondition.tired => '😩',
  WeekCondition.bad => '😣',
};

/// 컨디션 답의 로케일 이름.
String conditionLabel(AppLocalizations l, WeekCondition condition) =>
    switch (condition) {
      WeekCondition.great => l.reportsMemberFeedbackConditionGreat,
      WeekCondition.good => l.reportsMemberFeedbackConditionGood,
      WeekCondition.ok => l.reportsMemberFeedbackConditionOk,
      WeekCondition.tired => l.reportsMemberFeedbackConditionTired,
      WeekCondition.bad => l.reportsMemberFeedbackConditionBad,
    };

/// 강도 답의 로케일 이름.
String intensityLabel(AppLocalizations l, WeekIntensity intensity) =>
    switch (intensity) {
      WeekIntensity.tooEasy => l.reportsMemberFeedbackIntensityTooEasy,
      WeekIntensity.right => l.reportsMemberFeedbackIntensityRight,
      WeekIntensity.hard => l.reportsMemberFeedbackIntensityHard,
      WeekIntensity.tooHard => l.reportsMemberFeedbackIntensityTooHard,
    };

/// `문항 — 답` 한 줄.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.keyName,
    required this.label,
    required this.value,
    required this.alarming,
  });

  final String keyName;
  final String label;
  final String value;
  final bool alarming;

  /// 문항 이름이 차지하는 폭. 세 줄의 답이 같은 자리에서 시작해야 눈이
  /// 세로로 훑을 수 있다.
  static const double _labelWidth = 72;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      key: ValueKey<String>(keyName),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: _labelWidth,
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

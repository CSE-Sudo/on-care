import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
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
  const MemberFeedbackCard({
    super.key,
    required this.feedback,
    this.failed = false,
  });

  /// 아직 안 냈으면 null.
  final MemberWeeklyFeedback? feedback;

  /// 답을 읽지 못했다(#3246). 그때 빈 칸은 `미응답` 이 아니라 `불러오지 못함`
  /// 이다 — 답한 회원을 안 답한 회원으로 그리지 않는다.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final MemberWeeklyFeedback? given = feedback;
    // 안 낸 주에도 칸은 그대로 선다(#2450). 칸이 사라지면 답한 주와 안 한 주의
    // 카드 모양이 달라 나란히 비교가 안 되고, 무엇을 안 물어본 것인지 무엇에
    // 안 답한 것인지 구분되지 않는다.
    final String unanswered = failed
        ? l.reportsMemberFeedbackLoadFailed
        : l.reportsMemberFeedbackUnanswered;
    final Widget answers = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _answer(
          keyName: 'report-feedback-condition',
          label: l.reportsMemberFeedbackConditionLabel,
          value: given == null
              ? null
              : '${conditionEmoji(given.condition)} ${conditionLabel(l, given.condition)}',
          unanswered: unanswered,
          alarming: given?.condition.needsAttention ?? false,
        ),
        const SizedBox(height: OnCareSpacing.s8),
        _answer(
          keyName: 'report-feedback-intensity',
          label: l.reportsMemberFeedbackIntensityLabel,
          value: given == null ? null : intensityLabel(l, given.intensity),
          unanswered: unanswered,
          alarming: given?.intensity.needsAttention ?? false,
        ),
        const SizedBox(height: OnCareSpacing.s8),
        _answer(
          keyName: 'report-feedback-pain',
          label: l.reportsMemberFeedbackPainLabel,
          // 통증은 `없음` 도 답이다. 비워 두면 안 물어본 것처럼 보인다.
          value: given == null ? null : _painValue(l, given),
          unanswered: unanswered,
          alarming: given?.hasPain ?? false,
        ),
      ],
    );
    final String noteText = given?.note ?? '';
    final Widget note = AppTile(
      key: const ValueKey<String>('report-feedback-note-tile'),
      tone: AppTileTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l.reportsMemberFeedbackNoteLabel,
            key: const ValueKey<String>('report-feedback-note-label'),
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          if (noteText.isNotEmpty)
            Text(
              noteText,
              key: const ValueKey<String>('report-feedback-note'),
              style: tokens.text(OnCareTypography.bodySmall),
            )
          else
            Text(
              given == null ? unanswered : l.reportsMemberFeedbackNoteNone,
              key: const ValueKey<String>('report-feedback-note-empty'),
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
        ],
      ),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(
            number: 1,
            title: l.reportsMemberFeedbackTitle,
            // 언제 낸 답인지를 제목 줄에 적는다 — 주가 끝난 뒤에 받는 답이라,
            // 날짜가 없으면 이번 주 도중에 쓴 말처럼 읽힌다.
            titleMeta: given == null
                ? (failed
                      ? l.reportsMemberFeedbackLoadFailed
                      : l.reportsMemberFeedbackNone)
                : l.reportsMemberFeedbackMeta(
                    l.dateMonthDay(
                      given.submittedOn.month,
                      given.submittedOn.day,
                    ),
                  ),
            trailing: (given?.needsAttention ?? false)
                ? AppTag(
                    label: l.reportsMemberFeedbackAttention,
                    tone: AppTagTone.danger,
                  )
                : null,
          ),
          if (given == null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            // 빈 칸이 무엇을 뜻하는지 말해 준다 — 기능이 고장 난 것이 아니라
            // 회원이 아직 답하지 않은 것이다. 읽지 못했으면 그렇다고 말한다
            // (#3246).
            Text(
              failed
                  ? l.reportsMemberFeedbackLoadFailedHint
                  : l.reportsMemberFeedbackNoneHint,
              key: ValueKey<String>(
                failed ? 'report-feedback-failed' : 'report-feedback-empty',
              ),
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ],
          const SizedBox(height: OnCareSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
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

/// 통증 답 — 부위와 (있으면) 날짜, 없으면 `없음`.
String _painValue(AppLocalizations l, MemberWeeklyFeedback given) {
  if (!given.hasPain) return l.reportsMemberFeedbackPainNone;
  final DateTime? on = given.painOn;
  if (on == null) return given.painArea;
  return l.reportsMemberFeedbackPainOn(
    given.painArea,
    l.dateMonthDay(on.month, on.day),
  );
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

/// `문항 — 답` 한 줄. 안 낸 주에는 [unanswered] 를 흐리게, 살펴볼 답은
/// 위험 색으로 적는다.
Widget _answer({
  required String keyName,
  required String label,
  required String? value,
  required String unanswered,
  required bool alarming,
}) => AppKeyValueRow(
  key: ValueKey<String>(keyName),
  label: label,
  value: value ?? unanswered,
  strongValue: value != null,
  valueColor: value == null
      ? OnCareColors.textTertiary
      : alarming
      ? OnCareColors.danger
      : null,
);

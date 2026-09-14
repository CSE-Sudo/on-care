import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/dashboard/domain/activity_feedback.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// "활동 피드백" — 트레이너 활동 피드백 3가지(이행률·이탈 위험 감지, 7일
/// 이상 활동 저조, 식단 피드백 미완료)를 풀어서 보여 주는 카드.
///
/// 이전에는 규칙 기반 코칭 요약(고객별 상태·근거·운동 중심)을 함께 그렸는데,
/// 활동 피드백 하나로 좁혔다 — 두 정보가 한 카드에 있으면 어느 쪽을 먼저
/// 읽어야 할지 애매했다.
///
/// 제목은 "AI 진단"이었지만 실제로는 AI(LLM) 를 부르지 않고 클라이언트에서
/// 규칙(`buildActivityFeedback`/`computeChurnSignals`)으로만 계산한다 —
/// 이름이 실제로 하는 일과 달라 "활동 피드백"으로 고쳤다.
class AiSummaryCard extends StatelessWidget {
  /// Creates the card.
  const AiSummaryCard({super.key, required this.activityFeedback});

  /// 이행률·이탈 위험·식단 피드백 미완료 등 트레이너 활동 피드백 bullets.
  final List<ActivityFeedbackItem> activityFeedback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 대상이 없는 신호는 아예 그리지 않는다 — "0명" 문장은 안내가 아니다.
    final active = activityFeedback.where((i) => i.count > 0).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const OniAvatar(size: OnCareSize.avatarMedium),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(child: AppSectionHeader(title: l.dashAiSummaryTitle)),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (active.isEmpty)
            Text(
              l.dashAiNoClients,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            )
          else
            for (var i = 0; i < active.length; i++) ...<Widget>[
              if (i > 0) ...<Widget>[
                const SizedBox(height: OnCareSpacing.s12),
                const AppDivider(),
                const SizedBox(height: OnCareSpacing.s12),
              ],
              _ActivityFeedbackDetail(item: active[i]),
            ],
        ],
      ),
    );
  }
}

/// One 트레이너 활동 피드백 bullet, written out in full — headline, a
/// sentence that names the clients naturally, and a right-aligned link to
/// go act on it.
class _ActivityFeedbackDetail extends StatelessWidget {
  const _ActivityFeedbackDetail({required this.item});

  final ActivityFeedbackItem item;

  /// Where each kind's CTA leads — the client most worth checking first.
  String? _destination() {
    if (item.clientIds.isEmpty) return null;
    final id = item.clientIds.first;
    return switch (item.kind) {
      ActivityFeedbackKind.difficultyReview => AppRoutes.coachingFor(id),
      ActivityFeedbackKind.inactiveSevenDays => AppRoutes.messagesFor(id),
      ActivityFeedbackKind.dietFeedbackPending => AppRoutes.clientDetail(
        id,
        section: 'diet',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final destination = _destination();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          item.kind.title(l),
          style: tokens
              .text(OnCareTypography.label)
              .copyWith(color: OnCareColors.textPrimary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        // 설명은 왼쪽에서 넓게 숨 쉬고, 버튼은 오른쪽에 붙는다 — 세 항목이 같은
        // 두 칸 그리드로 줄을 맞춰야 나란히 훑어 읽힌다.
        Row(
          children: <Widget>[
            Expanded(
              // 추천 행동("프로그램에서 루틴을 조정해보세요")을 설명 문장에
              // 이어 붙인다 — 버튼은 그 탭으로 가는 짧은 링크일 뿐, 무엇을
              // 해야 하는지는 이 문장이 전부 말한다.
              child: Text(
                '${item.kind.description(l, _names(l, item.clientNames))} '
                '${item.kind.recommendation(l)}',
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            if (destination != null)
              AppButton(
                key: ValueKey<String>('ai-summary-cta-${item.kind.name}'),
                label: item.kind.tabLabel(l),
                onPressed: () => context.go(destination),
                variant: AppButtonVariant.secondary,
                size: OnCareButtonSize.small,
                trailingIcon: Icons.chevron_right_rounded,
              ),
          ],
        ),
      ],
    );
  }

  static String _names(AppLocalizations l, List<String> names) {
    const maxShown = 3;
    if (names.length <= maxShown) return names.join(', ');
    final shown = names.take(maxShown).join(', ');
    return l.dashActivityMoreClients(shown, names.length - maxShown);
  }
}

import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/reports/domain/report_goal_check.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_card_header.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// ③ 지난 주 목표 달성 — 지난 주 리포트를 보낼 때 고른 목표를 이번 주 수치로
/// 회수한다. (#2287)
///
/// 목표는 다음 주에 확인될 때 비로소 목표다. 고르는 자리(② 작성)만 있고 이
/// 칸이 없으면 트레이너는 매주 새 목표를 고르기만 하고, 회원은 지난 주 약속이
/// 어떻게 됐는지 듣지 못한다.
///
/// 판정마다 근거 수치를 옆에 적는다 — `미달` 만 적으면 트레이너가 그 판정을
/// 믿어야 할지 알 수 없다.
class ReportLastGoalsCard extends StatelessWidget {
  /// Creates the card.
  const ReportLastGoalsCard({super.key, required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<GoalCheck> checks = checkWeekGoals(l, report);
    if (checks.isEmpty) {
      return AppCard(
        key: const ValueKey<String>('report-last-goals-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ReportCardHeader(number: 3, title: l.reportsLastGoalsTitle),
            const SizedBox(height: OnCareSpacing.s12),
            AppEmptyState(
              key: const ValueKey<String>('report-last-goals-empty'),
              title: l.reportsLastGoalsNone,
              // 빈 칸이 고장이 아니라 아직 고른 적이 없다는 뜻임을, 그리고
              // 어디서 고르면 여기로 돌아오는지를 함께 말한다.
              message: l.reportsLastGoalsNoneHint,
              icon: Icons.flag_rounded,
              placement: AppStatePlacement.card,
            ),
          ],
        ),
      );
    }

    final int met = metGoalCount(checks);
    return AppCard(
      key: const ValueKey<String>('report-last-goals-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ReportCardHeader(
            number: 3,
            title: l.reportsLastGoalsTitle,
            subtitle: l.reportsLastGoalsSubtitle,
            trailing: AppTag(
              key: const ValueKey<String>('report-last-goals-count'),
              label: l.reportsLastGoalsMetCount(met, checks.length),
              tone: met == checks.length
                  ? AppTagTone.success
                  : AppTagTone.neutral,
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          for (var i = 0; i < checks.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: OnCareSpacing.s8),
            _GoalCheckRow(
              key: ValueKey<String>('report-last-goal-$i'),
              check: checks[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// 판정 딱지 · 목표 문장 · 근거 수치 한 줄.
class _GoalCheckRow extends StatelessWidget {
  const _GoalCheckRow({super.key, required this.check});

  final GoalCheck check;

  /// 판정 딱지가 차지하는 최소 폭. 줄마다 목표 문장이 같은 자리에서 시작해야 눈이
  /// 세로로 훑을 수 있다 — 딱지 글자 길이는 언어마다 다르다.
  static const double _tagWidth = 96;

  /// 근거를 줄 끝에 둘 수 있는 최소 폭.
  static const double _inlineMinWidth = 480;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String? evidence = check.evidence;
    final TextStyle goalStyle = tokens
        .text(OnCareTypography.strong(OnCareTypography.bodySmall))
        .copyWith(color: OnCareColors.textPrimary);
    final TextStyle evidenceStyle = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    return AppTile(
      // 읽기만 하는 줄이 이어지는 자리라 한 단계 옅은 채움을 쓴다.
      tone: AppTileTone.brandSoft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 넓으면 근거를 줄 끝에, 좁으면 목표 문장 아래에 둔다 — 좁은 칸에서
          // 한 줄에 세 가지를 세우면 목표 문장이 가장 먼저 밀려난다.
          final bool inline = constraints.maxWidth >= _inlineMinWidth;
          return Row(
            children: <Widget>[
              // 최소 폭만 정한다 — 큰 글자 배율에서 딱지가 이 폭을 넘으면
              // 목표 문장 쪽이 줄어든다.
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: _tagWidth),
                child: Align(
                  widthFactor: 1,
                  alignment: Alignment.centerLeft,
                  child: AppTag(
                    label: outcomeLabel(l, check.outcome),
                    tone: outcomeTone(check.outcome),
                  ),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(check.goal, style: goalStyle),
                    if (evidence != null && !inline) ...<Widget>[
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(evidence, style: evidenceStyle),
                    ],
                  ],
                ),
              ),
              if (evidence != null && inline) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s12),
                Text(evidence, style: evidenceStyle),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 판정의 로케일 이름.
String outcomeLabel(AppLocalizations l, GoalOutcome outcome) =>
    switch (outcome) {
      GoalOutcome.met => l.reportsLastGoalsMet,
      GoalOutcome.partial => l.reportsLastGoalsPartial,
      GoalOutcome.missed => l.reportsLastGoalsMissed,
      GoalOutcome.unknown => l.reportsLastGoalsUnknown,
    };

/// 판정의 딱지 색. `직접 확인` 은 좋고 나쁨이 아니라 회색이다.
AppTagTone outcomeTone(GoalOutcome outcome) => switch (outcome) {
  GoalOutcome.met => AppTagTone.success,
  GoalOutcome.partial => AppTagTone.caution,
  GoalOutcome.missed => AppTagTone.danger,
  GoalOutcome.unknown => AppTagTone.neutral,
};

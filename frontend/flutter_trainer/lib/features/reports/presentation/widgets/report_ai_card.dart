import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/soft_navy_card.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 요약 카드 — 트레이너가 매주 같은 문장을 처음부터 쓰지 않게 한다.
///
/// 결과는 그대로 읽는 글이 아니라 **피드백 초안으로 가져다 고칠 재료**다.
/// 그래서 `피드백으로 가져오기` 가 이 카드의 본래 동선이고, 문장이 마음에 안
/// 들면 다시 생성한다(#755).
///
/// 데모에는 모델이 없어 수치에서 조립한 문장이 온다. 실서버도 공급자 장애면
/// 같은 문장으로 되돌아온다 — 그 경우 `생성` 배지를 달지 않아, 트레이너가 이
/// 문장을 어디까지 믿을지 알 수 있다.
///
/// 화면의 AI 카드는 이것 하나다 — 대시보드 `활동 피드백` 카드와 같은 옅은 남색
/// 그라디언트 카드에 AI 아이콘 제목을 단다.
class ReportAiCard extends ConsumerWidget {
  const ReportAiCard({
    super.key,
    required this.report,
    required this.onUseAsDraft,
    this.fill = false,
  });

  final WeeklyReport report;

  /// 요약을 피드백 입력창으로 옮긴다.
  final void Function(String draft) onUseAsDraft;

  /// 남은 세로 자리를 채울 것인가.
  ///
  /// 넓은 화면에서 이 카드는 왼쪽 열의 마지막 칸이다. 내용만큼만 차지하면 그
  /// 아래가 통째로 빈 회색 바닥이 되어, 화면의 3분의 1이 아무 말도 하지
  /// 않았다. 채우되 **넘치지는 않는다** — 본문이 길면 카드 안에서 스크롤하고,
  /// 동작 줄은 바닥에 붙어 늘 보인다(#1177).
  final bool fill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final key = (client: report.client, weekStart: report.weekStart);
    final summary = ref.watch(reportSummaryProvider(key));
    final Widget content = summary.when(
      loading: () => const AppLoading(placement: AppStatePlacement.card),
      // 생성이 실패해도 카드가 비지 않는다 — 예전 안내문으로 되돌아가 그
      // 자리에 무엇이 올지는 말해 준다.
      error: (_, _) => Text(
        l.reportsAiUnavailable,
        style: tokens
            .text(OnCareTypography.bodySmall)
            .copyWith(color: OnCareColors.textSecondary),
      ),
      data: (value) => _SummaryBody(
        summary: value,
        actions: summaryCoachingActions(l, report),
        // 자리가 모자라 접은 주의사항이 몇 건인지 말한다 — 말하지 않으면
        // 카드가 다 보여 준 것으로 읽힌다(#1430).
        hiddenCount: summaryHiddenWatchCount(l, report),
        fill: fill,
        onRegenerate: () => ref.invalidate(reportSummaryProvider(key)),
        onUseAsDraft: () => onUseAsDraft(value.asDraft),
      ),
    );
    // 대시보드 `활동 피드백` 카드와 같은 옅은 남색 카드다. 흰 일반 카드 사이에서
    // AI 가 만든 초안이라는 것이 드러난다.
    return SoftNavyCard(
      key: const ValueKey<String>('reports-ai-card'),
      // 버튼 잉크가 그라디언트 위에 그려지도록 투명 Material 을 둔다.
      child: Material(
        type: MaterialType.transparency,
        child: _cardColumn(l, summary, content),
      ),
    );
  }

  Widget _cardColumn(
    AppLocalizations l,
    AsyncValue<ReportSummary> summary,
    Widget content,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AppSectionHeader(
                title: l.reportsAiTitle,
                icon: Icons.auto_awesome_rounded,
              ),
            ),
            if (summary.valueOrNull?.isGenerated ?? false) ...<Widget>[
              const SizedBox(width: OnCareSpacing.s8),
              AppTag(label: l.reportsAiGenerated, tone: AppTagTone.brand),
            ],
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        if (fill) Expanded(child: content) else content,
      ],
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.summary,
    required this.actions,
    this.hiddenCount = 0,
    required this.onRegenerate,
    required this.onUseAsDraft,
    this.fill = false,
  });

  final ReportSummary summary;

  /// 다음 주에 할 일. 요약이 지난 주를 말하면, 이쪽은 그래서 무엇을 하면
  /// 되는지를 말한다 — 카드 아래가 비어 있던 자리다(#1177).
  final List<String> actions;

  /// 자리가 모자라 접은 주의사항 수. 0 이면 접은 것이 없다. (#1430)
  final int hiddenCount;
  final VoidCallback onRegenerate;
  final VoidCallback onUseAsDraft;

  /// 남은 자리를 채운다. 글이 길면 본문만 스크롤하고 동작 줄은 바닥에 붙는다.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle detail = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textSecondary);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          summary.headline,
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.bodySmall))
              .copyWith(color: OnCareColors.textPrimary),
        ),
        for (final point in summary.points) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          Text('· $point', style: detail),
        ],
        if (actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          Text(
            l.reportsAiNextWeek,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: tokens.brand.primary),
          ),
          for (var i = 0; i < actions.length; i++) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Row(
              key: ValueKey<String>('reports-summary-action-$i'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: OnCareSize.iconSmall,
                  color: tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s4),
                Expanded(child: Text(actions[i], style: detail)),
              ],
            ),
          ],
          if (hiddenCount > 0) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              key: const ValueKey<String>('reports-summary-hidden'),
              l.reportsAiMoreWatchpoints(hiddenCount),
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.textTertiary),
            ),
          ],
        ],
      ],
    );
    final buttons = Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s8),
      // 왼쪽 열 폭에서 두 동작이 한 줄에 들어가지 않는 조합이 있다 — 영어 ·
      // 배율 1.3 이 그렇다. 줄을 접어 받는다.
      child: Wrap(
        spacing: OnCareSpacing.buttonGap,
        runSpacing: OnCareSpacing.s4,
        children: <Widget>[
          AppButton(
            label: l.reportsAiUseAsDraft,
            leadingIcon: Icons.edit_note_rounded,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
            onPressed: onUseAsDraft,
          ),
          AppButton(
            label: l.reportsAiRegenerate,
            leadingIcon: Icons.refresh_rounded,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
            onPressed: onRegenerate,
          ),
        ],
      ),
    );
    if (!fill) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[body, buttons],
      );
    }
    // 넘칠 것 같으면 본문만 스크롤한다. 카드가 열 밖으로 자라면 왼쪽 열이
    // 화면을 넘어가고, 그건 이 카드를 늘린 이유와 정반대다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey<String>('reports-summary-body-scroll'),
            child: body,
          ),
        ),
        buttons,
      ],
    );
  }
}

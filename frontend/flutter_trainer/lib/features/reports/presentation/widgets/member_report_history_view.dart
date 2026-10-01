import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/member_report_history_provider.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 한 회원에게 그동안 보낸 리포트를 주별로 모은 화면. (#2394)
///
/// 작업대는 **주 → 회원** 순서로 읽는다 — 한 주의 명단에서 누가 남았나를
/// 본다. 이 화면은 그 반대, **회원 → 주** 다. "이 회원에게 그동안 무엇을
/// 보냈나" 를 한 번에 본다. 회원 앱의 받은 리포트 모아 보기(#2277)의 짝이다.
///
/// 최신 주부터 선다. 이번 주를 아직 보내지 않았으면 맨 위에 `미전송 · 열기`
/// 줄이 먼저 선다 — 지난 리포트를 훑다가 이번 주 할 일로 바로 넘어간다.
class MemberReportHistoryView extends ConsumerWidget {
  /// Creates the view.
  const MemberReportHistoryView({
    super.key,
    required this.client,
    required this.onBack,
    required this.onView,
    required this.onOpenThisWeek,
  });

  /// 누구의 이력인가.
  final TrainerClient client;

  /// 회원 목록(작업대)으로 돌아간다.
  final VoidCallback onBack;

  /// 그 주에 보낸 리포트를 연다 — 인자는 그 주 월요일.
  final ValueChanged<DateTime> onView;

  /// 이번 주 리포트 편집기를 연다.
  final VoidCallback onOpenThisWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AsyncValue<MemberReportHistoryState> history = ref.watch(
      memberReportHistoryViewProvider(client.id),
    );
    final DateTime thisMonday = weekStartOf(nowKst());

    final Widget body = history.when(
      loading: () => const AppLoading(
        key: ValueKey<String>('reports-history-loading'),
        placement: AppStatePlacement.card,
      ),
      // 재시도 버튼은 상태 위젯 안에 있어 키를 줄 수 없다 — 묶음에 키를 둔다.
      error: (e, _) => KeyedSubtree(
        key: const ValueKey<String>('reports-history-retry'),
        child: AppErrorState(
          title: l.reportsHistoryLoadFailed,
          retryLabel: l.actionRetry,
          placement: AppStatePlacement.card,
          onRetry: history.isLoading
              ? null
              : () => ref.invalidate(memberReportHistoryProvider(client.id)),
        ),
      ),
      data: (MemberReportHistoryState state) {
        final bool thisWeekSent = state.items.any(
          (MemberReportHistoryItem item) => item.weekStart == thisMonday,
        );
        final List<Widget> rows = <Widget>[
          if (!thisWeekSent)
            _UnsentRow(weekStart: thisMonday, onOpen: onOpenThisWeek),
          for (final MemberReportHistoryItem item in state.items)
            _HistoryRow(
              client: client,
              item: item,
              thisWeek: item.weekStart == thisMonday,
              onView: () => onView(item.weekStart),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: OnCareSpacing.s8),
              rows[i],
            ],
            if (state.items.isEmpty) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s16),
              AppEmptyState(
                key: const ValueKey<String>('reports-history-empty'),
                title: l.reportsHistoryEmpty,
                icon: AppIcons.history,
                placement: AppStatePlacement.card,
              ),
            ],
            if (state.hasMore) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s12),
              Center(
                child: AppButton(
                  key: const ValueKey<String>('reports-history-more'),
                  label: l.reportsHistoryMore,
                  variant: AppButtonVariant.secondary,
                  size: OnCareButtonSize.small,
                  loading: state.loadingMore,
                  onPressed: state.loadingMore
                      ? null
                      : () => ref
                            .read(
                              memberReportHistoryProvider(client.id).notifier,
                            )
                            .loadMore(),
                ),
              ),
            ],
            if (state.loadMoreFailed) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              Text(
                l.reportsHistoryMoreFailed,
                key: const ValueKey<String>('reports-history-more-failed'),
                textAlign: TextAlign.center,
                style: tokens
                    .text(OnCareTypography.strong(OnCareTypography.caption))
                    .copyWith(color: OnCareColors.caution),
              ),
            ],
          ],
        );
      },
    );

    return SingleChildScrollView(
      key: const ValueKey<String>('reports-history-scroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 보낸 리포트 화면의 돌아가기와 같은 자리·같은 모양이다 — 리포트
          // 탭 안에서 한 단계 들어간 화면은 모두 왼쪽 위에서 나온다.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppBackLink(
              key: const ValueKey<String>('reports-history-back'),
              label: l.reportsBackToList,
              onPressed: onBack,
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            l.reportsHistoryTitle(client.name),
            key: const ValueKey<String>('reports-history-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.text(
              OnCareTypography.strong(OnCareTypography.titleSmall),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          body,
        ],
      ),
    );
  }
}

/// `8월 3일 – 8월 9일` — 한 주의 범위.
String reportWeekRangeLabel(AppLocalizations l, DateTime weekStart) {
  final DateTime weekEnd = DateTime(
    weekStart.year,
    weekStart.month,
    weekStart.day + 6,
  );
  return l.dateRange(
    l.dateMonthDay(weekStart.month, weekStart.day),
    l.dateMonthDay(weekEnd.month, weekEnd.day),
  );
}

/// 줄의 첫 줄 — 주 범위, 이번 주면 `· 이번 주`.
class _WeekHeading extends StatelessWidget {
  const _WeekHeading({required this.weekStart, required this.thisWeek});

  final DateTime weekStart;
  final bool thisWeek;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String range = reportWeekRangeLabel(l, weekStart);
    return Text(
      thisWeek ? '$range · ${l.reportsHistoryThisWeek}' : range,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.oncare.text(
        OnCareTypography.strong(OnCareTypography.bodySmall),
      ),
    );
  }
}

/// 이번 주를 아직 보내지 않았을 때 맨 위에 서는 `미전송 · 열기` 줄.
class _UnsentRow extends StatelessWidget {
  const _UnsentRow({required this.weekStart, required this.onOpen});

  final DateTime weekStart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      key: const ValueKey<String>('reports-history-unsent'),
      padding: AppCard.compactPadding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _WeekHeading(weekStart: weekStart, thisWeek: true),
                const SizedBox(height: OnCareSpacing.s4),
                AppTag(label: l.reportsHistoryUnsent, tone: AppTagTone.caution),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          AppButton(
            key: const ValueKey<String>('reports-history-open'),
            label: l.reportsOpenDraft,
            size: OnCareButtonSize.small,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

/// 보낸 주 한 줄 — 주 범위, 전송일, 열람 여부, 피드백 첫 줄, `보기`.
class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({
    required this.client,
    required this.item,
    required this.thisWeek,
    required this.onView,
  });

  final TrainerClient client;
  final MemberReportHistoryItem item;
  final bool thisWeek;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String key = ymd(item.weekStart);
    // 본문이 빈 기록(데모로 깔아 둔 이번 주)은 그 주 수치에서 만든 문구의 첫
    // 줄로 채운다 — 보낸 리포트 화면과 같은 규칙이다. 본문이 있는 줄은 그 주
    // 리포트를 읽지 않는다: 줄마다 한 주씩 집계를 부르면 목록이 무거워진다.
    String preview = item.feedbackPreview;
    if (preview.isEmpty) {
      final WeeklyReport? report = ref
          .watch(
            weeklyReportProvider(
              ReportKey(client: client, weekStart: item.weekStart),
            ),
          )
          .valueOrNull;
      if (report != null) {
        preview = reportFeedbackPreview(reportMessage(l, report));
      }
    }
    final TextStyle caption = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    return AppCard(
      key: ValueKey<String>('reports-history-week-$key'),
      padding: AppCard.compactPadding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _WeekHeading(weekStart: item.weekStart, thisWeek: thisWeek),
                const SizedBox(height: OnCareSpacing.s4),
                Wrap(
                  spacing: OnCareSpacing.s8,
                  runSpacing: OnCareSpacing.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      l.reportsSentOn(
                        l.dateMonthDay(item.sentAt.month, item.sentAt.day),
                      ),
                      style: caption,
                    ),
                    // 안 읽은 줄만 눈에 띄게 — 작업대 전송 완료 줄과 같은 규칙.
                    AppTag(
                      label: item.read
                          ? l.reportsSentRead
                          : l.reportsSentUnread,
                      tone: item.read ? AppTagTone.neutral : AppTagTone.danger,
                    ),
                    if (item.sendCount > 1)
                      AppTag(label: l.reportsHistorySendCount(item.sendCount)),
                    if (item.hasPdf) AppTag(label: l.reportsHistoryPdf),
                  ],
                ),
                if (preview.isNotEmpty) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s4),
                  Text(
                    preview,
                    key: ValueKey<String>('reports-history-preview-$key'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text(OnCareTypography.bodySmall),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s12),
          AppButton(
            key: ValueKey<String>('reports-history-view-$key'),
            label: l.reportsViewSent,
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
            onPressed: onView,
          ),
        ],
      ),
    );
  }
}

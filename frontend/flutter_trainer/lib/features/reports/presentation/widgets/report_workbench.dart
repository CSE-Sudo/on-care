import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_picker_card.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 탭의 첫 화면 — **이번 주 전 회원의 작업대**.
///
/// 회원 하나를 골라 그 사람의 주를 읽는 화면이 아니라, 이번 주 여덟 장을
/// 내보내는 라인이다. 그래서 왼쪽 회원 열 대신 큐가 본문을 차지하고, 화면이
/// 가장 먼저 답하는 질문은 "누가 남았나" 다. (#2232)
class ReportWorkbench extends StatelessWidget {
  /// Creates the workbench.
  const ReportWorkbench({
    super.key,
    required this.entries,
    required this.sort,
    required this.onSortChanged,
    required this.onOpen,
    required this.onOpenSent,
    required this.records,
    required this.weekNav,
    required this.loading,
  });

  /// 작업대에 선 줄 — 이미 정렬돼 있다.
  final List<ReportQueueEntry> entries;

  /// 지금 고른 정렬.
  final ReportQueueSort sort;

  /// 정렬을 바꿀 때.
  final ValueChanged<ReportQueueSort> onSortChanged;

  /// 미전송 줄을 눌러 편집기로 들어간다.
  final ValueChanged<ReportQueueEntry> onOpen;

  /// 전송 완료 줄을 눌러 보낸 리포트를 연다.
  final ValueChanged<ReportQueueEntry> onOpenSent;

  /// 그 주에 나간 기록 — `회원 id → 기록`. 전송 완료 열이 언제 나갔는지,
  /// 회원이 열어 봤는지를 여기서 읽는다.
  final Map<String, ReportSendRecord> records;

  /// 주 이동. 카드 제목 줄에 놓는다 — 옮기는 대상이 이 목록이다.
  final Widget weekNav;

  /// 아직 수치를 읽는 중인가. 줄은 그대로 서고 수치 자리만 비운다.
  final bool loading;

  /// `이번 주 리포트` 대 `전송 완료` 의 가로 비율.
  ///
  /// 왼쪽이 이 화면의 일이다 — 줄마다 이름·신호·요일 기록·여는 버튼이 한 줄에
  /// 서야 한다. 오른쪽은 이미 끝난 일의 명단이라 이름과 전송 시각이면 된다.
  /// 고정 폭으로 두면 넓은 화면에서 한쪽만 늘어나 비율이 화면마다 달라지므로,
  /// 남는 자리를 둘이 2:1 로 나눈다(#2232).
  /// 오른쪽(`전송 완료`)이 기본값 1 을 그대로 쓰므로 여기에는 왼쪽 몫만 적는다.
  static const int _queueFlex = 2;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<ReportQueueEntry> pending = <ReportQueueEntry>[
      for (final ReportQueueEntry e in entries)
        if (!e.sent) e,
    ];
    final List<ReportQueueEntry> done = <ReportQueueEntry>[
      for (final ReportQueueEntry e in entries)
        if (e.sent) e,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= OnCareLayout.splitBreakpoint;
        final Widget queue = _queueCard(context, l, pending, done.length);
        final Widget sentColumn = _sentCard(context, l, done);
        if (!wide) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                queue,
                const SizedBox(height: OnCareSpacing.s16),
                sentColumn,
              ],
            ),
          );
        }
        return SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: _queueFlex, child: queue),
              const SizedBox(width: OnCareLayout.splitGap),
              Expanded(child: sentColumn),
            ],
          ),
        );
      },
    );
  }

  Widget _queueCard(
    BuildContext context,
    AppLocalizations l,
    List<ReportQueueEntry> pending,
    int doneCount,
  ) {
    final OnCareTokens tokens = context.oncare;
    final int total = pending.length + doneCount;
    // 머리말(주 이동·규모·진행)은 **카드 밖**에 둔다. 카드 테두리는 "여기서
    // 부터 손댈 줄" 이라는 뜻이라, 이미 끝난 진행률까지 그 안에 넣으면 무엇이
    // 남은 일인지가 흐려진다. 상자는 미전송 줄에서 시작한다(#2232).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 날짜가 맨 왼쪽이다 — 이 화면의 모든 수는 "어느 주" 에 매여 있고,
        // 그 주를 먼저 읽어야 아래 줄들이 무슨 주의 기록인지 안다. 규모를
        // 말하던 곁말은 바로 아래 진행 줄이 같은 것을 수로 말하고 있어
        // 덜어냈다 — 같은 사실을 두 번 적으면 둘 다 흘려 읽는다(#2232).
        Align(alignment: AlignmentDirectional.centerStart, child: weekNav),
        const SizedBox(height: OnCareSpacing.s12),
        _ProgressRow(done: doneCount, total: total),
        const SizedBox(height: OnCareSpacing.s16),
        AppCard(
          key: const ValueKey<String>('reports-workbench-queue'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 영어·큰 글자에서는 `남은 사람` 과 정렬 토글이 한 줄에 다 서지
              // 못한다. 줄을 넘겨 두 줄로 세운다 — 한쪽을 줄여 읽기 어렵게
              // 만들지 않는다(#849).
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: OnCareSpacing.s12,
                runSpacing: OnCareSpacing.s8,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        l.reportsPending,
                        style: tokens.text(
                          OnCareTypography.strong(OnCareTypography.bodySmall),
                        ),
                      ),
                      const SizedBox(width: OnCareSpacing.s8),
                      // 남은 수는 배지로 — 전송 완료 열의 수와 같은 모양으로 읽힌다.
                      AppTag(
                        label: l.reportsCountPeople(pending.length),
                        tone: pending.isEmpty
                            ? AppTagTone.success
                            : AppTagTone.brand,
                      ),
                    ],
                  ),
                  AppSegmentedToggle<ReportQueueSort>(
                    segments: <AppSegment<ReportQueueSort>>[
                      AppSegment<ReportQueueSort>(
                        value: ReportQueueSort.priority,
                        label: l.reportsSortPriority,
                      ),
                      AppSegment<ReportQueueSort>(
                        value: ReportQueueSort.name,
                        label: l.reportsSortName,
                      ),
                    ],
                    selected: sort,
                    onChanged: onSortChanged,
                  ),
                ],
              ),
              const SizedBox(height: OnCareSpacing.s12),
              if (pending.isEmpty)
                AppEmptyState(
                  key: const ValueKey<String>('reports-queue-empty'),
                  title: l.reportsQueueAllSent,
                  icon: Icons.check_circle_rounded,
                  placement: AppStatePlacement.card,
                )
              else
                for (final ReportQueueEntry entry in pending) ...<Widget>[
                  _QueueRow(
                    entry: entry,
                    loading: loading,
                    onTap: () => onOpen(entry),
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sentCard(
    BuildContext context,
    AppLocalizations l,
    List<ReportQueueEntry> done,
  ) {
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      key: const ValueKey<String>('reports-workbench-sent'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                l.reportsSentColumn,
                style: tokens.text(
                  OnCareTypography.strong(OnCareTypography.bodySmall),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              AppTag(label: l.reportsCountPeople(done.length)),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (done.isEmpty)
            Text(
              l.reportsSentColumnEmpty,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            )
          else ...<Widget>[
            for (final ReportQueueEntry entry in done) ...<Widget>[
              // 보낸 줄도 누를 수 있다 — 회원이 받은 리포트를 그대로 다시
              // 연다. 흐리게 깔지 않는다: 이미 끝난 일이지 못 쓰는 줄이
              // 아니다.
              AppTile(
                key: ValueKey<String>('reports-sent-${entry.client.id}'),
                onTap: () => onOpenSent(entry),
                child: _SentRow(entry: entry, record: records[entry.client.id]),
              ),
              const SizedBox(height: OnCareSpacing.s8),
            ],
            // 열람 여부가 다음 주 순서에 어떻게 쓰이는지 한 줄로 밝힌다 —
            // `안 읽음` 배지가 그냥 표시가 아니라는 뜻이다.
            if (done.any((e) => records[e.client.id]?.read == false))
              Text(
                l.reportsSentUnreadHint,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
          ],
        ],
      ),
    );
  }
}

/// 전송 완료 열의 한 줄 — 누구에게, 언제 나갔고, 열어 봤는가.
class _SentRow extends StatelessWidget {
  const _SentRow({required this.entry, required this.record});

  final ReportQueueEntry entry;
  final ReportSendRecord? record;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ReportSendRecord? sent = record;
    final String subtitle = sent == null
        ? l.reportsSentSubtitle
        : l.reportsSentOn(l.dateMonthDay(sent.sentAt.month, sent.sentAt.day));
    return Row(
      children: <Widget>[
        ClientAvatar(label: entry.client.avatar, size: OnCareSize.avatarSmall),
        const SizedBox(width: OnCareSpacing.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                entry.client.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.text(
                  OnCareTypography.strong(OnCareTypography.bodySmall),
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
          ),
        ),
        if (sent != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          // 안 읽은 줄만 눈에 띄게 둔다 — 읽은 줄이 더 조용해야 남은 일이
          // 먼저 보인다.
          AppTag(
            label: sent.read ? l.reportsSentRead : l.reportsSentUnread,
            tone: sent.read ? AppTagTone.neutral : AppTagTone.danger,
          ),
        ],
        const SizedBox(width: OnCareSpacing.s4),
        AppIcon(
          AppIcon.setOf(context).disclosure,
          size: OnCareSize.iconSmall,
          color: OnCareColors.textTertiary,
        ),
      ],
    );
  }
}

/// `n / m 전송` 진행 줄.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double fraction = total == 0 ? 0 : done / total;
    return Row(
      children: <Widget>[
        Text(
          l.reportsSendProgress(done, total),
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.bodySmall))
              .copyWith(color: tokens.brand.strong),
        ),
        const SizedBox(width: OnCareSpacing.s12),
        Expanded(child: AppProgressBar(value: fraction)),
      ],
    );
  }
}

/// 작업대의 한 줄.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.entry,
    required this.loading,
    required this.onTap,
  });

  final ReportQueueEntry entry;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final WeeklyReport? report = entry.report;
    final Widget identity = ClientPickerCard(
      key: ValueKey<String>('report-client-${entry.client.id}'),
      client: entry.client,
      // 작업대에는 고른 회원이 없다 — 줄을 누르면 곧바로 편집기로 들어가지,
      // 이 화면에서 골라 둔 채 머무르지 않는다.
      selected: false,
      onTap: onTap,
    );
    // 그 주를 한 줄로 말하는 자리. 이 줄을 먼저 봐야 하는 이유가 여기 적힌다
    // — 이행률이 낮다, PT 를 빠졌다, 사흘이 비었다. 식단 수치는 오지 않는다.
    final Widget reasons = Wrap(
      spacing: OnCareSpacing.s4,
      runSpacing: OnCareSpacing.s4,
      children: _reasons(l, report),
    );
    final Widget action = loading && report == null
        ? const AppLoading.inline()
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppButton(
                label: l.reportsOpenDraft,
                size: OnCareButtonSize.small,
                onPressed: onTap,
              ),
            ],
          );

    return AppCard(
      key: ValueKey<String>('reports-queue-${entry.client.id}'),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s16,
        vertical: OnCareSpacing.s12,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 이름 칸·이유·버튼이 한 줄에 다 서려면 이유가 설 자리가 있어야
          // 한다. 영어·큰 글자에서는 그 자리가 먼저 사라지므로, 모자라면
          // 이유를 아랫줄로 내린다 — 줄여 그리지 않는다(#849).
          final bool roomy =
              constraints.maxWidth >=
              clientPickerColumnWidth +
                  _reasonsMinWidth +
                  _actionMinWidth +
                  OnCareSpacing.s12 * 2;
          if (roomy) {
            return Row(
              children: <Widget>[
                SizedBox(width: clientPickerColumnWidth, child: identity),
                const SizedBox(width: OnCareSpacing.s12),
                Expanded(child: reasons),
                const SizedBox(width: OnCareSpacing.s12),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: identity),
                  const SizedBox(width: OnCareSpacing.s12),
                  action,
                ],
              ),
              const SizedBox(height: OnCareSpacing.s8),
              reasons,
            ],
          );
        },
      ),
    );
  }

  /// 이유 칸이 한 줄에 설 수 있다고 보는 최소 폭.
  static const double _reasonsMinWidth = 260;

  /// `열기` 버튼 자리로 잡아 두는 최소 폭.
  static const double _actionMinWidth = 200;

  /// 그 주를 설명하는 신호 배지. 판정은 [reportSignals] 한 곳에서만 한다 —
  /// 화면은 고른 것을 옮겨 적기만 한다.
  List<Widget> _reasons(AppLocalizations l, WeeklyReport? report) {
    if (report == null) {
      return <Widget>[AppTag(label: l.reportsReasonUnknown)];
    }
    final List<ReportSignal> signals = reportSignals(report);
    if (signals.isEmpty) {
      return <Widget>[
        AppTag(label: l.reportsReasonSteady, tone: AppTagTone.success),
      ];
    }
    // 잘한 것 하나까지 줄에 세우면, 골라야 할 이유와 골라도 그만인 사실이
    // 같은 크기로 선다. `PT 를 예정대로 했다` 는 리포트 본문에서 말한다.
    final List<ReportSignal> shown = <ReportSignal>[
      for (final ReportSignal signal in signals)
        if (signal.kind != ReportSignalKind.sessionDone) signal,
    ];
    if (shown.isEmpty) {
      return <Widget>[
        AppTag(label: l.reportsReasonSteady, tone: AppTagTone.success),
      ];
    }
    return <Widget>[for (final ReportSignal signal in shown) _tag(l, signal)];
  }

  Widget _tag(AppLocalizations l, ReportSignal signal) => switch (signal.kind) {
    // 이 목록에서 색은 `먼저 열 줄인가` 하나만 가른다. 60% 와 79% 를 다른
    // 색으로 두면 트레이너는 두 경고색의 뜻을 따로 외워야 하는데, 어차피 둘
    // 다 이번 주에 손대야 하는 줄이다(#2232).
    ReportSignalKind.completion => AppTag(
      label: l.reportsReasonCompletion(signal.value),
      tone: signal.value < 80 ? AppTagTone.danger : AppTagTone.success,
    ),
    ReportSignalKind.noShow => AppTag(
      label: l.reportsReasonNoShow(signal.value),
      tone: AppTagTone.danger,
    ),
    ReportSignalKind.sessionDone => AppTag(
      label: l.reportsReasonSessionDone(signal.value),
      tone: AppTagTone.success,
    ),
    ReportSignalKind.silentDays => AppTag(
      label: l.reportsReasonSilentDays(signal.value),
      tone: AppTagTone.danger,
    ),
    ReportSignalKind.slump => AppTag(
      label: l.reportsReasonSlump(signal.value),
      tone: AppTagTone.danger,
    ),
    ReportSignalKind.rising => AppTag(
      label: l.reportsReasonRising(signal.value),
      tone: AppTagTone.success,
    ),
    ReportSignalKind.fullLog => AppTag(
      label: l.reportsReasonFullLog,
      tone: AppTagTone.success,
    ),
    ReportSignalKind.onboarding => AppTag(label: l.reportsReasonOnboarding),
  };
}

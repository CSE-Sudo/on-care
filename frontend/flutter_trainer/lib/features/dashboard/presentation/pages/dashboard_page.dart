import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/page_scroll_reset.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/features/dashboard/data/demo_task_history.dart';
import 'package:oncare_trainer/features/dashboard/domain/churn_risk.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart';
import 'package:oncare_trainer/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/ai_summary_card.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/churn_risk_dialog.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/task_progress_chart.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/today_tasks_card.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/today_timeline_card.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 대시보드 — the console's home: what needs doing today.
///
/// Every number here is a link. The four KPI cards deep-link into the
/// view that explains them (담당 고객 → 고객 명단, 메시지 → 안읽음 필터,
/// 주의 고객/이탈 위험 → 해당 목록/다이얼로그), because a dashboard the
/// trainer can only read is a dashboard they stop opening.
class DashboardPage extends ConsumerWidget {
  /// Creates the dashboard.
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    // 이탈 위험·활동 피드백은 대시보드 화면에 있을 때만 구독하는 별도
    // provider다(dashboard_controller.dart 참고 — 30일 스케줄 구간을 도는
    // 조회라 `dashboardSummaryProvider`처럼 앱 내내 살아 있으면 안 된다).
    final churnRisk = ref.watch(dashboardChurnRiskProvider);
    final activityFeedback = ref.watch(dashboardActivityFeedbackProvider);
    final today = nowKst();

    return AppWebPage(
      title: l.dashTitle,
      subtitle: dateLabel(l, today),
      headerCenter: const ClientSearchBar(),
      body: PageScrollResetListener(
        child: summaryAsync.when(
          loading: () => const AppLoading(),
          error: (e, _) => AppErrorState(
            key: const ValueKey<String>('dashboard-retry'),
            title: l.dashLoadFailed,
            retryLabel: l.actionRetry,
            onRetry: summaryAsync.isLoading
                ? null
                : () => ref.invalidate(clientsProvider),
          ),
          data: (summary) => SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= OnCareLayout.twoColumnBreakpoint;
                // 왼쪽: 오늘의 일정 + (그 아래) 활동 피드백. 오른쪽: 오늘 할 일 +
                // (그 아래) 할 일 진행률 — 활동 피드백이 그래프와 나란한 줄에
                // 오도록 왼쪽 칸에 둔다.
                final leftColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const TodayTimelineCard(),
                    const SizedBox(height: OnCareSpacing.s16),
                    AiSummaryCard(activityFeedback: activityFeedback),
                  ],
                );
                final rightColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TodayTasksCard(entries: summary.attention),
                    const SizedBox(height: OnCareSpacing.s16),
                    const _TaskProgressCard(),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _KpiRow(summary: summary, churnRisk: churnRisk, wide: wide),
                    const SizedBox(height: OnCareSpacing.s16),
                    if (wide)
                      Row(
                        key: const ValueKey<String>('dashboard-action-row'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // 5:4 — 딱 반반은 아니다.
                          Expanded(flex: 5, child: leftColumn),
                          const SizedBox(width: OnCareSpacing.s16),
                          Expanded(flex: 4, child: rightColumn),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          leftColumn,
                          const SizedBox(height: OnCareSpacing.s16),
                          rightColumn,
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 몇 주 전까지 볼 수 있는가 — 무한정 뒤로 가면 저장된 기록이 없는 빈 주만
/// 계속 나온다. 서버 보관 기간(63일)이 이 범위에 맞춰져 있다(#1633).
const int _maxTaskProgressWeeksBack = 8;

/// 할 일 진행률 그래프가 보는 주 — 0 이 이번 주, 음수가 지난 주.
final _taskProgressWeekOffsetProvider = StateProvider<int>(
  (ref) => 0,
  name: 'taskProgressWeekOffset',
);

/// 오늘 할 일 진행률 — 선택한 주의 일별 완료 현황, 지난 할일(carried-over)
/// stacked in a different colour. `<`/`>` 로 지난 주 기록을 오갈 수 있다.
class _TaskProgressCard extends ConsumerWidget {
  const _TaskProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // 오늘 할 일 카드가 저장할 때 같은 provider 가 갱신돼 이 카드도 다시 그린다.
    final history = ref.watch(dailyTaskHistoryProvider).valueOrNull;
    final demoHistory = ref.watch(demoTaskHistoryProvider);
    final offset = ref.watch(_taskProgressWeekOffsetProvider);
    final today = nowKst();
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final monday = currentMonday.add(Duration(days: 7 * offset));
    final dates = <DateTime>[
      for (var i = 0; i < weekdayCount; i++) monday.add(Duration(days: i)),
    ];
    final OnCareBrand brand = context.oncare.brand;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 범례(오늘 처리/이월 처리)를 그래프 위 별도 줄 대신 제목 옆으로 —
          // 자리가 모자라면 범례만 FittedBox 로 줄어들고, 주 이동 버튼은
          // 터치 크기를 지킨다. 범례 칸은 Expanded 로 몫을 다 쓰고 그 안에서
          // 오른쪽 정렬한다 — Flexible(loose) 이면 범례가 안 쓴 몫이 버튼
          // 오른쪽 빈칸으로 남아 버튼이 카드 오른쪽 끝에 붙지 않았다.
          Row(
            children: <Widget>[
              Expanded(
                child: AppSectionHeader(
                  title: l.dashTaskProgressTitle,
                  icon: Icons.stacked_bar_chart_rounded,
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TaskProgressLegend(
                        color: brand.primary,
                        label: l.dashTaskProgressToday,
                      ),
                      const SizedBox(width: OnCareSpacing.s8),
                      TaskProgressLegend(
                        // 막대의 이월 처리 칸과 같은 색이다(#2214).
                        color: OnCareColors.chartGoalLine,
                        label: l.dashTaskProgressCarriedOver,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s12),
              AppIconButton(
                key: const ValueKey<String>('task-progress-prev-week'),
                icon: Icons.chevron_left_rounded,
                tooltip: l.a11yPrevWeek,
                // 배경 상자 없이 화살표만 — 제목 줄에서 화살표만 무거워
                // 보였다(#2202). 넘어갈 수 없는 쪽은 비활성 회색이 된다.
                color: brand.primary,
                onPressed: offset <= -_maxTaskProgressWeeksBack
                    ? null
                    : () => ref
                          .read(_taskProgressWeekOffsetProvider.notifier)
                          .state--,
              ),
              const SizedBox(width: OnCareSpacing.s4),
              AppIconButton(
                key: const ValueKey<String>('task-progress-next-week'),
                icon: Icons.chevron_right_rounded,
                tooltip: l.a11yNextWeek,
                color: brand.primary,
                onPressed: offset >= 0
                    ? null
                    : () => ref
                          .read(_taskProgressWeekOffsetProvider.notifier)
                          .state++,
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          TaskProgressChart(
            // 실제 기록이 먼저다. 데모 이력은 그 기록이 시작되기 전의 지난
            // 날들만 채운다(#1203). 이력을 읽기 전에는 데모도 그리지 않는다 —
            // 실제 기록이 있는 계정에서 데모 막대가 잠깐 비쳤다 사라진다.
            snapshots: <DailyTaskSnapshot?>[
              for (final d in dates)
                history == null
                    ? null
                    : history.read(ymd(d)) ?? demoHistory.snapshotFor(d),
            ],
            dates: dates,
            labels: weekdayLabels(l),
            todayIndex: offset == 0
                ? elapsedWeekdays(today) - 1
                : weekdayCount - 1,
            isCurrentWeek: offset == 0,
          ),
        ],
      ),
    );
  }
}

/// The four KPI tiles. Wraps to two rows on narrow content areas rather
/// than shrinking to unreadable widths.
class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.summary,
    required this.churnRisk,
    required this.wide,
  });

  final DashboardSummary summary;
  final List<ChurnRiskClient> churnRisk;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final cards = <Widget>[
      AppStatCard(
        label: l.dashMyClients,
        value: '${summary.activeClients}',
        unit: l.dashUnitPeople,
        icon: Icons.groups_rounded,
        caption: summary.totalClients > summary.activeClients
            ? l.dashDormantClients(summary.totalClients - summary.activeClients)
            : l.dashAllActive,
        onTap: () => context.go(AppRoutes.clients),
      ),
      AppStatCard(
        label: l.dashMessages,
        value: '${summary.unreadTotal}',
        unit: l.dashUnitCount,
        icon: Icons.mark_chat_unread_rounded,
        caption: summary.unreadTotal > 0
            ? l.dashWaitingClients(summary.unreadClients)
            : l.dashAllReplied,
        onTap: () => context.go(AppRoutes.messagesFor(null, filter: 'unread')),
      ),
      AppStatCard(
        label: l.dashAttentionClients,
        value: '${summary.healthAttentionCount}',
        unit: l.dashUnitPeople,
        icon: Icons.report_gmailerrorred_rounded,
        // 0명이면 초록(정상), 1명 이상이면 빨강 — 숫자와 아이콘을 칠한다.
        toneColor: summary.healthAttentionCount == 0
            ? OnCareColors.success
            : OnCareColors.danger,
        caption: summary.healthAttentionCount == 0
            ? l.dashNoIssues
            : l.dashCheckSodiumCompletion,
        onTap: () => context.go(AppRoutes.clientsFiltered('attention')),
      ),
      AppStatCard(
        label: l.dashChurnRisk,
        value: '${churnRisk.length}',
        unit: l.dashUnitPeople,
        icon: Icons.person_off_rounded,
        // 주의 회원과 같은 규칙·같은 빨강 — 톤이 다르면 서로 다른 심각도로 읽힌다.
        toneColor: churnRisk.isEmpty
            ? OnCareColors.success
            : OnCareColors.danger,
        caption: churnRisk.isEmpty ? l.dashChurnRiskNone : l.dashChurnRiskCheck,
        onTap: () => showChurnRiskDialog(context, entries: churnRisk),
      ),
    ];

    // IntrinsicHeight so the tiles line up: the hint line is present on
    // some and absent on others, which otherwise staggers the row.
    if (wide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < cards.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: OnCareSpacing.s16),
              Expanded(child: cards[i]),
            ],
          ],
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (var i = 0; i < cards.length; i += 2) ...<Widget>[
          if (i > 0) const SizedBox(height: OnCareSpacing.s16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: cards[i]),
                const SizedBox(width: OnCareSpacing.s16),
                if (i + 1 < cards.length)
                  Expanded(child: cards[i + 1])
                else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

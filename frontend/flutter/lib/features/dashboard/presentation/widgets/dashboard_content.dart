import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/ai_advice_text.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/services/exercise_goals_provider.dart';
import 'package:oncare/shared/widgets/ai_advice_card.dart';
import 'package:oncare/shared/widgets/chart_semantics.dart';
import 'package:oncare/shared/widgets/coaching_sheet.dart';
import 'package:oncare/shared/widgets/member_tab_header.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare/shared/widgets/modals/schedule_calendar_sheet.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// The Home tab, rebuilt to match the On-Care Figma redesign.
///
/// Sections (top → bottom): header, AI coaching banner, a 식단·영양 card
/// (칼로리·나트륨·당류 지표 카드 + 탄단지 + 선택한 지표의 주간 추이) and a
/// 운동 card (좌측 지표 3종 + 우측 주간 추이), 이번 주 AI 추천 식단 carousel,
/// 오늘의 일정. Per the product decision the 건강 지표 (심박수·수면) cards and
/// the sleep AI-coaching banner are omitted.
///
/// 틀은 모바일 페이지 틀(`AppPage`)이다 — 연회색 배경·좌우 여백·최대 폭·탭 머리를
/// 틀이 정하고, 이 화면은 내용만 쌓는다(#1699).
class DashboardContent extends StatelessWidget {
  const DashboardContent({
    super.key,
    this.onNotificationTap,
    this.onCalendarTap,
  });

  final VoidCallback? onNotificationTap;
  final VoidCallback? onCalendarTap;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      header: _HomeHeader(
        onNotificationTap: onNotificationTap,
        onCalendarTap: onCalendarTap,
      ),
      // 셸이 하단 바 뒤까지 본문을 늘리므로 바가 가린 만큼 아래를 비운다.
      bottomInset: MediaQuery.paddingOf(context).bottom,
      children: <Widget>[
        Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            return ref
                .watch(dashboardSummaryProvider)
                .when(
                  loading: () => const AppLoading(),
                  error: (Object error, StackTrace stackTrace) =>
                      AppErrorState(
                        title: AppLocalizations.of(
                          context,
                        ).homeDashboardLoadError,
                        retryLabel: AppLocalizations.of(context).actionRetry,
                        onRetry: () => ref.invalidate(dashboardSummaryProvider),
                      ),
                  data: (DashboardSummary summary) => _DashboardData(
                    summary: summary,
                    // 홈 배너로 열어도 같은 시트다 — 배지도 같이 내려간다.
                    onCoachingTap: () => showCoachingSheet(context, ref: ref),
                    onDietTap: () => context.go(AppRoutes.diet),
                    onExerciseTap: () => context.go(AppRoutes.exercise),
                  ),
                );
          },
        ),
      ],
    );
  }
}

/// 홈 탭 머리. 벨 점은 서버 미읽음을 본다 — 이 머리만 다시 그린다.
class _HomeHeader extends ConsumerWidget implements PreferredSizeWidget {
  const _HomeHeader({this.onNotificationTap, this.onCalendarTap});

  final VoidCallback? onNotificationTap;
  final VoidCallback? onCalendarTap;

  @override
  Size get preferredSize =>
      const MemberTabHeader(title: '', trailingAction: SizedBox.shrink())
          .preferredSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MemberTabHeader(
      title: 'On - Care',
      leading: const MemberLogo(),
      trailingAction: const TrainerChatHeaderButton(),
      onBell: onNotificationTap,
      bellHasUnread:
          (ref.watch(notificationUnreadProvider).valueOrNull ?? 0) > 0,
      onCalendar: onCalendarTap,
    );
  }
}

class _DashboardData extends StatelessWidget {
  const _DashboardData({
    required this.summary,
    required this.onCoachingTap,
    required this.onDietTap,
    required this.onExerciseTap,
  });

  final DashboardSummary summary;
  final VoidCallback onCoachingTap;
  final VoidCallback onDietTap;
  final VoidCallback onExerciseTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (summary.isEmpty) ...<Widget>[
          Text(
            l.homeDashboardEmpty,
            style: context.oncare
                .text(OnCareTypography.body)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.cardGap),
        ],
        _CoachingBanner(summary: summary, onTap: onCoachingTap),
        const SizedBox(height: OnCareSpacing.sectionGap),
        _DietNutritionCard(
          summary: summary,
          showCharts: !summary.isEmpty,
          onOpen: onDietTap,
        ),
        const SizedBox(height: OnCareSpacing.cardGap),
        _ExerciseCard(onOpen: onExerciseTap),
        const SizedBox(height: OnCareSpacing.sectionGap),
        const _RecommendedMeals(),
        // 오늘의 일정은 지금 쓰지 않는다. 되살릴 수 있어 지우지 않고 남겨
        // 둔다. (#1055)
        // _ScheduleCard(items: summary.todaySchedule),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────── coaching banner ──

/// 홈의 AI 조언 배너. 앱의 AI 카드 한 가지([AiAdviceShell])를 눌리는 모양으로
/// 쓴다 — 그라디언트 강조 카드는 없앴다(#1690).
class _CoachingBanner extends StatelessWidget {
  const _CoachingBanner({required this.summary, required this.onTap});
  final DashboardSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AiAdviceShell(
      // 플로팅 버튼을 감춘 동안(#862) AI 조언으로 들어가는 자리는 여기 하나다.
      key: const ValueKey<String>('home-coaching-banner'),
      title: l.homeAiAdviceTitle,
      onTap: onTap,
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: OnCareSize.iconMedium,
        color: tokens.brand.primary,
      ),
      child: Text(
        aiAdviceBody(l, summary),
        style: tokens
            .text(OnCareTypography.bodySmall)
            .copyWith(color: OnCareColors.textPrimary),
      ),
    );
  }
}

// ────────────────────────────────────────────────────── summary cards ──

/// 홈 카드 헤더 — 제목 + 자세히 링크. 식단·운동 카드가 같은 구조라 한 곳에 둔다.
///
/// 제목은 남는 폭 안에서 줄바꿈되고 링크는 항상 남는다 — 셋 다 고유 폭을 요구하던
/// 예전 구조는 폭이 모자라면 `RenderFlex overflowed` 를 냈다(#440).
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.label, this.onOpen});

  final IconData icon;
  final String label;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    // `AI 분석` 필은 뗐다 (#1055). 아이콘은 배경 틴트 없이 둔다 (#1117).
    return AppSectionHeader(
      title: label,
      icon: icon,
      actionLabel: AppLocalizations.of(context).homeDetails,
      onAction: onOpen,
    );
  }
}

/// 홈 식단·영양 카드에서 고른 지표(칼로리/나트륨/당류) — 탭을 벗어났다가 홈에
/// 다시 들어오면 기본값으로 되돌아가야 하는 임시 UI 상태라 Riverpod 에
/// 둔다(#861). 실제 요약 데이터(`dashboardSummaryProvider`)와는 분리된 값이다.
final _dashboardNutritionTabProvider = StateProvider<_NutTabKind>(
  (ref) => _NutTabKind.calories,
  name: 'dashboardNutritionTab',
);

/// 홈 탭 재진입 시 초기화할 임시 UI 상태 — 식단·영양 카드가 보여 주는 지표를
/// 기본값(칼로리)으로 되돌린다(#861).
void resetDashboardTransientUiState(WidgetRef ref) {
  ref.read(_dashboardNutritionTabProvider.notifier).state =
      _NutTabKind.calories;
}

// ───────────────────────────────────────────── diet + nutrition card ──
/// The merged 식단·영양 card: calorie ring + achievement, macro grams/goals,
/// and the weekly nutrition trend chart (legend + Y axis + point labels).
class _DietNutritionCard extends ConsumerWidget {
  const _DietNutritionCard({
    required this.summary,
    required this.showCharts,
    required this.onOpen,
  });
  final DashboardSummary summary;
  final bool showCharts;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _NutTabKind tab = ref.watch(_dashboardNutritionTabProvider);
    final AppLocalizations l = AppLocalizations.of(context);
    final Map<_NutTabKind, _NutData> nutrition = _nutritionFor(summary);
    final _NutData cfg = nutrition[tab]!;
    final List<String> days = weekDayLabels(l);
    final int todayIdx = _todayIndex();
    final NumberFormat nf = NumberFormat('#,###');
    final String chartTitle = l.homeWeeklyMetricTrend(_nutLabel(l, tab));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHeader(
            icon: Icons.restaurant_rounded,
            label: l.homeDietNutritionTitle,
            onOpen: onOpen,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 상단: 칼로리·나트륨·당류를 큰 숫자 칸으로 나란히. 누르면 아래
          // 그래프가 그 지표의 주간 추이로 바뀐다.
          Row(
            children: <Widget>[
              for (final _NutTabKind kind in nutrition.keys) ...<Widget>[
                if (kind != nutrition.keys.first)
                  const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: _MetricStatCard(
                    label: _nutLabel(l, kind),
                    indicator: _indicatorFor(summary, kind),
                    selected: tab == kind,
                    onTap: () =>
                        ref
                                .read(_dashboardNutritionTabProvider.notifier)
                                .state =
                            kind,
                  ),
                ),
              ],
            ],
          ),
          if (showCharts) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s12),
            Row(
              key: const ValueKey<String>('dashboard-nutrition-chart'),
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // 목표는 그래프의 목표선 라벨이 말한다 — 카드 위에 또
                      // 적으면 한 화면에서 같은 말이 두 번 나온다(#756).
                      _ChartLegend(title: chartTitle),
                      const SizedBox(height: OnCareSpacing.s8),
                      MetricTrendChart(
                        values: cfg.cur,
                        dayLabels: days,
                        goal: cfg.goal,
                        ticks: cfg.ticks,
                        todayIndex: todayIdx,
                        // 지표를 바꾸면 선을 처음부터 다시 그려 값이 바뀐 것을
                        // 눈으로 따라가게 한다.
                        replayKey: tab,
                        // 화면 위 제목과 같은 문구로 시작한다 — 음성 안내에서도
                        // 이 그래프가 어느 지표의 것인지가 먼저 들린다.
                        semanticsLabel: chartSemanticsLabel(
                          l,
                          title: chartTitle,
                          points: chartSeriesPoints(
                            l,
                            values: cfg.cur,
                            dayLabels: days,
                            format: (double v) => '${nf.format(v)}${cfg.unit}',
                            // 선은 오늘까지만 잇는다. 아직 오지 않은 요일을
                            // 읽으면 화면에 없는 값을 말하게 된다.
                            upTo: todayIdx,
                          ),
                        ),
                        goalLabel: '${l.homeGoal}\n${nf.format(cfg.goal)}',
                        formatTick: nf.format,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 식단 카드 상단의 지표 칸 하나 — "칼로리" 라벨 + 큰 숫자 + "/2,000kcal"
/// 목표치. 누르면 아래 주간 추이 그래프가 이 지표로 바뀐다.
///
/// 카드 안 칸이라 안쪽 타일 모양(반경 12)이고, 선택은 옅은 브랜드 채움 +
/// 브랜드 테두리다(#1690 선택 상태).
class _MetricStatCard extends StatelessWidget {
  const _MetricStatCard({
    required this.label,
    required this.indicator,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final HealthIndicator indicator;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool over =
        indicator.overBudget ||
        (indicator.max > 0 && indicator.current > indicator.max);
    final TextStyle subStyle = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textSecondary);
    // 선택 상태를 색으로만 알리면 스크린리더 사용자는 어떤 지표가 켜져 있는지도,
    // 이 칸이 누를 수 있는 요소인지도 알 수 없다.
    return Semantics(
      button: true,
      selected: selected,
      label: '$label (${indicator.unit})',
      child: Material(
        color: selected ? tokens.brand.surface : OnCareColors.surfaceInput,
        shape: RoundedRectangleBorder(
          borderRadius: OnCareRadius.mdAll,
          side: BorderSide(
            color: selected ? tokens.brand.primary : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: OnCareSpacing.s8,
              vertical: OnCareSpacing.s12,
            ),
            child: Column(
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: subStyle),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                // 초과는 배지가 아니라 수치 자체를 빨갛게 해서 말한다. 배지는
                // 카드마다 있고 없고가 갈려 카드 높이를 들쭉날쭉하게 만들었다
                // (#1070). 색은 어느 카드에도 자리를 더 먹지 않는다.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _metricNumber(indicator.current),
                    maxLines: 1,
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.display),
                    ).copyWith(
                      color: over
                          ? OnCareColors.danger
                          : OnCareColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                // 목표치는 작은 글씨로 현재 수치 바로 아래. 단위는 라벨이
                // 아니라 목표치 오른쪽에 붙인다("/2,000kcal") — 라벨에 두면
                // "칼로리 (kcal)" 처럼 길어져 좁은 칸에서 먼저 줄어들었다.
                // 목표가 없는 지표(max=0)면 단위만 남겨 큰 숫자가 단위를 잃지
                // 않게 한다.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    indicator.max > 0
                        ? '/${_metricNumber(indicator.max)}${indicator.unit}'
                        : indicator.unit,
                    maxLines: 1,
                    style: subStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 이번 주의 시작(월요일). 운동 탭과 같은 기준으로 잘라야 홈이 같은 한 주를
/// 말한다.
DateTime _thisMonday() {
  final DateTime n = nowKst();
  final DateTime d = DateTime(n.year, n.month, n.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// 홈의 운동 카드 — 제목 줄 아래에 운동 탭 `운동 현황 · 이번 주` 와 **같은
/// 카드**를 그린다 (#1183).
///
/// 예전에는 왼쪽에 지표 네 줄, 오른쪽에 주간 소모 막대그래프를 두었다. 같은 한
/// 주를 두 화면이 다른 그림으로 말하고 있었고, 홈에서 본 것과 운동 탭에서 본
/// 것을 머릿속에서 다시 맞춰야 했다. 이제 그림도 하나다 — 값의 출처
/// (`exerciseWeekViewProvider` · `exerciseLoadGoalsProvider`)는 예전부터 이미
/// 같았다.
class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 운동 탭과 같은 단일 소스에서 읽어 두 화면이 항상 일치한다. 이 provider 는
    // 오늘 체크한 AI 추천 운동까지 이미 더한 값이다.
    final AsyncValue<ExerciseWeek> weekAsync = ref.watch(
      exerciseWeekViewProvider,
    );
    // 새로고침 중에는 직전 값을 계속 그린다 — 이미 맞는 그림을 지웠다 다시
    // 그리면 깜빡임만 는다.
    final ExerciseWeek? wk = weekAsync.valueOrNull;
    // MY 건강 목표에서 저장한 값을 운동 탭과 함께 읽는다 (#1139).
    final ExerciseLoadGoals goals = ref.watch(exerciseLoadGoalsProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHeader(
            icon: Icons.fitness_center_rounded,
            label: l.dashboardMetricExercise,
            onOpen: onOpen,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (wk != null)
            ExerciseWeekLoadCard(
              key: const ValueKey<String>('dashboard-exercise-week'),
              loads: dayLoadsOfWeek(wk, _thisMonday()),
              goals: goals,
              // 이미 홈 카드 안이다 — 카드 바탕을 한 겹 더 그리지 않는다.
              surface: false,
            )
          else if (weekAsync.hasError)
            _ExerciseUnavailable(
              // 되짚는 대상은 파생 provider 가 아니라 실제로 서버를 부르는
              // 쪽이다 — 뷰만 무효화하면 캐시된 에러가 그대로 다시 계산돼
              // 아무 일도 일어나지 않는다.
              onRetry: () => ref.invalidate(exerciseWeekProvider),
            )
          else
            const _ExercisePlaceholder(),
        ],
      ),
    );
  }
}

/// 주간 기록을 불러오지 못했을 때. 값을 지어내는 대신 못 불러왔다고 적고,
/// 다시 시도할 자리를 준다 (#962).
class _ExerciseUnavailable extends StatelessWidget {
  const _ExerciseUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return SizedBox(
      key: const ValueKey<String>('dashboard-exercise-error'),
      height: _kExerciseBodyHeight,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.homeExerciseTrendUnavailable,
            style: context.oncare
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          AppButton(
            key: const ValueKey<String>('dashboard-exercise-retry'),
            label: l.actionRetry,
            onPressed: onRetry,
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
          ),
        ],
      ),
    );
  }
}

/// 아직 읽는 중. 자리만 잡아 두면 값이 도착했을 때 카드가 튀지 않는다.
class _ExercisePlaceholder extends StatelessWidget {
  const _ExercisePlaceholder();

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey<String>('dashboard-exercise-loading'),
    height: _kExerciseBodyHeight,
    width: double.infinity,
    child: const DecoratedBox(
      decoration: BoxDecoration(
        color: OnCareColors.surfaceInput,
        borderRadius: OnCareRadius.mdAll,
      ),
    ),
  );
}

/// 실패·로딩 자리가 잡는 높이. 값이 도착하면 그 자리에 이번 주 카드가 서므로
/// 같은 높이를 쓴다 — 카드가 튀지 않는다.
double get _kExerciseBodyHeight => kActivityCardHeight;

// ───────────────────────────────────────────────────── nutrition data ──

class _NutData {
  const _NutData({
    required this.cur,
    required this.unit,
    required this.goal,
    required this.ticks,
    required this.warn,
  });
  final List<double> cur;
  final String unit;
  final double goal;

  /// 세로축(가로 눈금선) 값들. 지표마다 다르게 지정한다.
  final List<double> ticks;
  final bool warn;
}

/// Stable identity for a nutrition tab, decoupled from its displayed label
/// so the shown language never becomes an internal key.
enum _NutTabKind { calories, sodium, sugar }

/// 지표마다 고정된 표시 규칙 — 단위·눈금. 값은 여기 없다.
///
/// 예전에는 이 자리에 주간 이력 예시 숫자까지 함께 들어 있었고, 응답이 7일을
/// 채우지 않으면 그 숫자가 그대로 그려졌다. 화면에 뜬 한 주가 회원의 것이
/// 아닐 수 있다는 뜻이라, 표시 규칙만 남기고 값은 응답에서만 온다(#962).
///
/// 그래프 색은 지표와 무관하게 식단 그래프 색 하나다(`OnCareBrand.dietChart`) —
/// 여기 두던 지표별 색은 그리는 곳이 없어 뺐다.
const Map<_NutTabKind, _NutStyle> _nutStyles = <_NutTabKind, _NutStyle>{
  _NutTabKind.calories: _NutStyle(
    unit: 'kcal',
    // 맨 아래 0 눈금은 당류 그래프와 같은 기준선 역할이라 항상 넣는다 —
    // 세 지표가 한 카드에서 탭으로 바뀌는데 축의 바닥이 서로 달랐다 (#548).
    // 그 위 눈금은 2개만 둔다. 라벨 칸은 16px 인데 촘촘히(1000·1500·2000·2500)
    // 놓으면 칸 간격이 16px 을 밑돌아 아래쪽 라벨끼리 겹쳐 숫자를 읽을 수
    // 없었다. 목표선은 따로 그리지 않으므로(상단 '목표 N' 라벨과 데이터
    // 포인트 상태색으로만 표현) 2000 을 빼도 잃는 정보가 없다.
    ticks: <double>[0, 1500, 2500],
  ),
  _NutTabKind.sodium: _NutStyle(
    unit: 'mg',
    ticks: <double>[0, 1750, 3500],
  ),
  _NutTabKind.sugar: _NutStyle(
    unit: 'g',
    ticks: <double>[0, 25, 50],
  ),
};

class _NutStyle {
  const _NutStyle({required this.unit, required this.ticks});
  final String unit;
  final List<double> ticks;
}

Map<_NutTabKind, _NutData> _nutritionFor(DashboardSummary summary) {
  final liveValues = <_NutTabKind, HealthIndicator>{
    _NutTabKind.calories: summary.calorieIndicator,
    _NutTabKind.sodium: summary.sodiumIndicator,
    _NutTabKind.sugar: summary.sugarIndicator,
  };
  final List<NutritionDay>? week = summary.nutritionWeek.length == 7
      ? summary.nutritionWeek
      : null;
  // 주간 이력이 없으면 오늘 값만 제 요일 자리에 놓고 나머지는 비운다 —
  // 없는 기록을 지어내지 않는다.
  final int todayIdx = _todayIndex();
  return <_NutTabKind, _NutData>{
    for (final entry in _nutStyles.entries)
      entry.key: _NutData(
        cur: week != null
            ? <double>[
                for (final day in week)
                  switch (entry.key) {
                    _NutTabKind.calories => day.calories.toDouble(),
                    _NutTabKind.sodium => day.sodiumMg.toDouble(),
                    _NutTabKind.sugar => day.sugarG,
                  },
              ]
            : <double>[
                for (int i = 0; i < 7; i++)
                  i == todayIdx ? liveValues[entry.key]!.current.toDouble() : 0,
              ],
        unit: entry.value.unit,
        goal: liveValues[entry.key]!.max.toDouble(),
        ticks: entry.value.ticks,
        warn: liveValues[entry.key]!.overBudget,
      ),
  };
}

/// 오늘 요일 인덱스(0=월 … 6=일). 고정 라벨 배열 `_weekDayLabels` 와 함께 써서
/// 주간 차트의 '오늘' 배지·라이브 값을 실제 요일 칸에 배치하고, 오늘 이후(미래)
/// 요일의 0값이 급락처럼 보이지 않도록 렌더 범위를 오늘까지로 제한한다.
/// 홈 카드 전체가 이 하나만 쓴다(지표 카드·차트 기준이 어긋나지 않도록).
int _todayIndex() => nowKst().weekday - 1;

/// 지표 키 → 화면 라벨(칼로리/나트륨/당류).
String _nutLabel(AppLocalizations l, _NutTabKind key) => switch (key) {
  _NutTabKind.calories => l.dashboardMetricCalories,
  _NutTabKind.sodium => l.dietSodium,
  _NutTabKind.sugar => l.dietSugar,
};

/// 지표 수치 표기. 정수는 천단위 콤마만 붙이고, 소수가 있으면 한 자리까지
/// 남긴다(당류 17.8 이 18 로 반올림돼 지표 카드와 그래프 라벨·식단 탭 수치가
/// 서로 어긋나던 문제).
String _metricNumber(num v) => v == v.roundToDouble()
    ? NumberFormat('#,###').format(v)
    : NumberFormat('#,##0.#').format(v);

/// 지표 키 → 오늘 수치(현재값·목표·초과 여부).
HealthIndicator _indicatorFor(DashboardSummary s, _NutTabKind key) =>
    switch (key) {
      _NutTabKind.calories => s.calorieIndicator,
      _NutTabKind.sodium => s.sodiumIndicator,
      _NutTabKind.sugar => s.sugarIndicator,
    };

// ───────────────────────────────────────────────────── recommended meals ──

/// 추천 식단 카드의 폭과 사진 높이. 가로로 흘러가는 목록이라 카드 폭이 고정이다.
const double _kRecMealCardWidth = 128;
const double _kRecMealPhotoHeight = 72;

/// 추천을 누가 골랐는지. 트레이너가 짚어 준 식단과 AI 가 고른 식단은 회원이
/// 받아들이는 무게가 다르다 — 카드에 적어 둔다. (#1056)
enum _RecSource { trainer, ai }

class _RecMeal {
  const _RecMeal(
    this.photo,
    this.emoji,
    this.name,
    this.reason,
    this.tag, {
    this.source = _RecSource.ai,
  });

  /// Bundled dish photo shown on the card. [emoji] over the tile colour is
  /// the fallback when the asset is missing, so the section still renders
  /// end-to-end.
  final String photo;
  final String emoji;
  final String name;
  final String reason;

  /// 영양 특성 배지. 어휘는 여섯 가지로 고정한다 — 같은 뜻을 화면마다 다른
  /// 말로 부르지 않기 위해서다. (#1056)
  final String tag;

  final _RecSource source;

  /// 사진·태그는 그대로 두고 추천 이유 문구만 바꾼 사본.
  /// 서버가 개인화 문구를 보냈을 때 쓴다.
  _RecMeal withReason(String newReason) =>
      _RecMeal(photo, emoji, name, newReason, tag, source: source);

  /// 출처만 바꾼 사본.
  _RecMeal withSource(_RecSource newSource) =>
      _RecMeal(photo, emoji, name, reason, tag, source: newSource);
}

/// 서버 카탈로그 key → 화면 표시(사진·이모지·문구).
///
/// 추천 API 는 무엇을 어떤 순서로 보여줄지(`key`)만 정하고, 실제 그리기는 여기서
/// 한다. 사진은 앱 번들 에셋이고 문구는 로케일별 ARB 라, 서버가 문자열을 만들면
/// 영어 화면에 한국어가 섞이고 사진 없는 요리가 나오기 때문이다.
/// key 값은 백엔드 `app/data/meal_catalog.py` 와 일치해야 한다.
///
/// 사진이 빠졌을 때의 바탕은 요리마다 색을 고르지 않고 안쪽 타일 색 하나로 둔다 —
/// 요리별 색은 식단 탭의 끼니 색과 같은 값을 따로 들고 있었다.
Map<String, _RecMeal> _recMealsByKey(AppLocalizations l) => <String, _RecMeal>{
  'chicken_salad': _RecMeal(
    'assets/images/rec-chicken-salad.jpg',
    '🥗',
    l.homeMealChickenSalad,
    l.homeMealReasonSodium,
    l.homeMealTagLowSodium,
  ),
  'brown_rice_box': _RecMeal(
    'assets/images/rec-brown-rice-box.jpg',
    '🍱',
    l.homeMealBrownRiceBox,
    l.homeMealReasonGlucose,
    // 혈당을 가리키던 `저GI` 는 이 앱이 다른 곳에서 쓰지 않는 말이었다.
    l.homeMealTagLowSugar,
  ),
  'salmon': _RecMeal(
    'assets/images/rec-salmon-steak.jpg',
    '🐟',
    l.homeMealSalmon,
    l.homeMealReasonOmega,
    l.homeMealTagHighProtein,
  ),
  'tofu': _RecMeal(
    'assets/images/rec-tofu-broccoli.png',
    '🥦',
    l.homeMealTofu,
    l.homeMealReasonLowCal,
    l.homeMealTagLowCal,
  ),
  'namul_bibimbap': _RecMeal(
    'assets/images/rec-namul-bibimbap.png',
    '🥬',
    l.homeMealNamulBibimbap,
    l.homeMealReasonFiber,
    // 나물 위주라 지방이 적다 — `고식이섬유` 는 정해 둔 여섯 어휘 밖이다.
    l.homeMealTagLowFat,
  ),
};

/// 이유 코드 → 기본 문구. 서버가 개인화 문구(`reasonText`)를 주지 않았을 때 쓴다.
/// 요리별 기본 이유는 카탈로그에 고정돼 있어, 이 경로면 화면이 서버 연동 이전과
/// 완전히 같아진다.
String? _reasonTextFor(AppLocalizations l, String reasonKey) =>
    switch (reasonKey) {
      'sodium' => l.homeMealReasonSodium,
      'glucose' => l.homeMealReasonGlucose,
      'omega' => l.homeMealReasonOmega,
      'low_cal' => l.homeMealReasonLowCal,
      'fiber' => l.homeMealReasonFiber,
      _ => null,
    };

/// 개인화 근거 한 줄 — 예: "최근 3일 평균 나트륨 2,400mg · 권장 초과".
///
/// 서버가 준 `basis` 문자열을 쓰지 않고 수치로 다시 만든다. `basis` 는 서버가 조립한
/// 한국어라 영어 로케일에 그대로 쓰면 문구가 섞인다(요리명·이유를 key 로 주고받는
/// 것과 같은 이유).
///
/// 개인화되지 않았거나 근거 데이터가 없으면 null — 목업/데모 모드와 신규 가입자가
/// 이 경로라, 화면에 아무것도 추가되지 않는다.
String? _basisTextFor(AppLocalizations l, MealRecommendations recs) {
  if (!recs.personalized || recs.daysWithData <= 0 || recs.avgSodiumMg <= 0) {
    return null;
  }
  final String sodium = NumberFormat.decimalPattern().format(recs.avgSodiumMg);
  final String base = l.homeRecBasisSodium(recs.daysWithData, sodium);
  return recs.sodiumOverLimit ? '$base · ${l.homeRecBasisOverLimit}' : base;
}

/// 추천 응답 → 카드 목록.
///
/// 앱이 모르는 key(서버 카탈로그가 먼저 늘어난 경우)는 그릴 방법이 없으므로
/// 조용히 버리고, 그만큼을 기본 순서에서 채워 카드 수를 유지한다.
List<_RecMeal> _cardsFor(AppLocalizations l, MealRecommendations recs) {
  final Map<String, _RecMeal> byKey = _recMealsByKey(l);
  final List<_RecMeal> cards = <_RecMeal>[];
  final Set<String> used = <String>{};

  for (final MealRecommendation rec in recs.items) {
    final _RecMeal? base = byKey[rec.key];
    if (base == null || used.contains(rec.key)) continue;
    used.add(rec.key);
    final String reason =
        rec.reasonText ?? _reasonTextFor(l, rec.reasonKey) ?? base.reason;
    cards.add(base.withReason(reason));
  }

  for (final String key in kDefaultMealKeys) {
    if (cards.length >= kDefaultMealKeys.length) break;
    if (used.contains(key)) continue;
    used.add(key);
    final _RecMeal? base = byKey[key];
    if (base != null) cards.add(base);
  }
  return cards;
}

class _RecommendedMeals extends ConsumerWidget {
  const _RecommendedMeals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // valueOrNull 이라 로딩·에러에서 기본 추천이 그대로 그려진다. 스켈레톤을 두면
    // 홈 진입 때 카드가 한 번 비었다가 채워져 화면이 깜빡인다(목업 모드에서는
    // 결과가 기본값과 같아 아예 아무 변화도 보이지 않는다).
    final MealRecommendations recs =
        ref.watch(dietRecommendationsProvider).valueOrNull ??
        MealRecommendations.fallback;
    // 담당 트레이너가 있는 회원의 첫 장은 트레이너가 짚어 준 자리다. 담당이
    // 없으면 그 배지를 달지 않는다 — 없는 사람의 추천이라고 말하게 된다.
    final bool hasCoach = ref.watch(memberCoachProvider).valueOrNull != null;
    final List<_RecMeal> meals = <_RecMeal>[
      for (final (int i, _RecMeal meal) in _cardsFor(l, recs).indexed)
        i == 0 && hasCoach ? meal.withSource(_RecSource.trainer) : meal,
    ];
    // 개인화된 응답일 때만 근거를 보여준다. 목업/데모 모드와 신규 가입자는
    // personalized=false 라 이 줄이 아예 나타나지 않는다(화면 불변).
    final String? basis = _basisTextFor(l, recs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: OnCareSpacing.s8,
          runSpacing: OnCareSpacing.s4,
          children: <Widget>[
            Text(
              l.homeRecMealsTitle,
              style: tokens
                  .text(OnCareTypography.titleSmall)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
            if (basis != null)
              Text(
                basis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
          ],
        ),
        // 카드 높이를 숫자로 박지 않는다 (#1118). 예전에는 설명 두 줄을 미리
        // 잡아 두느라, 설명이 한 줄인 카드는 태그 아래가 통째로 비었다.
        // IntrinsicHeight 가 실제 내용으로 높이를 재고, 카드끼리는 가장 높은
        // 것에 맞춰 늘어난다 — 글씨 배율이 커져도 계산이 어긋날 자리가 없다.
        //
        // 아래 여백은 카드 그림자가 뷰포트에 잘리지 않을 만큼이다. 위보다
        // 넉넉한 것은 그림자가 아래로 치우쳐 지기 때문.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(
            top: OnCareSpacing.s12,
            bottom: OnCareSpacing.s16,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < meals.length; i++) ...<Widget>[
                  if (i != 0) const SizedBox(width: OnCareSpacing.cardGap),
                  _RecMealCard(meal: meals[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 카드 좌측 상단의 추천 출처 배지. 사진 위에 얹히므로 바탕은 불투명하다 —
/// 트레이너 추천은 브랜드 채움, AI 추천은 옅은 브랜드 채움이다.
class _RecSourceBadge extends StatelessWidget {
  const _RecSourceBadge({required this.source});

  final _RecSource source;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool trainer = source == _RecSource.trainer;
    return _Badge(
      label: trainer ? l.homeMealSourceTrainer : l.homeMealSourceAi,
      textKey: const Key('rec-meal-source'),
      fill: trainer ? tokens.brand.primary : tokens.brand.surface,
      foreground: trainer ? OnCareColors.textOnFill : tokens.brand.primary,
    );
  }
}

/// 태그 모양(알약·높이 24·`caption` 600) 그대로, 글자에 열쇠를 달 수 있게 풀어 둔
/// 배지. 추천 카드의 테스트가 글자를 찾아 읽는다.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.textKey,
    required this.fill,
    required this.foreground,
  });

  final String label;
  final Key textKey;
  final Color fill;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: OnCareSize.tagHeight,
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: OnCareRadius.pillAll,
      ),
      child: Text(
        label,
        key: textKey,
        // 영어 태그는 길어서 두 줄이 되고, 그만큼 설명이 눌려 사라진다 — 한
        // 줄로 못 박는다. (#1004)
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.oncare
            .text(OnCareTypography.strong(OnCareTypography.caption))
            .copyWith(color: foreground),
      ),
    );
  }
}

class _RecMealCard extends StatelessWidget {
  const _RecMealCard({required this.meal});
  final _RecMeal meal;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return SizedBox(
      width: _kRecMealCardWidth,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                Image.asset(
                  meal.photo,
                  height: _kRecMealPhotoHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  // Fall back to the emoji tile if the bundled photo is missing.
                  errorBuilder: (BuildContext context, Object _, StackTrace? _) =>
                      _emojiHeader(context),
                ),
                // 누가 고른 추천인지 사진 위에 얹는다 — 카드가 좁아 아래 글자
                // 자리를 더 쓰면 이름이나 이유가 밀린다. (#1056)
                Positioned(
                  left: OnCareSpacing.s8,
                  top: OnCareSpacing.s8,
                  right: OnCareSpacing.s8,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _RecSourceBadge(source: meal.source),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(OnCareSpacing.s8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    meal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                  const SizedBox(height: OnCareSpacing.s2),
                  // 카드 폭이 좁아 설명은 가장 작은 역할 글자로 둔다 — 제목이
                  // 진한 글씨라 부제는 작은 회색이어야 위계도 산다.
                  Text(
                    meal.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  // 배지 색은 하나다 (#1056). 요리마다 색이 달라지면 색이
                  // 영양 특성을 뜻하는지 요리 종류를 뜻하는지 알 수 없다.
                  _Badge(
                    label: meal.tag,
                    textKey: const Key('rec-meal-tag'),
                    fill: tokens.brand.surface,
                    foreground: tokens.brand.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiHeader(BuildContext context) => Container(
    height: _kRecMealPhotoHeight,
    width: double.infinity,
    color: context.oncare.brand.surface,
    alignment: Alignment.center,
    child: Text(meal.emoji, style: context.oncare.text(OnCareTypography.display)),
  );
}

// ───────────────────────────────────────────────────────── schedule ──

/// 홈 하단의 오늘 일정 카드. 지금은 화면에 걸지 않았다 (#1055) — 지우지 않고
/// 남겨 둔 것이라 쓰이지 않는다는 경고를 여기서 끈다.
// ignore: unused_element
class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.items});

  final List<ScheduleItem> items;

  /// 트레이너가 잡아 준 오늘의 PT 를 일정 항목으로 바꾼다. (#490)
  ///
  /// 별도 카드를 만들지 않고 여기 합치는 이유: 회원 입장에서 '오늘 뭐 하지'는
  /// 하나의 질문이다. PT 만 따로 떼면 같은 시간대를 두 곳에서 봐야 한다.
  ///
  /// 데모는 담당 일정이 없어(`MockMemberCoachRepository.fetchSessions`) 빈
  /// 목록이 오므로 카드가 지금과 똑같이 그려진다.
  static List<ScheduleItem> _todaysSessions(List<CoachSession> sessions) {
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return <ScheduleItem>[
      for (final CoachSession session in sessions)
        if (session.isUpcoming && session.date != null)
          if (DateTime(
                session.date!.year,
                session.date!.month,
                session.date!.day,
              ) ==
              today)
            ScheduleItem(time: session.time, title: session.type, emoji: '🏋️'),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final DateTime now = nowKst();
    final String weekday = weekDayLabels(l)[now.weekday - 1];
    final String todayLabel = l.homeScheduleDate(weekday, now.month, now.day);
    // 트레이너 일정과 내가 만든 일정을 한 목록으로 보여 준다. 시간순으로 섞어야
    // '다음에 뭐가 있는지'를 한 번에 읽을 수 있다.
    final List<ScheduleItem> merged =
        <ScheduleItem>[
          ...items,
          ..._todaysSessions(
            ref.watch(coachSessionsProvider).valueOrNull ??
                const <CoachSession>[],
          ),
        ]..sort(
          (ScheduleItem first, ScheduleItem second) =>
              first.time.compareTo(second.time),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(
          title: l.homeScheduleTitle,
          actionLabel: l.homeViewAll,
          onAction: () => showScheduleCalendarSheet(context),
        ),
        Text(
          todayLabel,
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        if (merged.isEmpty)
          AppTile(
            child: Text(
              l.homeScheduleEmpty,
              style: tokens
                  .text(OnCareTypography.body)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          )
        else
          for (int index = 0; index < merged.length; index++) ...<Widget>[
            _ScheduleItemCard(item: merged[index]),
            if (index != merged.length - 1)
              const SizedBox(height: OnCareSpacing.s8),
          ],
      ],
    );
  }
}

class _ScheduleItemCard extends StatelessWidget {
  const _ScheduleItemCard({required this.item});

  final ScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Semantics(
      button: true,
      child: AppTile(
        onTap: () => showScheduleCalendarSheet(context),
        child: Row(
          children: <Widget>[
            Text(
              item.time,
              style: OnCareTypography.numeric(
                tokens.text(OnCareTypography.titleSmall),
              ).copyWith(color: tokens.brand.primary),
            ),
            const SizedBox(width: OnCareSpacing.s16),
            Expanded(
              child: Row(
                children: <Widget>[
                  if (item.emoji.isNotEmpty) ...<Widget>[
                    Text(item.emoji),
                    const SizedBox(width: OnCareSpacing.s8),
                  ],
                  Expanded(
                    child: Text(
                      item.title,
                      style: tokens
                          .text(OnCareTypography.titleSmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: OnCareSize.iconMedium,
              color: tokens.brand.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.title});

  /// "주간 {지표} 추이" — 선택된 지표에 따라 바뀌는 그래프 왼쪽 상단 제목.
  final String title;

  @override
  Widget build(BuildContext context) {
    // 범례(이번 주/지난 주)와 목표 수치는 제거. 목표는 그래프 안의 목표선
    // 라벨이 말한다(#756).
    return Row(
      children: <Widget>[
        Expanded(
          // 그래프 제목은 그 그래프가 무슨 지표인지를 말한다 — 줄임표가 되면
          // (`Weekly Calories tre…`) 그 역할이 사라진다. 좁으면 줄인다. (#1004)
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              title,
              maxLines: 1,
              style: context.oncare
                  .text(OnCareTypography.titleSmall)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

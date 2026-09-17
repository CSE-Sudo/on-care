import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/ai_advice_text.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
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
import 'package:oncare_ui/oncare_ui.dart';

/// The Home tab, rebuilt to match the On-Care Figma redesign.
///
/// Sections (top → bottom): header, AI coaching banner, a 식단·영양 card
/// (탄수화물·단백질·지방 지표 카드 + 이번 주 칼로리 추이) and a
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
    this.adviceAnchorKey,
  });

  final VoidCallback? onNotificationTap;

  /// 사용 가이드가 `오늘의 AI 통합 조언` 카드의 자리를 재는 열쇠(#1857). 홈은 이
  /// 값을 주지 않는다 — 가이드 화면만 자기 사본에 달아 쓴다.
  final GlobalKey? adviceAnchorKey;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      header: _HomeHeader(
        onNotificationTap: onNotificationTap,
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
                  error: (Object error, StackTrace stackTrace) => AppErrorState(
                    title: AppLocalizations.of(context).homeDashboardLoadError,
                    retryLabel: AppLocalizations.of(context).actionRetry,
                    onRetry: () => ref.invalidate(dashboardSummaryProvider),
                  ),
                  data: (DashboardSummary summary) => _DashboardData(
                    adviceAnchorKey: adviceAnchorKey,
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
  const _HomeHeader({this.onNotificationTap});

  final VoidCallback? onNotificationTap;

  @override
  Size get preferredSize => const MemberTabHeader(
    title: '',
    trailingAction: SizedBox.shrink(),
  ).preferredSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MemberTabHeader(
      title: 'On - Care',
      leading: const MemberLogo(),
      trailingAction: const TrainerChatHeaderButton(),
      onBell: onNotificationTap,
      bellHasUnread:
          (ref.watch(notificationUnreadProvider).valueOrNull ?? 0) > 0,
    );
  }
}

class _DashboardData extends StatelessWidget {
  const _DashboardData({
    required this.summary,
    this.adviceAnchorKey,
    required this.onCoachingTap,
    required this.onDietTap,
    required this.onExerciseTap,
  });

  final DashboardSummary summary;
  final GlobalKey? adviceAnchorKey;
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
        KeyedSubtree(
          key: adviceAnchorKey,
          child: _CoachingBanner(summary: summary, onTap: onCoachingTap),
        ),
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
      trailing: AppIcon(
        AppIcons.chevronRight,
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

// ───────────────────────────────────────────── diet + nutrition card ──
/// 홈 식단·영양 카드 — 오늘의 탄단지 세 칸과 **이번 주 칼로리 추이** 꺾은선.
///
/// 예전에는 세 칸이 곧 지표 전환 버튼이어서, 누르면 아래 그래프가 그 지표의
/// 주간 추이로 바뀌었다(#861 의 임시 UI 상태가 그 선택이었다). 지금은 그래프가
/// 칼로리 하나로 고정이다(#1879) — 그래서 이 카드에는 되돌릴 선택 자체가 없고,
/// 세 칸은 누르는 것이 아니라 **읽는 것**이다.
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
    final AppLocalizations l = AppLocalizations.of(context);
    // 탄단지 목표는 식단 탭 하루 요약과 **같은 값**을 쓴다. 홈만 따로 기본값을
    // 들고 있으면 회원이 목표를 고쳤을 때 두 화면이 다른 목표를 말한다.
    final UserProfile? profile = ref.watch(profileProvider).asData?.value;
    final _NutData cfg = _calorieWeek(summary);
    final List<String> days = weekDayLabels(l);
    final int todayIdx = _todayIndex();
    final NumberFormat nf = NumberFormat('#,###');
    final String chartTitle = l.homeWeeklyMetricTrend(
      l.dashboardMetricCalories,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHeader(
            icon: AppIcons.diet,
            label: l.homeDietNutritionTitle,
            onOpen: onOpen,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 상단: 오늘의 탄수화물·단백질·지방을 큰 숫자 칸으로 나란히.
          Row(
            children: <Widget>[
              for (final _NutTabKind kind in _NutTabKind.values) ...<Widget>[
                if (kind != _NutTabKind.values.first)
                  const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: _MetricStatCard(
                    label: _nutLabel(l, kind),
                    indicator: _indicatorFor(summary, profile, kind),
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
                        // 그래프가 칼로리 하나라(#1879) 다시 재생할 전환이
                        // 없다 — 카드가 붙을 때 한 번 그려지고 멈춘다.
                        replayKey: chartTitle,
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

/// 식단 카드 상단의 지표 칸 하나 — "탄수화물" 라벨 + 큰 숫자 + "/275g" 목표치.
///
/// 카드 안 칸이라 안쪽 타일 모양(반경 12)이다. 예전에는 눌러서 아래 그래프의
/// 지표를 고르는 버튼이었지만, 그래프가 칼로리 하나로 고정된 뒤로는(#1879)
/// 누를 곳이 아니다 — 선택 상태도, 그것을 알리던 브랜드 채움·테두리도 없다.
class _MetricStatCard extends StatelessWidget {
  const _MetricStatCard({required this.label, required this.indicator});

  final String label;
  final HealthIndicator indicator;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool over =
        indicator.overBudget ||
        (indicator.max > 0 && indicator.current > indicator.max);
    final TextStyle subStyle = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textSecondary);
    // 라벨·수치·목표가 따로 읽히면 "탄수화물", "203.6", "/275g" 세 토막이 된다.
    // 한 칸을 한 번에 읽히게 묶고 단위를 라벨에 붙여 준다.
    return Semantics(
      container: true,
      label: '$label (${indicator.unit})',
      child: Material(
        // 카드와 같은 흰 바탕이다. 칸을 회색으로 채우면 누를 수 있는 것처럼
        // 보이는데, 지표 전환이 사라진 뒤로는(#1879) 누를 곳이 아니다 —
        // 칸의 경계는 채움이 아니라 얇은 선이 말한다.
        color: OnCareColors.surfaceCard,
        shape: const RoundedRectangleBorder(
          borderRadius: OnCareRadius.mdAll,
          side: BorderSide(color: OnCareColors.lineSubtle),
        ),
        clipBehavior: Clip.antiAlias,
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
                  style:
                      OnCareTypography.numeric(
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
              // 아니라 목표치 오른쪽에 붙인다("/275g") — 라벨에 두면
              // "탄수화물 (g)" 처럼 길어져 좁은 칸에서 먼저 줄어들었다.
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
            icon: AppIcons.exercise,
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
enum _NutTabKind { carbs, protein, fat }

/// 탄단지 지표 칸의 단위. 셋 다 그램이다.
const String _kMacroUnit = 'g';

/// 주간 추이 꺾은선의 세로 눈금. **식단 탭과 같은 값**이라(`diet_period_view`
/// 의 `_kCalorieTicks`) 두 화면이 같은 한 주를 다른 축으로 그리지 않는다.
///
/// 맨 아래 0 눈금은 축의 바닥을 고정한다(#548). 그 위 눈금은 2개만 둔다 —
/// 라벨 칸은 16px 이라 촘촘히(1000·1500·2000·2500) 놓으면 칸 간격이 16px 을
/// 밑돌아 아래쪽 라벨끼리 겹쳐 숫자를 읽을 수 없었다. 목표선은 따로 그리므로
/// 2000 을 빼도 잃는 정보가 없다.
const List<double> _kCalorieTicks = <double>[0, 1500, 2500];

/// 이번 주 칼로리 추이 — 그래프가 그리는 값·목표·눈금 한 덩어리.
///
/// 예전에는 지표(칼로리/나트륨/당류)마다 같은 것을 만들어 지도로 들고 다녔다.
/// 그래프가 칼로리 하나로 고정된 뒤로는(#1879) 하나면 된다.
///
/// 값은 응답에서만 온다 — 예전에는 주간 이력 예시 숫자를 코드가 들고 있다가
/// 응답이 7일을 채우지 않으면 그 숫자를 그대로 그렸다. 화면에 뜬 한 주가
/// 회원의 것이 아닐 수 있다는 뜻이었다(#962).
_NutData _calorieWeek(DashboardSummary summary) {
  final HealthIndicator today = summary.calorieIndicator;
  final List<NutritionDay>? week = summary.nutritionWeek.length == 7
      ? summary.nutritionWeek
      : null;
  // 주간 이력이 없으면 오늘 값만 제 요일 자리에 놓고 나머지는 비운다 —
  // 없는 기록을 지어내지 않는다.
  final int todayIdx = _todayIndex();
  return _NutData(
    cur: week != null
        ? <double>[for (final day in week) day.calories.toDouble()]
        : <double>[
            for (int i = 0; i < 7; i++)
              i == todayIdx ? today.current.toDouble() : 0,
          ],
    unit: today.unit,
    goal: today.max.toDouble(),
    ticks: _kCalorieTicks,
    warn: today.overBudget,
  );
}

/// 오늘 요일 인덱스(0=월 … 6=일). 고정 라벨 배열 `_weekDayLabels` 와 함께 써서
/// 주간 차트의 '오늘' 배지·라이브 값을 실제 요일 칸에 배치하고, 오늘 이후(미래)
/// 요일의 0값이 급락처럼 보이지 않도록 렌더 범위를 오늘까지로 제한한다.
/// 홈 카드 전체가 이 하나만 쓴다(지표 카드·차트 기준이 어긋나지 않도록).
int _todayIndex() => nowKst().weekday - 1;

/// 지표 키 → 화면 라벨(탄수화물/단백질/지방). 식단 탭과 같은 문구를 쓴다.
String _nutLabel(AppLocalizations l, _NutTabKind key) => switch (key) {
  _NutTabKind.carbs => l.homeMacroCarbs,
  _NutTabKind.protein => l.homeMacroProtein,
  _NutTabKind.fat => l.homeMacroFat,
};

/// 지표 수치 표기. 정수는 천단위 콤마만 붙이고, 소수가 있으면 한 자리까지
/// 남긴다(당류 17.8 이 18 로 반올림돼 지표 카드와 그래프 라벨·식단 탭 수치가
/// 서로 어긋나던 문제).
String _metricNumber(num v) => v == v.roundToDouble()
    ? NumberFormat('#,###').format(v)
    : NumberFormat('#,##0.#').format(v);

/// 지표 키 → 오늘 수치(현재값·목표·초과 여부).
///
/// 탄단지는 서버 `indicators`(칼로리·나트륨·당류) 밖에 있다 — 오늘 합계는
/// `macros`, 목표는 회원 프로필에서 온다. 목표를 못 읽으면 식단 탭과 같은
/// 기본값으로 떨어진다.
HealthIndicator _indicatorFor(
  DashboardSummary s,
  UserProfile? p,
  _NutTabKind key,
) {
  final (double current, int goal) = switch (key) {
    _NutTabKind.carbs => (
      s.macros.carbsG,
      p?.effectiveDailyCarbsG ?? UserProfile.defaultDailyCarbsG,
    ),
    _NutTabKind.protein => (
      s.macros.proteinG,
      p?.effectiveDailyProteinG ?? UserProfile.defaultDailyProteinG,
    ),
    _NutTabKind.fat => (
      s.macros.fatG,
      p?.effectiveDailyFatG ?? UserProfile.defaultDailyFatG,
    ),
  };
  return HealthIndicator(
    // 라벨은 화면이 [_nutLabel] 로 따로 붙인다 — 이 값은 서버 `indicators` 의
    // 표시 문구를 담는 자리이고, 탄단지는 그 목록 밖이라 채울 것이 없다.
    label: '',
    current: current,
    max: goal,
    unit: _kMacroUnit,
    overBudget: current > goal,
  );
}

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
/// 트레이너 추천은 브랜드 채움, AI 추천은 흰 바탕에 옅은 테두리다.
///
/// 태그 높이(24)로 키우지 않는다. 사진이 낮아 태그 크기면 음식을 가리므로,
/// 글자에 딱 맞는 작은 알약으로 모서리에만 얹는다.
class _RecSourceBadge extends StatelessWidget {
  const _RecSourceBadge({required this.source});

  final _RecSource source;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool trainer = source == _RecSource.trainer;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s8,
        vertical: OnCareSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: trainer ? tokens.brand.primary : OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.pillAll,
        border: Border.all(
          color: trainer ? tokens.brand.primary : OnCareColors.lineSubtle,
        ),
      ),
      child: Text(
        trainer ? l.homeMealSourceTrainer : l.homeMealSourceAi,
        key: const Key('rec-meal-source'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tokens
            .text(OnCareTypography.strong(OnCareTypography.caption))
            .copyWith(
              color: trainer ? OnCareColors.textOnFill : tokens.brand.primary,
            ),
      ),
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
                  // 카드에서 이름은 사진 아래 따로 읽히지만, 사진 자체에
                  // 이름이 없으면 무엇의 사진인지 알 수 없다(#1942).
                  semanticLabel: AppLocalizations.of(
                    context,
                  ).a11yMealPhotoOf(meal.name),
                  fit: BoxFit.cover,
                  // Fall back to the emoji tile if the bundled photo is missing.
                  errorBuilder:
                      (BuildContext context, Object _, StackTrace? _) =>
                          _emojiHeader(context),
                ),
                // 누가 고른 추천인지 사진 위에 얹는다 — 카드가 좁아 아래 글자
                // 자리를 더 쓰면 이름이나 이유가 밀린다. (#1056)
                // 끝쪽도 묶어 두어야 긴 영어 배지가 카드 밖으로 나가지 않고
                // 말줄임된다. 배지 자체는 글자 폭만큼만 차지한다.
                PositionedDirectional(
                  start: OnCareSpacing.s4,
                  top: OnCareSpacing.s4,
                  end: OnCareSpacing.s4,
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
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
                        .text(
                          OnCareTypography.strong(OnCareTypography.bodySmall),
                        )
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
    child: Text(
      meal.emoji,
      style: context.oncare.text(OnCareTypography.display),
    ),
  );
}

// ───────────────────────────────────────────────────────── schedule ──

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

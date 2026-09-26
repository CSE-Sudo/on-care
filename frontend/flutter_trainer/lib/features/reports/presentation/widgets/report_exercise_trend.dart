import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_trend_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/widgets/activity_charts.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// ④ 운동 추세 — 유형별 주간 목표 달성률 도넛 셋과 최근 여덟 주. (#2232)
///
/// 유산소는 분, 근력은 세트, 스트레칭은 분으로 재는 값이라 **서로 더할 수도,
/// 나란히 높이를 견줄 수도 없다.** 그래서 셋을 각자의 주간 목표에 대한
/// 달성률로 바꿔 같은 모양의 도넛으로 그린다 — 비교되는 것은 값이 아니라
/// "자기 목표에 얼마나 왔나" 다.
///
/// 도넛 하나에 이번 주만 담으면 `70%` 가 좋아진 70 인지 나빠진 70 인지 알 수
/// 없다. 그래서 칸마다 지난 여덟 주에서 읽은 한 줄을 붙인다 — `5주 연속 감소`
/// 는 이번 주 수치가 말하지 못하는 것을 말한다.
///
/// 회원 앱 운동 탭·고객 상세의 [BurnGoalRings] 와 같은 색·같은 순서(유산소 →
/// 근력 → 스트레칭)를 쓴다. 겹친 링 대신 도넛 셋으로 펼치는 까닭은, 이 카드는
/// 회원에게 보낼 글의 근거라 **유형 하나를 짚어 말할 수 있어야** 하기 때문이다.
class ReportExerciseTrend extends ConsumerWidget {
  /// Creates the section.
  const ReportExerciseTrend({super.key, required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final ReportTrendKey key = (
      clientId: report.client.id,
      weekStart: report.weekStart,
    );
    final ReportTrend? trend = ref.watch(reportTrendProvider(key)).valueOrNull;
    final ReportTrendWeek? current = trend?.current;
    // 못 읽은 주를 0 으로 그리면 "그 주에 아무것도 안 했다" 는 다른 말이 된다.
    if (trend == null || current == null) {
      return AppEmptyState(
        key: const ValueKey<String>('report-trend-empty'),
        title: l.reportsTrendUnavailable,
        icon: Icons.fitness_center_rounded,
        placement: AppStatePlacement.card,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final List<Widget> cards = <Widget>[
              for (final ExerciseKind kind in ExerciseKind.values)
                _KindCard(trend: trend, kind: kind),
            ];
            // 좁으면 셋을 아래로 쌓는다 — 도넛 옆에 칼로리가 서야 하는 칸이라
            // 폭이 모자라면 글씨부터 줄바꿈으로 무너진다.
            if (constraints.maxWidth < OnCareLayout.splitBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final Widget card in cards) ...<Widget>[
                    card,
                    if (card != cards.last)
                      const SizedBox(height: OnCareSpacing.s12),
                  ],
                ],
              );
            }
            // 세 칸의 높이를 맞춘다. 흐름 한 줄의 길이가 칸마다 달라 그냥 두면
            // 카드 바닥이 들쭉날쭉해진다. `stretch` 만으로는 안 되는데, 이
            // 카드가 세로로 무한한 스크롤 안에 서기 때문이다.
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final Widget card in cards) ...<Widget>[
                    Expanded(child: card),
                    if (card != cards.last)
                      const SizedBox(width: OnCareSpacing.s12),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: OnCareSpacing.s16),
        const AppDivider(),
        const SizedBox(height: OnCareSpacing.s12),
        _TrendTotals(trend: trend),
        const SizedBox(height: OnCareSpacing.s12),
        const AppDivider(),
        const SizedBox(height: OnCareSpacing.s12),
        _TrackedExercises(report: report),
      ],
    );
  }
}

/// 유형 한 칸 — 도넛 · 소모 칼로리 · 주간 목표 · 흐름 한 줄.
class _KindCard extends StatelessWidget {
  const _KindCard({required this.trend, required this.kind});

  final ReportTrend trend;
  final ExerciseKind kind;

  /// 도넛의 바깥 지름.
  static const double _size = 76;

  /// 고리 두께.
  static const double _stroke = 9;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ReportTrendWeek week = trend.current!;
    final double? ratio = trend.ratioOf(kind, week);
    final int? percent = ratio == null ? null : (ratio * 100).round();

    return AppTile(
      key: ValueKey<String>('report-trend-${kind.name}'),
      tone: AppTileTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            kindLabel(l, kind),
            style: tokens.text(
              OnCareTypography.strong(OnCareTypography.bodySmall),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            children: <Widget>[
              SizedBox(
                width: _size,
                height: _size,
                child: CustomPaint(
                  painter: _DonutPainter(
                    // 한 바퀴를 넘긴 주는 회원 탭 운동 도넛처럼 두 바퀴째를
                    // 이어 그린다 — 끝 아래 그림자가 어디서 멈췄는지 짚는다.
                    ratio: ratio ?? 0,
                    color: kindColor(kind),
                    stroke: _stroke,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          l.reportsTrendCenterLabel,
                          style: tokens
                              .text(OnCareTypography.caption)
                              .copyWith(color: OnCareColors.textTertiary),
                        ),
                        Text(
                          percent == null
                              ? l.reportsTrendNoGoal
                              : l.reportsPdfValuePercent(formatNumber(percent)),
                          style: tokens.text(
                            OnCareTypography.numeric(
                              OnCareTypography.strong(
                                OnCareTypography.bodySmall,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 한 축에서 셋을 견줄 수 있는 유일한 값이 칼로리라, 그것이
                    // 가장 크게 선다. 분·세트는 그 아래 원래 단위로 남는다.
                    Text(
                      '${formatNumber(week.caloriesOf(kind))}${l.unitKcal}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text(
                        OnCareTypography.numeric(
                          OnCareTypography.strong(OnCareTypography.titleSmall),
                        ),
                      ),
                    ),
                    Text(
                      kindValueText(l, kind, week.valueOf(kind)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .text(OnCareTypography.caption)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Text(
            l.reportsTrendWeeklyGoal(
              kindValueText(l, kind, trend.goals.weeklyGoalOf(kind)),
            ),
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          _RunLine(trend: trend, kind: kind),
        ],
      ),
    );
  }
}

/// `▼ 5주 연속 감소` — 그 유형이 흘러온 방향 한 줄.
///
/// 연속 구간이 없으면 지난 주 대비로 떨어진다. 둘 다 말할 수 없는 주(첫 주,
/// 지난 주가 0 인 주)에는 **빈 줄 대신** 견줄 것이 없다고 적는다 — 빈 자리는
/// 좋은 소식으로 읽힌다.
class _RunLine extends StatelessWidget {
  const _RunLine({required this.trend, required this.kind});

  final ReportTrend trend;
  final ExerciseKind kind;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ReportTrendRun run = trend.runOf(kind);
    final int? delta = trend.deltaOf(kind);

    final (String text, bool rising, bool known) = switch ((run.weeks, delta)) {
      (final int weeks, _) when weeks > 0 => (
        run.rising ? l.reportsTrendRunUp(weeks) : l.reportsTrendRunDown(weeks),
        run.rising,
        true,
      ),
      (_, final int d) when d != 0 => (
        l.reportsTrendVsLastWeek(d > 0 ? '+$d' : '$d'),
        d > 0,
        true,
      ),
      (_, final int _) => (l.reportsTrendFlat, true, false),
      _ => (l.reportsTrendNoHistory, true, false),
    };

    return Text(
      known ? '${rising ? '▲' : '▼'} $text' : text,
      maxLines: 2,
      style: tokens
          .text(OnCareTypography.strong(OnCareTypography.caption))
          .copyWith(
            color: !known
                ? OnCareColors.textTertiary
                : rising
                ? OnCareColors.success
                : OnCareColors.danger,
          ),
    );
  }
}

/// 트랙 위에 원호 하나. 그림자는 다른 도넛들과 같은 두 겹이다.
class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.ratio,
    required this.color,
    required this.stroke,
  });

  final double ratio;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // 회원 탭 → 운동 탭의 도넛과 **같은 붓**으로 그린다 — 끝(캡) 아래의
    // 그림자와 `>` 까지 같아야 두 화면의 고리가 같은 것으로 읽힌다.
    paintRing(
      canvas,
      size.center(Offset.zero),
      (size.shortestSide - stroke) / 2,
      stroke,
      ratio,
      color,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.ratio != ratio || old.color != color || old.stroke != stroke;
}

/// 도넛 아래 합계 줄 — 이번 주 달성률 · 여덟 주 평균 · 내림세.
class _TrendTotals extends StatelessWidget {
  const _TrendTotals({required this.trend});

  final ReportTrend trend;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double? rate = trend.rateOf(trend.current!);
    final double? average = trend.averageRate;
    final int falling = trend.fallingWeeks;

    String percent(double? value) => value == null
        ? l.chartNoRecord
        : l.reportsPdfValuePercent(formatNumber((value * 100).round()));

    return Wrap(
      spacing: OnCareSpacing.s24,
      runSpacing: OnCareSpacing.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _TrendTotal(
          label: l.reportsTrendRate,
          value: percent(rate),
          // 이번 주가 여덟 주 평균에 못 미치면 붉게 짚는다 — 같은 52% 라도
          // 평균이 40% 인 회원과 74% 인 회원에게 뜻이 다르다.
          alarming: rate != null && average != null && rate < average,
        ),
        _TrendTotal(
          label: l.reportsTrendAverage(kReportTrendWeeks),
          value: percent(average),
          alarming: false,
        ),
        if (falling > 0)
          Text(
            '▼ ${l.reportsTrendRateFalling(falling)}',
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.danger),
          ),
      ],
    );
  }
}

/// 이름 한 줄 + 수 한 줄 — 격자 합계와 같은 모양이다.
class _TrendTotal extends StatelessWidget {
  const _TrendTotal({
    required this.label,
    required this.value,
    required this.alarming,
  });

  final String label;
  final String value;
  final bool alarming;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          label,
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textTertiary),
        ),
        const SizedBox(width: OnCareSpacing.s8),
        Text(
          value,
          style: tokens
              .text(
                OnCareTypography.numeric(
                  OnCareTypography.strong(OnCareTypography.body),
                ),
              )
              .copyWith(
                color: alarming
                    ? OnCareColors.danger
                    : OnCareColors.textPrimary,
              ),
        ),
      ],
    );
  }
}

/// 그 주에 가장 자주 한 종목 셋. (#2232)
///
/// 유형(유산소·근력·스트레칭)까지만 보면 `근력이 줄었다` 에서 멈춘다. 회원에게
/// 보낼 글은 종목 이름까지 가야 한다 — 무엇을 빼고 무엇을 넣을지가 거기서
/// 정해진다. 고르는 것은 사람이 아니라 그 주의 기록이라 `자동 선별됨` 이다.
class _TrackedExercises extends StatelessWidget {
  const _TrackedExercises({required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<({String name, int count})> top = trackedExercises(report);
    if (top.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.reportsTrendTracked(top.length),
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: tokens.brand.primary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Wrap(
          spacing: OnCareSpacing.s8,
          runSpacing: OnCareSpacing.s8,
          children: <Widget>[
            for (final ({String name, int count}) item in top)
              AppTag(
                key: ValueKey<String>('report-tracked-${item.name}'),
                label:
                    '${item.name} · ${l.reportsTrendTrackedTimes(item.count)}',
              ),
          ],
        ),
      ],
    );
  }
}

/// 그 주에 가장 자주 나온 종목 이름과 횟수. 많은 순, 같으면 이름 순이다.
List<({String name, int count})> trackedExercises(
  WeeklyReport report, {
  int max = 3,
}) {
  final Map<String, int> counts = <String, int>{};
  for (final ReportDay day in report.days) {
    for (final String name in day.exercises) {
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  final List<String> names = counts.keys.toList()
    ..sort((String a, String b) {
      final int byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return <({String name, int count})>[
    for (final String name in names.take(max))
      (name: name, count: counts[name]!),
  ];
}

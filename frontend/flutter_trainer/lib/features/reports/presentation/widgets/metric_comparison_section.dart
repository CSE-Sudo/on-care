import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/bar_line_chart.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 운동 상자가 견주는 값.
enum ExerciseCompareMetric {
  /// 그 주에 태운 열량(kcal).
  burned,

  /// 유산소·근력·스트레칭 시간(분).
  cardio,
  strength,
  stretching,
}

/// 식단 상자가 견주는 값.
enum DietCompareMetric {
  /// 하루 평균 칼로리(kcal). 막대는 탄·단·지로 쌓는다.
  calories,

  /// 하루 평균 나트륨(mg).
  sodium,

  /// 하루 평균 당류(g).
  sugar,
}

/// 비교 그래프의 막대 영역 높이 — 막대 둘이 상자 안에서 값 차이가 읽히는 높이.
const double _chartHeight = 96;

/// 비교 그래프 막대 최대 폭 — 칸이 둘뿐이라 넓게 두되 통짜 블록이 되지 않게.
const double _maxBarWidth = 46;

/// 지표 색에서 꺾은선 색으로 어둡게 섞는 비율. 막대와 같은 계열을 유지하면서
/// 옅은 색(스트레칭)의 선도 흰 바탕에서 보이게 한다.
const double _lineDarken = 0.3;

/// 이번 주 vs 지난 주 — 운동과 식단을 흰 상자 둘로 나눠 나란히 놓는다.
///
/// 한 상자 안에서는 알약 버튼으로 지표를 갈아 끼우고, 그래프는 `주간 운동
/// 이행률` 과 **같은 그림**(막대 + 꺾은선)이다. 카드마다 다른 막대를 쓰면 같은
/// 화면에서 눈금이 갈린 것처럼 보인다(#1177).
class MetricComparisonSection extends StatelessWidget {
  /// Creates the comparison section.
  const MetricComparisonSection({super.key, required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceInput,
        borderRadius: OnCareRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l.reportsComparisonTitle(
              report.isCurrentWeek ? l.reportsThisWeek : l.reportsSelectedWeek,
            ),
            style: context.oncare
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          LayoutBuilder(
            builder: (context, constraints) {
              final Widget workout = _ExerciseComparisonBox(report: report);
              final Widget diet = _DietComparisonBox(report: report);
              // 좁은 카드에서는 위아래로 쌓는다 — 한 줄에 우겨넣으면 상자 하나가
              // 막대 둘도 못 담는 폭이 된다.
              if (constraints.maxWidth < OnCareLayout.tabletBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    workout,
                    const SizedBox(height: OnCareSpacing.s8),
                    diet,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: workout),
                  const SizedBox(width: OnCareSpacing.s8),
                  Expanded(child: diet),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 흰 상자 하나 — 제목 · 알약 · 그래프(변화량은 두 막대를 잇는 선 위).
class _ComparisonBox extends StatelessWidget {
  const _ComparisonBox({
    required this.title,
    required this.caption,
    required this.pills,
    required this.previous,
    required this.current,
    required this.previousLabel,
    required this.currentLabel,
    required this.format,
    required this.goal,
    required this.segments,
    required this.legend,
    this.barColor,
    this.lineColor,
    required this.higherIsBetter,
    required this.loading,
    required this.emptyLabel,
    required this.semanticsLabel,
  });

  final String title;

  /// 값이 주 합계인지 하루 평균인지. 두 상자가 다른 기준을 쓰므로 적어 준다.
  final String caption;

  final List<Widget> pills;
  final double? previous;
  final double? current;
  final String previousLabel;
  final String currentLabel;
  final String Function(double) format;

  /// 넘으면 막대가 빨강이 되는 값.
  final double? goal;

  /// 막대를 쌓을 조각(칼로리의 탄·단·지). 없으면 한 색으로 채운다.
  final List<List<BarSegment>?>? segments;

  /// 조각이 무엇인지 적는 줄.
  final Widget? legend;

  /// 지금 고른 지표의 색. 주지 않으면 그래프의 기본 브랜드 색이다 — 식단
  /// 상자는 지금까지처럼 지표와 무관하게 한 색을 쓴다(#1424).
  final Color? barColor;
  final Color? lineColor;

  final bool? higherIsBetter;
  final bool loading;
  final String emptyLabel;
  final String semanticsLabel;

  /// 지난 주 대비 변화. 두 주 중 하나라도 값이 없으면 견줄 것이 없다.
  ///
  /// 제목 줄 오른쪽 끝에 따로 두던 것을 두 막대를 잇는 선 위로 옮겼다 —
  /// 떨어져 있으면 어느 두 막대 사이의 차이인지 한눈에 들어오지 않았다(#2186).
  BarLineDelta? _delta() {
    final double? delta = current == null || previous == null
        ? null
        : current! - previous!;
    if (delta == null) return null;
    // null 이면 좋고 나쁨을 가리지 않는다 — 칼로리처럼 목표에 가까울수록 좋은
    // 지표는 늘거나 줄었다는 사실만 적는다.
    final Color color = higherIsBetter == null
        ? OnCareColors.textSecondary
        : (delta >= 0) == higherIsBetter!
        ? OnCareColors.success
        : OnCareColors.danger;
    return (
      text: '${delta >= 0 ? '+' : '-'}${format(delta.abs())}',
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final l = AppLocalizations.of(context);
    final BarLineDelta? delta = _delta();
    // 눈금 끝은 두 주와 목표를 모두 담는다. 그 주의 최댓값에 맞춰 늘이면 두 주가
    // 늘 같은 높이에서 조금 다른 그림이 된다.
    final double ceiling = <double>[
      previous ?? 0,
      current ?? 0,
      if (goal != null) goal! * 1.05,
      1,
    ].reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(OnCareSpacing.s8),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: tokens
                    .text(OnCareTypography.label)
                    .copyWith(color: OnCareColors.textPrimary),
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Expanded(
                child: Text(
                  caption,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          // 범례는 알약 **오른쪽**에 둔다. 그래프 아래에 있던 때에는 칼로리를
          // 고를 때만 한 줄이 생겨 상자 높이가 달라졌고, 나란히 선 운동 상자와
          // 아래 끝이 어긋났다. 알약 줄은 지표와 무관하게 늘 있는 자리다(#1177).
          Row(
            children: <Widget>[
              Flexible(
                child: Wrap(
                  spacing: OnCareSpacing.s4,
                  runSpacing: OnCareSpacing.s4,
                  children: pills,
                ),
              ),
              if (legend != null) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                // 자리가 좁으면 줄을 접는 대신 글씨를 줄인다 — 접히는 순간
                // 상자 높이가 다시 달라진다.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: legend!,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          if (loading)
            const AppLoading(placement: AppStatePlacement.card)
          else
            BarLineChart(
              values: <double?>[previous, current],
              labels: <String>[previousLabel, currentLabel],
              ceiling: ceiling,
              goal: goal,
              segments: segments,
              barColor: barColor,
              lineColor: lineColor,
              format: format,
              emptyLabel: emptyLabel,
              highlightIndex: 1,
              height: _chartHeight,
              maxBarWidth: _maxBarWidth,
              delta: delta,
              // 운동·식단 상자가 나란히 서므로, 한쪽만 기록이 없어도 높이를 맞춘다.
              reserveDeltaSpace: true,
              // 변화는 캔버스에 그려지므로 음성 안내에는 문장으로 넘긴다.
              semanticsLabel: delta == null
                  ? semanticsLabel
                  : '$semanticsLabel · ${l.reportsCompareWith} ${delta.text}',
            ),
        ],
      ),
    );
  }
}

/// 운동 상자 — 소모 칼로리·유산소·근력·스트레칭을 주 합계로 견준다.
class _ExerciseComparisonBox extends ConsumerStatefulWidget {
  const _ExerciseComparisonBox({required this.report});

  final WeeklyReport report;

  @override
  ConsumerState<_ExerciseComparisonBox> createState() =>
      _ExerciseComparisonBoxState();
}

class _ExerciseComparisonBoxState
    extends ConsumerState<_ExerciseComparisonBox> {
  ExerciseCompareMetric _metric = ExerciseCompareMetric.burned;

  String _label(AppLocalizations l, ExerciseCompareMetric metric) =>
      switch (metric) {
        ExerciseCompareMetric.burned => l.clientTrendCaloriesBurned,
        ExerciseCompareMetric.cardio => l.routineTypeCardio,
        ExerciseCompareMetric.strength => l.routineTypeStrength,
        ExerciseCompareMetric.stretching => l.routineTypeStretching,
      };

  /// 지금 고른 지표의 색. 유형 셋은 다른 운동 그래프(주간 운동 시간·이행률
  /// 막대)와 같은 램프를(#1168), 소모 칼로리는 그 셋이 함께 만든 결과를 뜻하는
  /// 운동 그래프 색을 쓴다 — 같은 값이 화면마다 다른 색이면 색이 뜻을 잃는다.
  Color _metricColor(OnCareBrand brand) => switch (_metric) {
    ExerciseCompareMetric.burned => brand.exerciseChart,
    ExerciseCompareMetric.cardio => brand.exerciseCardio,
    ExerciseCompareMetric.strength => brand.exerciseStrength,
    ExerciseCompareMetric.stretching => brand.exerciseStretching,
  };

  /// 꺾은선은 같은 색의 한 단계 진한 쪽이다. 스트레칭처럼 옅은 색은 흰 바탕
  /// 위에서 선이 거의 보이지 않는다 — 막대와 같은 계열을 유지하면서 선만
  /// 또렷하게 둔다.
  Color _metricLineColor(OnCareBrand brand) =>
      Color.lerp(_metricColor(brand), OnCareColors.textPrimary, _lineDarken)!;

  double? _value(ClientExercisePeriod? period) {
    if (period == null) return null;
    // 그 주에 아무 기록도 없으면 0 이 아니라 '없음' 이다.
    if (period.days.every((d) => !d.logged)) return null;
    return switch (_metric) {
      ExerciseCompareMetric.burned => period.totalCalories,
      ExerciseCompareMetric.cardio => period.totalCardioMinutes,
      ExerciseCompareMetric.strength => period.totalStrengthMinutes,
      ExerciseCompareMetric.stretching => period.totalStretchingMinutes,
    }.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareBrand brand = context.oncare.brand;
    final report = widget.report;
    ClientPeriodKey keyFor(DateTime week) =>
        (clientId: report.client.id, period: ClientPeriod.week, day: week);
    final week = ref.watch(
      clientExercisePeriodProvider(keyFor(report.weekStart)),
    );
    final before = ref.watch(
      clientExercisePeriodProvider(
        keyFor(report.weekStart.subtract(const Duration(days: 7))),
      ),
    );
    final String unit = _metric == ExerciseCompareMetric.burned
        ? l.unitKcal
        : l.unitMinutes;
    String format(double v) => '${formatNumber(v.round())}$unit';
    return _ComparisonBox(
      title: l.clientTabWorkout,
      caption: l.reportsWeekTotal,
      pills: <Widget>[
        for (final metric in ExerciseCompareMetric.values)
          AppChoiceChip(
            key: ValueKey<String>('compare-exercise-${metric.name}'),
            label: _label(l, metric),
            selected: metric == _metric,
            onSelected: (_) => setState(() => _metric = metric),
          ),
      ],
      previous: _value(before.valueOrNull),
      current: _value(week.valueOrNull),
      previousLabel: l.reportsLastWeek,
      currentLabel: report.isCurrentWeek
          ? l.reportsThisWeek
          : l.reportsSelectedWeek,
      format: format,
      goal: null,
      segments: null,
      legend: null,
      // 지표를 바꾸면 그래프 색도 바뀐다 — 알약만 보고 무엇을 보고 있는지
      // 되짚지 않아도 되게(#1424).
      barColor: _metricColor(brand),
      lineColor: _metricLineColor(brand),
      // 운동은 많이 할수록 좋은 값이다.
      higherIsBetter: true,
      loading: week.isLoading || before.isLoading,
      emptyLabel: l.reportsDataInsufficient,
      semanticsLabel: '${l.clientTabWorkout} · ${_label(l, _metric)}',
    );
  }
}

/// 식단 상자 — 칼로리(탄·단·지)·나트륨·당류를 하루 평균으로 견준다.
class _DietComparisonBox extends ConsumerStatefulWidget {
  const _DietComparisonBox({required this.report});

  final WeeklyReport report;

  @override
  ConsumerState<_DietComparisonBox> createState() => _DietComparisonBoxState();
}

class _DietComparisonBoxState extends ConsumerState<_DietComparisonBox> {
  DietCompareMetric _metric = DietCompareMetric.calories;

  String _label(AppLocalizations l, DietCompareMetric metric) =>
      switch (metric) {
        DietCompareMetric.calories => l.metricCalories,
        DietCompareMetric.sodium => l.metricSodium,
        DietCompareMetric.sugar => l.metricSugar,
      };

  /// 하루 평균. 기록이 있는 날만 센다 — 아직 오지 않은 날을 0 으로 세면 이번
  /// 주가 늘 나아 보인다.
  double? _value(WeeklyReport? report) {
    if (report == null) return null;
    return switch (_metric) {
      DietCompareMetric.calories => recordedMean(report.caloriesWeek),
      DietCompareMetric.sodium => report.sodiumAvg?.toDouble(),
      DietCompareMetric.sugar => recordedMean(report.sugarWeek),
    };
  }

  double get _goal => switch (_metric) {
    DietCompareMetric.calories => calorieTargetKcal.toDouble(),
    DietCompareMetric.sodium => sodiumTargetMg.toDouble(),
    DietCompareMetric.sugar => sugarTargetG.toDouble(),
  };

  /// 그 주의 탄·단·지 하루 평균(g). 하나도 없으면 빈 목록이다.
  List<double> _macros(WeeklyReport? report) {
    if (report == null || _metric != DietCompareMetric.calories) {
      return const <double>[];
    }
    final means = <double>[
      recordedMean(report.carbsWeek) ?? 0,
      recordedMean(report.proteinWeek) ?? 0,
      recordedMean(report.fatWeek) ?? 0,
    ];
    return means.every((v) => v == 0) ? const <double>[] : means;
  }

  /// 막대를 쌓을 조각. 몫은 **열량 기여분**이다(탄·단 4kcal/g, 지방 9kcal/g) —
  /// 그램으로 쌓으면 열량의 절반을 내는 지방이 가장 얇게 그려져 막대 전체가
  /// 칼로리를 말하지 않게 된다. 색은 메인 색 한 가지의 농담이다(#953).
  List<BarSegment>? _segments(WeeklyReport? report, OnCareBrand brand) {
    final means = _macros(report);
    if (means.isEmpty) return null;
    return <BarSegment>[
      (value: means[0] * 4, color: brand.macroCarbs),
      (value: means[1] * 4, color: brand.macroProtein),
      (value: means[2] * 9, color: brand.macroFat),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareBrand brand = context.oncare.brand;
    final report = widget.report;
    final previous = ref.watch(
      weeklyReportProvider((
        client: report.client,
        weekStart: report.weekStart.subtract(const Duration(days: 7)),
      )),
    );
    final WeeklyReport? before = previous.valueOrNull;
    final String unit = switch (_metric) {
      DietCompareMetric.calories => l.unitKcal,
      DietCompareMetric.sodium => l.unitMg,
      DietCompareMetric.sugar => l.unitGram,
    };
    String format(double v) => _metric == DietCompareMetric.sugar
        ? '${formatNumber((v * 10).roundToDouble() / 10)}$unit'
        : '${formatNumber(v.round())}$unit';
    final List<double> means = _macros(report);
    return _ComparisonBox(
      title: l.clientTabDiet,
      caption: l.clientPeriodAverage,
      pills: <Widget>[
        for (final metric in DietCompareMetric.values)
          AppChoiceChip(
            key: ValueKey<String>('compare-diet-${metric.name}'),
            label: _label(l, metric),
            selected: metric == _metric,
            onSelected: (_) => setState(() => _metric = metric),
          ),
      ],
      previous: _value(before),
      current: _value(report),
      previousLabel: l.reportsLastWeek,
      currentLabel: report.isCurrentWeek
          ? l.reportsThisWeek
          : l.reportsSelectedWeek,
      format: format,
      goal: _goal,
      segments: <List<BarSegment>?>[
        _segments(before, brand),
        _segments(report, brand),
      ],
      legend: means.isEmpty
          ? null
          : _MacroLegend(means: means, unit: l.unitGram),
      // 칼로리는 목표에 가까울수록 좋은 값이라 어느 쪽도 아니다.
      higherIsBetter: _metric == DietCompareMetric.calories ? null : false,
      loading: previous.isLoading,
      emptyLabel: l.reportsDataInsufficient,
      semanticsLabel: '${l.clientTabDiet} · ${_label(l, _metric)}',
    );
  }
}

/// 탄·단·지 하루 평균을 색과 함께 적는다. 막대의 세 조각이 무엇인지 말하는
/// 유일한 자리다.
class _MacroLegend extends StatelessWidget {
  const _MacroLegend({required this.means, required this.unit});

  final List<double> means;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final labels = <String>[l.metricCarbs, l.metricProtein, l.metricFat];
    final colors = <Color>[
      tokens.brand.macroCarbs,
      tokens.brand.macroProtein,
      tokens.brand.macroFat,
    ];
    final TextStyle style = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textSecondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < labels.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppChartSwatch(color: colors[i]),
              const SizedBox(width: OnCareSpacing.s4),
              Text(
                '${labels[i]} ${formatNumber(means[i].round())}$unit',
                style: style,
              ),
              if (i < labels.length - 1)
                const SizedBox(width: OnCareSpacing.s8),
            ],
          ),
      ],
    );
  }
}

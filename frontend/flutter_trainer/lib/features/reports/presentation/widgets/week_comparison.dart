import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/bar_line_chart.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 두 주 막대 영역 높이 — 비교 상자의 그래프와 같은 높이다.
const double _chartHeight = 96;

/// 이번 주 vs 지난 주 — 같은 지표를 두 주로 나란히 놓는다.
class WeekComparison extends ConsumerWidget {
  const WeekComparison({super.key, required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final previousStart = report.weekStart.subtract(const Duration(days: 7));
    final previous = ref.watch(
      weeklyReportProvider((client: report.client, weekStart: previousStart)),
    );
    final before = previous.valueOrNull;
    final completionDelta = _delta(report.completionAvg, before?.completionAvg);
    final sodiumDelta = _delta(report.sodiumAvg, before?.sodiumAvg);
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
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          if (previous.isLoading)
            const AppLoading(placement: AppStatePlacement.card)
          else if (previous.hasError)
            Text(
              l.reportsPreviousLoadFailed,
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.danger),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final charts = <Widget>[
                  _ComparisonMetric(
                    key: const ValueKey<String>('completion-comparison-chart'),
                    label: l.reportsCompletionAvg,
                    current: report.completionAvg,
                    previous: before?.completionAvg,
                    previousLabel: l.reportsLastWeek,
                    currentLabel: report.isCurrentWeek
                        ? l.reportsThisWeek
                        : l.reportsSelectedWeek,
                    maxValue: 100,
                    valueSuffix: '%',
                    delta: completionDelta == null
                        ? null
                        : '${completionDelta >= 0 ? '+' : ''}$completionDelta%p',
                    positive: completionDelta == null || completionDelta >= 0,
                  ),
                  _ComparisonMetric(
                    key: const ValueKey<String>('sodium-comparison-chart'),
                    label: l.reportsAverageSodium,
                    current: report.sodiumAvg,
                    previous: before?.sodiumAvg,
                    previousLabel: l.reportsLastWeek,
                    currentLabel: report.isCurrentWeek
                        ? l.reportsThisWeek
                        : l.reportsSelectedWeek,
                    valueSuffix: 'mg',
                    delta: sodiumDelta == null
                        ? null
                        : '${sodiumDelta >= 0 ? '+' : ''}${sodiumDelta}mg',
                    positive: sodiumDelta == null || sodiumDelta <= 0,
                  ),
                ];
                if (constraints.maxWidth < OnCareLayout.tabletBreakpoint) {
                  return Column(
                    children: <Widget>[
                      charts.first,
                      const SizedBox(height: OnCareSpacing.s8),
                      charts.last,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: charts.first),
                    const SizedBox(width: OnCareSpacing.s8),
                    Expanded(child: charts.last),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  static int? _delta(int? current, int? previous) =>
      current == null || previous == null ? null : current - previous;
}

class _ComparisonMetric extends StatelessWidget {
  const _ComparisonMetric({
    super.key,
    required this.label,
    required this.current,
    required this.previous,
    required this.previousLabel,
    required this.currentLabel,
    required this.valueSuffix,
    required this.delta,
    required this.positive,
    this.maxValue,
  });

  final String label;
  final int? current;
  final int? previous;
  final String previousLabel;
  final String currentLabel;
  final String valueSuffix;
  final String? delta;
  final bool positive;
  final int? maxValue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final int highest = <int>[
      maxValue ?? 0,
      previous ?? 0,
      current ?? 0,
      1,
    ].reduce((a, b) => a > b ? a : b);
    String format(double v) => '${v.round()}$valueSuffix';
    // 기록이 없는 주는 읽지 않는다 — 빈 칸을 `0` 으로 읽으면 측정된 0 과
    // 구분되지 않는다.
    final List<String> points = <String>[
      if (previous != null)
        l.a11yChartPoint(previousLabel, format(previous!.toDouble())),
      if (current != null)
        l.a11yChartPoint(currentLabel, format(current!.toDouble())),
    ];
    return Container(
      padding: const EdgeInsets.all(OnCareSpacing.s8),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          // 리포트 탭의 두 주 비교는 모두 같은 막대 + 꺾은선 그림이다(#1177).
          BarLineChart(
            values: <double?>[previous?.toDouble(), current?.toDouble()],
            labels: <String>[previousLabel, currentLabel],
            ceiling: highest.toDouble(),
            format: format,
            emptyLabel: l.chartNoRecord,
            highlightIndex: 1,
            height: _chartHeight,
            semanticsLabel: points.isEmpty
                ? l.a11yChartEmpty(label)
                : l.a11yChartSummary(label, points.join(', ')),
          ),
          if (delta != null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                delta!,
                style:
                    OnCareTypography.numeric(
                      tokens.text(
                        OnCareTypography.strong(OnCareTypography.caption),
                      ),
                    ).copyWith(
                      color: positive
                          ? OnCareColors.success
                          : OnCareColors.danger,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

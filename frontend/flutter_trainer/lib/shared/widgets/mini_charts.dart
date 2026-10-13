import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/chart_a11y_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// A compact labelled bar series (주간 이행률, 세션 수 …).
///
/// Deliberately hand-built rather than pulled from a charting package:
/// the console needs exactly one chart shape here, trivial, and a chart
/// library would add build weight and its own theming surface for no
/// gain. If a real analytics screen ever needs
/// axes, tooltips and zoom, that's the moment to add one.
class BarSeriesChart extends StatelessWidget {
  /// Creates a bar series.
  const BarSeriesChart({
    super.key,
    required this.values,
    required this.labels,
    required this.title,
    this.height = 96,
    this.maxValue,
    this.highlightIndex,
    this.overThreshold,
    this.valueSuffix = '',
    this.showValues = false,
    this.pendingFromIndex,
    this.missingIndices = const <int>{},
  }) : assert(values.length == labels.length, 'values/labels 길이가 달라요');

  /// Bar values (non-negative).
  final List<int> values;

  /// X-axis labels, one per value.
  final List<String> labels;

  /// 그래프가 무엇을 그린 것인지. 막대는 높이로만 값을 말하고 [showValues] 가
  /// 꺼져 있으면 숫자가 화면 어디에도 없어, 음성 안내는 이 이름과 아래에서
  /// 만드는 요약 문장에 기댄다(#972).
  final String title;

  /// Plot height (excluding labels).
  final double height;

  /// Scale ceiling. Defaults to the largest value (min 1).
  final int? maxValue;

  /// Bar rendered in the strong primary fill (e.g. 오늘).
  final int? highlightIndex;

  /// Values strictly above this render in the warning colour.
  final int? overThreshold;

  /// Appended to the value label when [showValues] is on.
  final String valueSuffix;

  /// Whether to print the value above each bar.
  final bool showValues;

  /// First index that hasn't happened yet (e.g. tomorrow, in a Mon–Sun
  /// chart shown on Thursday). Those bars render as an empty track with
  /// no value, so a day with no data yet can't be misread as a zero.
  final int? pendingFromIndex;

  /// Indices whose value is unavailable rather than zero.
  ///
  /// The empty track and a `-` value keep missing comparison data from being
  /// misread as a measured zero.
  final Set<int> missingIndices;

  @override
  Widget build(BuildContext context) {
    final pendingFrom = pendingFromIndex ?? values.length;
    final ceiling = <int>[
      maxValue ?? 0,
      if (values.isNotEmpty) values.reduce((a, b) => a > b ? a : b),
      1,
    ].reduce((a, b) => a > b ? a : b);

    // 기록이 없는 칸(`missingIndices`)과 아직 오지 않은 칸은 읽지 않는다 —
    // 빈 트랙을 `0` 으로 읽으면 측정된 0 과 구분되지 않는다.
    final points = <String>[
      for (var i = 0; i < values.length && i < labels.length; i++)
        if (i < pendingFrom && !missingIndices.contains(i))
          chartPointLabel(
            AppLocalizations.of(context).chartA11y,
            labels[i],
            '${values[i]}$valueSuffix',
          ),
    ];

    return Semantics(
      container: true,
      label: chartSemanticsLabel(
        AppLocalizations.of(context).chartA11y,
        title: title,
        points: points,
      ),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: OnCareSpacing.s2,
                        ),
                        child: _Bar(
                          value: values[i],
                          ceiling: ceiling,
                          color: _colorFor(i),
                          label: showValues
                              ? missingIndices.contains(i)
                                    ? AppLocalizations.of(context).chartNoRecord
                                    : '${values[i]}$valueSuffix'
                              : null,
                          pending: i >= pendingFrom,
                          missing: missingIndices.contains(i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: OnCareSpacing.s4),
            Row(
              children: <Widget>[
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: context.oncare
                          .text(
                            highlightIndex == i
                                ? OnCareTypography.strong(
                                    OnCareTypography.caption,
                                  )
                                : OnCareTypography.caption,
                          )
                          .copyWith(
                            color: highlightIndex == i
                                ? OnCareBrand.trainer.primary
                                : i >= pendingFrom
                                ? OnCareColors.textDisabled
                                : OnCareColors.textTertiary,
                          ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _colorFor(int index) {
    if (overThreshold != null && values[index] > overThreshold!) {
      return OnCareColors.danger;
    }
    if (highlightIndex == index) return OnCareBrand.trainer.primary;
    return OnCareBrand.trainer.exerciseStrength;
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.ceiling,
    required this.color,
    required this.label,
    this.pending = false,
    this.missing = false,
  });

  final int value;
  final int ceiling;
  final Color color;
  final String? label;

  /// The day hasn't happened yet: draw the empty track only.
  ///
  /// Distinct from `value == 0`, which is a real "recorded, nothing done"
  /// and keeps its 2px stub — and from the value's own colour, which for
  /// a future day would otherwise paint the track red on a series with an
  /// `overThreshold`.
  final bool pending;

  /// No measurement exists for this bar.
  final bool missing;

  @override
  Widget build(BuildContext context) {
    // A zero value still draws a 2px stub so the day reads as "recorded,
    // nothing done" rather than "no data".
    final ratio = pending || missing ? 0.0 : (value / ceiling).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelHeight = label == null || pending ? 0.0 : 16.0;
        final plot = (constraints.maxHeight - labelHeight).clamp(
          0.0,
          constraints.maxHeight,
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (label != null && !pending)
              SizedBox(
                height: labelHeight,
                child: FittedBox(
                  child: Text(
                    label!,
                    style: context.oncare
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ),
              ),
            Container(
              // 칸이 2px 보다 낮으면 하한이 상한을 넘어 `clamp` 가
              // 던진다(#3250) — 그때는 칸 높이가 곧 하한이다.
              height: (plot * ratio).clamp(plot < 2.0 ? plot : 2.0, plot),
              decoration: BoxDecoration(
                color: pending || missing ? OnCareColors.lineSubtle : color,
                borderRadius: const BorderRadius.vertical(top: OnCareRadius.sm),
              ),
            ),
          ],
        );
      },
    );
  }
}

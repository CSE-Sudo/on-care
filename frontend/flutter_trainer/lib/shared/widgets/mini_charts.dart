import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/chart_semantics.dart';
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
            AppLocalizations.of(context),
            labels[i],
            '${values[i]}$valueSuffix',
          ),
    ];

    return Semantics(
      container: true,
      label: chartSemanticsLabel(
        AppLocalizations.of(context),
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
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
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
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: highlightIndex == i
                            ? FontWeight.w800
                            : FontWeight.w500,
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

/// 값 하나를 한 줄짜리 가로 막대로 — 목록 행처럼 세로 자리가 없는 곳에서 쓴다.
///
/// 숫자만 적혀 있으면 목록을 훑으며 누가 처지는지 견주려고 다섯 개를 눈으로
/// 비교해야 한다. 길이가 있으면 훑는 것만으로 드러난다(#899).
///
/// 값이 없으면([fraction] 이 null) 막대를 그리지 않는다 — 빈 트랙에 0 을
/// 채우면 `기록 없음` 이 `0% 수행` 으로 읽힌다.
///
/// 값이 있는 줄은 **언제나 남색**이다(#913). 기준 미달을 빨강으로 칠하던
/// 분기가 있었는데, 이 앱에서 빨강은 `목표 초과` 라는 다른 뜻으로 이미
/// 쓰이고 있었다(#690). 낮다는 사실은 막대 길이와 값이 말한다.
class InlineBarValue extends StatelessWidget {
  /// Creates an inline bar with [text] to its right.
  const InlineBarValue({
    super.key,
    required this.fraction,
    required this.text,
    this.label,
    this.labelWidth = 56,
    this.valueWidth = 40,
  });

  /// 막대가 무엇을 재는 값인지. 자리가 좁아 [labelWidth] 안에서 줄여 그린다 —
  /// 말줄임하면 정작 무슨 값인지가 사라진다.
  final String? label;

  /// 라벨 칸 너비.
  final double labelWidth;

  /// 막대 길이(0~1). 값이 없으면 null.
  final double? fraction;

  /// 막대 오른쪽에 찍을 값. 값이 없으면 부르는 쪽이 안내 문구를 준다.
  final String text;

  /// 값 칸 너비. 단위가 붙으면 넓혀 준다.
  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    // 값이 없는 줄은 **줄 전체가 흐려진다.** 값 칸만 흐리면 라벨은 또렷한
    // 채로 남아, 잴 값이 있는데 못 읽은 것처럼 보인다. 흐린 줄은 누를 것도
    // 읽을 것도 없다는 뜻이다.
    final bool empty = fraction == null;
    final Color tone = empty ? OnCareColors.lineStrong : OnCareBrand.trainer.primary;
    return Row(
      children: <Widget>[
        if (label != null) ...<Widget>[
          SizedBox(
            width: labelWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label!,
                maxLines: 1,
                style: TextStyle(
                  color: empty
                      ? OnCareColors.textDisabled
                      : OnCareColors.textTertiary,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
        ],
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.all(OnCareRadius.pill),
            child: Stack(
              children: <Widget>[
                Container(height: 6, color: OnCareColors.surfaceInput),
                FractionallySizedBox(
                  widthFactor: (fraction ?? 0).clamp(0.0, 1.0),
                  child: Container(height: 6, color: tone),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: OnCareSpacing.s8),
        SizedBox(
          width: valueWidth,
          // `데이터 부족` 처럼 값 대신 들어가는 안내는 숫자보다 길다. 잘라내면
          // 무슨 말인지 사라지므로 칸 안에서 줄여 그린다.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              text,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                // 값이 없으면 굵기까지 낮춘다 — 흐린 색만으로는 여전히
                // 읽을 값처럼 보인다.
                fontWeight: empty ? FontWeight.w600 : FontWeight.w800,
                color: empty ? OnCareColors.textDisabled : tone,
              ),
            ),
          ),
        ),
      ],
    );
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: OnCareColors.textSecondary,
                    ),
                  ),
                ),
              ),
            Container(
              height: (plot * ratio).clamp(2.0, plot),
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

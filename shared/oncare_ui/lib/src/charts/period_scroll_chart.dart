import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/charts/chart_basics.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';

/// `전체` 그래프의 선택·보이는 구간 상태(#1018). 두 앱 공용.
class PeriodChartSelection extends ChangeNotifier {
  int? _selected;
  (int, int)? _visible;

  int? get selected => _selected;
  (int, int)? get visible => _visible;

  void select(int? index) {
    if (_selected == index) return;
    _selected = index;
    notifyListeners();
  }

  void setVisible(int first, int last) {
    if (_visible != null && _visible!.$1 == first && _visible!.$2 == last) {
      return;
    }
    _visible = (first, last);
    notifyListeners();
  }

  /// 고른 날을 푼다.
  ///
  /// [includeVisible] 을 주면 보이는 구간까지 함께 비운다 — 그리는 배열이 통째로
  /// 바뀔 때(식단 탭의 기간 토글, #1984) 앞 기간의 구간이 남아 있으면 [averageOf]
  /// 가 새 배열과 무관한 창으로 평균을 낸다. 비운 구간은 그래프가 자리를 잡으며
  /// [setVisible] 로 다시 알려 준다.
  void reset({bool includeVisible = false}) {
    final bool clearsVisible = includeVisible && _visible != null;
    if (_selected == null && !clearsVisible) return;
    _selected = null;
    if (clearsVisible) _visible = null;
    notifyListeners();
  }

  /// 보이는 구간의 평균. 기록이 없는 날(0)은 뺀다.
  double averageOf(List<double> values) {
    if (values.isEmpty) return 0;
    final (int first, int last) = _visible ?? (0, values.length - 1);
    double sum = 0;
    int count = 0;
    for (int i = first; i <= last && i < values.length; i++) {
      if (values[i] > 0) {
        sum += values[i];
        count += 1;
      }
    }
    return count == 0 ? 0 : sum / count;
  }
}

const double _axisLabelWidth = 52;
const double _axisLabelRowHeight = 16;

/// `전체` 기간 그래프 뼈대 — 가로 스크롤 + 날짜 선택(#1018). 두 앱의 복사본을 합쳤다.
///
/// 막대는 [barBuilder] 가 그리고 여기서는 자리·선택·목표선·축 라벨만 맡는다.
/// 등장 애니메이션은 처음 한 번과 [revealKey] 변경 때만 돈다(#1697).
class PeriodScrollChart extends StatefulWidget {
  const PeriodScrollChart({
    super.key,
    required this.count,
    required this.height,
    required this.barBuilder,
    required this.labelBuilder,
    required this.onVisibleRangeChanged,
    this.selectedIndex,
    this.onSelected,
    this.goalBottom,
    this.goalLabel,
    this.topGap = 0,
    this.revealKey,
    this.daysPerScreen = 30,
    this.background,
    this.boldSelectedLabel = false,
  });

  final int count;
  final double height;
  final Widget Function(BuildContext context, int i) barBuilder;
  final String Function(int i) labelBuilder;
  final void Function(int first, int last) onVisibleRangeChanged;
  final int? selectedIndex;
  final void Function(int? i)? onSelected;
  final double? goalBottom;
  final String? goalLabel;
  final double topGap;
  final Object? revealKey;
  final int daysPerScreen;

  /// 막대 뒤에 까는 눈금선·달 경계.
  final CustomPainter? background;

  /// 고른 칸의 축 라벨을 진하게 적을지(한 칸이 한 주인 그래프).
  final bool boldSelectedLabel;

  @override
  State<PeriodScrollChart> createState() => _PeriodScrollChartState();
}

class _PeriodScrollChartState extends State<PeriodScrollChart> {
  final ScrollController _controller = ScrollController();
  double _slot = 0;
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportVisible);
  }

  @override
  void dispose() {
    _controller.removeListener(_reportVisible);
    _controller.dispose();
    super.dispose();
  }

  void _reportVisible() {
    if (_slot <= 0 || _viewport <= 0) return;
    final double offset = _controller.hasClients ? _controller.offset : 0;
    final int first = (offset / _slot).floor().clamp(0, widget.count - 1);
    final int last = ((offset + _viewport) / _slot).ceil() - 1;
    widget.onVisibleRangeChanged(first, last.clamp(first, widget.count - 1));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) return SizedBox(height: widget.height);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ChartGoalAxis(
          height: widget.height,
          label: widget.goalLabel,
          lineBottom: widget.goalBottom,
        ),
        const SizedBox(width: chartGoalAxisGap),
        Expanded(child: _scroller(context)),
      ],
    );
  }

  Widget _scroller(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewport = constraints.maxWidth;
        final double slot = viewport / widget.daysPerScreen;
        final double contentWidth = math.max(slot * widget.count, viewport);
        final bool changed = slot != _slot || viewport != _viewport;
        _slot = slot;
        _viewport = viewport;
        if (changed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_controller.hasClients) return;
            _controller.jumpTo(_controller.position.maxScrollExtent);
            _reportVisible();
          });
        }
        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: widget.count <= widget.daysPerScreen
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          child: SizedBox(
            width: contentWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  height: widget.height + widget.topGap,
                  child: Stack(
                    children: <Widget>[
                      if (widget.background != null)
                        Positioned.fill(
                          top: widget.topGap,
                          child: CustomPaint(painter: widget.background),
                        ),
                      if (widget.goalBottom != null)
                        GoalLineOverlay(bottom: widget.goalBottom!),
                      if (widget.selectedIndex != null)
                        Positioned(
                          left: slot * widget.selectedIndex! + slot / 2 - 0.5,
                          top: 0,
                          child: Container(
                            height: widget.height + widget.topGap,
                            width: 1,
                            color: OnCareColors.chartGoalLine,
                          ),
                        ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: EdgeInsets.only(top: widget.topGap),
                          child: ChartReveal(
                            replayKey: widget.revealKey ?? widget.count,
                            builder: (BuildContext context, double t) => Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                for (int i = 0; i < widget.count; i++)
                                  SizedBox(
                                    width: slot,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => widget.onSelected?.call(
                                        widget.selectedIndex == i ? null : i,
                                      ),
                                      child: ClipRect(
                                        key: ValueKey<String>(
                                          'period-bar-reveal-$i',
                                        ),
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          heightFactor: t,
                                          child: widget.barBuilder(context, i),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                SizedBox(
                  height: _axisLabelRowHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      for (int i = 0; i < widget.count; i++)
                        if (widget.labelBuilder(i).isNotEmpty)
                          Positioned(
                            left: (slot * i + slot / 2 - _axisLabelWidth / 2)
                                .clamp(
                                  0.0,
                                  math.max(contentWidth - _axisLabelWidth, 0.0),
                                ),
                            width: _axisLabelWidth,
                            child: Text(
                              widget.labelBuilder(i),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              textAlign: TextAlign.center,
                              style: chartAxisLabelStyle(
                                context,
                                selected:
                                    widget.boldSelectedLabel &&
                                    widget.selectedIndex == i,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 머리 값 — 평소에는 보이는 구간 평균, 날을 고르면 그날 값(회색 상자).
class PeriodChartHeadline extends StatelessWidget {
  const PeriodChartHeadline({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s12,
        vertical: OnCareSpacing.s8,
      ),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceInput,
        borderRadius: OnCareRadius.mdAll,
      ),
      child: child,
    );
  }
}

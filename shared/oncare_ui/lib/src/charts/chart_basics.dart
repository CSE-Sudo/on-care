import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/motion.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 차트 등장 진행값 빌더.
typedef ChartRevealBuilder = Widget Function(BuildContext context, double t);

/// 차트 등장 애니메이션(#1697) — 두 앱이 같은 규칙이다.
///
/// 처음 나타날 때 한 번만 [OnCareMotion.chartDraw] 로 그리고, [replayKey] 가
/// 바뀔 때(기간·지표 전환)만 다시 그린다. 막대를 고를 때 바뀌는 값은 넣지 않는다.
/// 줄인 움직임 설정이면 바로 완성 상태로 그린다.
class ChartReveal extends StatelessWidget {
  const ChartReveal({
    super.key,
    required this.builder,
    this.duration = OnCareMotion.chartDraw,
    this.curve = OnCareMotion.curve,
    this.replayKey,
  });

  final ChartRevealBuilder builder;
  final Duration duration;
  final Curve curve;
  final Object? replayKey;

  Object? get _stableReplayKey {
    final Object? k = replayKey;
    if (k is double && !k.isFinite) return '_nonFinite';
    return k;
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return builder(context, 1);
    }
    final Object? key = _stableReplayKey;
    return TweenAnimationBuilder<double>(
      key: key == null ? null : ValueKey<Object>(key),
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (BuildContext context, double t, Widget? _) =>
          builder(context, t),
    );
  }
}

/// 막대 차트 시차 — [t] 를 칸별 구간으로 나눈다.
double chartStagger(
  double t,
  int index,
  int count, {
  double spread = OnCareMotion.barStagger,
  Curve curve = OnCareMotion.curve,
}) {
  final double clamped = t.clamp(0.0, 1.0);
  final double span = 1 - spread;
  if (count <= 1 || spread <= 0 || span <= 0) {
    return curve.transform(clamped).clamp(0.0, 1.0);
  }
  final double start = (spread / (count - 1)) * index;
  final double local = ((clamped - start) / span).clamp(0.0, 1.0);
  return curve.transform(local).clamp(0.0, 1.0);
}

/// 그래프 목표선 — 1px 파선 4/3, 중립 회색. 가로선은 이것 하나뿐이다(#1015).
class ChartGoalLine {
  ChartGoalLine._();

  static const Color color = OnCareColors.chartGoalLine;
  static const double strokeWidth = 1;
  static const double dashWidth = 4;
  static const double dashGap = 3;

  static void paint(
    Canvas canvas, {
    required double y,
    required double left,
    required double right,
  }) {
    final Paint dash = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    for (double x = left; x < right; x += dashWidth + dashGap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dashWidth, right), y),
        dash,
      );
    }
  }
}

/// Stack 위에 얹는 목표선. [bottom] 은 그래프 바닥에서 선까지의 거리다.
class GoalLineOverlay extends StatelessWidget {
  const GoalLineOverlay({super.key, required this.bottom, this.visible = true});

  final double bottom;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: const IgnorePointer(
        child: CustomPaint(
          painter: _GoalLinePainter(),
          child: SizedBox(height: 0, width: double.infinity),
        ),
      ),
    );
  }
}

class _GoalLinePainter extends CustomPainter {
  const _GoalLinePainter();

  @override
  void paint(Canvas canvas, Size size) =>
      ChartGoalLine.paint(canvas, y: 0, left: 0, right: size.width);

  @override
  bool shouldRepaint(_GoalLinePainter old) => false;
}

/// 목표치 칸 폭(글자 배율 1 기준)과 그래프 사이 간격.
const double chartGoalAxisWidth = 40;
const double chartGoalAxisGap = OnCareSpacing.s8;

/// 목표치 라벨을 집는 키.
const Key chartGoalLabelKey = ValueKey<String>('chart-goal-label');

/// 그래프 왼쪽 목표치 칸 — 모든 그래프가 이 칸 하나로 목표치를 적는다(#1071).
class ChartGoalAxis extends StatelessWidget {
  const ChartGoalAxis({
    super.key,
    required this.height,
    this.label,
    this.lineBottom,
  });

  final double height;

  /// 두 줄 라벨(`목표` / 목표치). null 이면 칸만 지킨다.
  final String? label;
  final double? lineBottom;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = chartAxisLabelStyle(context);
    final TextScaler ts = MediaQuery.textScalerOf(context);
    final double width = chartGoalAxisWidth * ts.scale(1);
    final double labelHeight =
        ts.scale(style.fontSize!) * (style.height ?? 1.4) * 2;
    final double? bottom = lineBottom;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: <Widget>[
          if (label != null && bottom != null)
            Positioned(
              right: 0,
              top: (height - bottom - labelHeight / 2).clamp(
                0.0,
                math.max(0, height - labelHeight),
              ),
              child: SizedBox(
                key: chartGoalLabelKey,
                height: labelHeight,
                child: Center(
                  child: Text(
                    label!,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    style: style,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 축·요일 라벨 — `caption` 600, 힌트 색.
TextStyle chartAxisLabelStyle(BuildContext context, {bool selected = false}) =>
    context.oncare
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(
          color: selected
              ? OnCareColors.textPrimary
              : OnCareColors.textTertiary,
        );

/// 차트 툴팁 — 흰 카드 + 진한 테두리 + 떠 있는 그림자, 반경 12.
class AppChartTooltip extends StatelessWidget {
  const AppChartTooltip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s12,
        vertical: OnCareSpacing.s8,
      ),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.fromBorderSide(
          BorderSide(color: OnCareColors.lineStrong),
        ),
        boxShadow: OnCareShadows.overlay,
      ),
      child: DefaultTextStyle.merge(
        style: context.oncare
            .text(OnCareTypography.strong(OnCareTypography.bodySmall))
            .copyWith(color: OnCareColors.textPrimary),
        child: child,
      ),
    );
  }
}

/// 범례 견본 — 8×8, 반경 2.
class AppChartSwatch extends StatelessWidget {
  const AppChartSwatch({super.key, required this.color});

  final Color color;

  static const double size = 8;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.all(Radius.circular(2)),
    ),
  );
}

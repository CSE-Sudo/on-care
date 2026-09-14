import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 막대 하나에 쌓는 조각(칼로리의 탄·단·지).
typedef BarSegment = ({double value, Color color});

/// 막대 위에 꺾은선을 겹친 그래프 — 리포트 탭의 **모든** 막대가 이 그림이다.
///
/// 막대는 "그 칸이 얼마나 되나", 꺾은선은 "칸에서 칸으로 어떻게 움직였나" 를
/// 말한다. 주간 이행률·주 대비 비교가 같은 위젯을 쓰므로, 한 화면 안에서 막대
/// 모양·값 위치·선 굵기가 갈리지 않는다(#1177).
///
/// 두 그림이 **같은 좌표**를 쓴다. 선을 따로 그린 그래프를 아래에 붙이면
/// 눈금이 갈라져 같은 값이 두 높이로 보인다.
///
/// 막대 뒤에 빈 트랙을 깔지 않는다. 회색 기둥이 막대 위로 이어지면 `아직 못
/// 채운 몫` 처럼 읽혀, 눈금 끝이 목표가 아닌 그래프(소모 칼로리처럼 목표가 없는
/// 값)에서도 모자란 것처럼 보였다. 값이 없는 칸은 [emptyLabel] 이 말한다.
class BarLineChart extends StatelessWidget {
  /// Creates the chart.
  const BarLineChart({
    super.key,
    required this.values,
    required this.labels,
    required this.ceiling,
    required this.format,
    required this.semanticsLabel,
    this.emptyLabel,
    this.pendingFrom,
    this.segments,
    this.goal,
    this.barColor,
    this.lineColor,
    this.height = 118,
    this.maxBarWidth = 30,
    this.highlightIndex,
  }) : assert(values.length == labels.length, 'values/labels 길이가 달라요');

  /// 칸별 값. null 은 **기록이 없다**는 뜻이다 — 0 과 다르다.
  final List<double?> values;

  /// 칸 라벨(요일 또는 주).
  final List<String> labels;

  /// 눈금 끝. 0 이하면 1 로 본다.
  final double ceiling;

  /// 값을 단위까지 붙여 적는 방법.
  final String Function(double) format;

  /// `CustomPaint` 는 시맨틱 트리에 아무것도 남기지 않는다 — 이 문장이 없으면
  /// 그래프가 음성 안내에서 통째로 사라진다.
  final String semanticsLabel;

  /// 값이 없는 칸에 적을 말. null 이면 빈 트랙만 둔다.
  final String? emptyLabel;

  /// 아직 오지 않은 첫 칸. 그 뒤는 빈 트랙만 두고 아무 말도 적지 않는다 —
  /// 오지 않은 날은 "기록이 없다" 와 다르다.
  final int? pendingFrom;

  /// 칸별 누적 조각. 준 칸은 조각 색으로 쌓고, 안 준 칸은 한 색으로 채운다.
  final List<List<BarSegment>?>? segments;

  /// 넘으면 막대가 빨강이 되는 값. 없으면 늘 [barColor] 다.
  final double? goal;

  /// 목표 이내 막대의 색. 기본은 브랜드 색(목표 안쪽 색)이다. 보고 있는 지표가
  /// 색을 갖는 그래프(운동 유형별 비교 등)만 자기 색을 준다 — 지표를 바꿔도
  /// 그림이 그대로면 지금 무엇을 보고 있는지 색으로 알 수 없다(#1424).
  final Color? barColor;

  /// 꺾은선·점의 색. 기본은 브랜드의 진한 색. 막대에 지표 색을 줄 때는
  /// 같은 계열의 진한 색을 함께 줘 한 그림이 한 지표를 말하게 한다.
  final Color? lineColor;

  /// 막대 영역 높이(값 라벨·칸 라벨 제외).
  final double height;

  /// 막대 최대 폭. 칸이 적은 그래프에서 막대가 통짜 블록처럼 보이지 않게 한다.
  final double maxBarWidth;

  /// 굵게 적을 칸(보고 있는 주).
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // `TextPainter` 는 위젯 트리 밖이라 테마·글자 배율을 물려받지 않는다.
    // 여기서 역할 글자를 풀어 넘겨야 같은 카드 안에서 서체·크기가 갈리지 않는다.
    final TextStyle axis = chartAxisLabelStyle(context);
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height + _BarLinePainter.topPad + _BarLinePainter.labelHeight,
          child: CustomPaint(
            painter: _BarLinePainter(
              values: values,
              labels: labels,
              ceiling: ceiling <= 0 ? 1 : ceiling,
              format: format,
              emptyLabel: emptyLabel,
              pendingFrom: pendingFrom ?? values.length,
              segments: segments,
              goal: goal,
              barColor: barColor ?? tokens.brand.statusWithinGoal,
              lineColor: lineColor ?? tokens.brand.strong,
              maxBarWidth: maxBarWidth,
              highlightIndex: highlightIndex,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              valueStyle: OnCareTypography.numeric(
                tokens.text(OnCareTypography.strong(OnCareTypography.caption)),
              ).copyWith(color: OnCareColors.textPrimary),
              emptyStyle: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textDisabled),
              axisStyle: axis,
              axisHighlightStyle: chartAxisLabelStyle(
                context,
                selected: true,
              ).copyWith(color: tokens.brand.primary),
              axisPendingStyle: axis.copyWith(color: OnCareColors.textDisabled),
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _BarLinePainter extends CustomPainter {
  _BarLinePainter({
    required this.values,
    required this.labels,
    required this.ceiling,
    required this.format,
    required this.emptyLabel,
    required this.pendingFrom,
    required this.segments,
    required this.goal,
    required this.barColor,
    required this.lineColor,
    required this.maxBarWidth,
    required this.highlightIndex,
    required this.textDirection,
    required this.textScaler,
    required this.valueStyle,
    required this.emptyStyle,
    required this.axisStyle,
    required this.axisHighlightStyle,
    required this.axisPendingStyle,
  });

  final List<double?> values;
  final List<String> labels;
  final double ceiling;
  final String Function(double) format;
  final String? emptyLabel;
  final int pendingFrom;
  final List<List<BarSegment>?>? segments;
  final double? goal;
  final Color barColor;
  final Color lineColor;
  final double maxBarWidth;
  final int? highlightIndex;
  final TextDirection textDirection;
  final TextScaler textScaler;

  /// 점 위 값 라벨. 목표를 넘긴 칸만 빨강으로 바꿔 쓴다.
  final TextStyle valueStyle;

  /// 값이 없는 칸의 말.
  final TextStyle emptyStyle;

  /// 칸 라벨 — 평소 / 보고 있는 칸 / 아직 오지 않은 칸.
  final TextStyle axisStyle;
  final TextStyle axisHighlightStyle;
  final TextStyle axisPendingStyle;

  /// 값 라벨이 들어갈 위쪽 여백. 꽉 찬 막대의 숫자가 카드 제목에 닿지 않는다.
  static const double topPad = OnCareSpacing.s20;

  /// 칸 라벨 줄 — `caption` 한 줄(12 × 1.4)과 막대와의 틈이 들어가는 높이.
  static const double labelHeight = 22;

  // 리포트 탭 막대 그래프들이 같은 값을 쓴다 — 그래프마다 선 굵기·점 크기가
  // 다르면 같은 화면에서 다른 종류의 그림처럼 읽힌다(#1177).

  /// 꺾은선·점 테두리 굵기.
  static const double lineWidth = 2;

  /// 꺾은선 점 반지름.
  static const double pointRadius = 4;

  /// 0 인 막대도 남기는 높이 — '기록했고 아무것도 못 했다' 와 '기록 없음' 은
  /// 다른 말이다.
  static const double zeroStub = 2;

  /// 칸 폭 대비 막대 폭.
  static const double barWidthFactor = 0.46;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final double plotHeight = size.height - topPad - labelHeight;
    if (plotHeight <= 0) return;
    final double baseline = topPad + plotHeight;
    final double slot = size.width / values.length;
    final double barWidth = slot * barWidthFactor > maxBarWidth
        ? maxBarWidth
        : slot * barWidthFactor;

    double centerOf(int i) => slot * (i + 0.5);
    double topOf(double v) =>
        baseline - plotHeight * (v / ceiling).clamp(0.0, 1.0);
    bool drawn(int i) => i < pendingFrom && values[i] != null;
    bool over(double v) => goal != null && v > goal!;

    for (var i = 0; i < values.length; i++) {
      if (!drawn(i)) continue;
      final double value = values[i]!;
      final double top = topOf(value);
      final Rect rect = Rect.fromLTRB(
        centerOf(i) - barWidth / 2,
        top > baseline - zeroStub ? baseline - zeroStub : top,
        centerOf(i) + barWidth / 2,
        baseline,
      );
      final RRect bar = RRect.fromRectAndRadius(rect, OnCareRadius.xs);
      final List<BarSegment>? stack = segments != null && i < segments!.length
          ? segments![i]
          : null;
      final double stackTotal =
          stack?.fold<double>(0, (sum, s) => sum + s.value) ?? 0;
      if (stack != null && stackTotal > 0) {
        // 조각은 막대 안에서만 그린다 — 둥근 모서리 밖으로 새면 막대가 아니라
        // 색 띠 셋으로 보인다.
        canvas.save();
        canvas.clipRRect(bar);
        var y = rect.bottom;
        for (final segment in stack) {
          final double h = rect.height * (segment.value / stackTotal);
          canvas.drawRect(
            Rect.fromLTRB(rect.left, y - h, rect.right, y),
            Paint()..color = segment.color,
          );
          y -= h;
        }
        canvas.restore();
      } else {
        // 한 색으로 칠한다. 위아래로 옅어지는 그러데이션은 막대마다 밝기가
        // 달라 보여, 나란히 놓은 두 주의 높이를 견주기 전에 색부터 비교하게
        // 만들었다. 색을 나누는 것은 조각을 일부러 쌓을 때뿐이다(#1177).
        canvas.drawRRect(
          bar,
          Paint()..color = over(value) ? OnCareColors.danger : barColor,
        );
      }
    }

    // 꺾은선은 값이 있는 칸만 잇는다. 빈 칸을 가로질러 이으면 그 사이에 값이
    // 있었던 것처럼 보인다.
    final List<Offset> run = <Offset>[];
    void flush() {
      if (run.length > 1) {
        final Path path = Path()..moveTo(run.first.dx, run.first.dy);
        for (final point in run.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = lineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = lineWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      run.clear();
    }

    for (var i = 0; i < values.length; i++) {
      if (!drawn(i)) {
        flush();
        continue;
      }
      run.add(Offset(centerOf(i), topOf(values[i]!)));
    }
    flush();

    for (var i = 0; i < values.length; i++) {
      if (!drawn(i)) continue;
      final Offset point = Offset(centerOf(i), topOf(values[i]!));
      canvas.drawCircle(
        point,
        pointRadius,
        Paint()..color = OnCareColors.surfaceCard,
      );
      canvas.drawCircle(
        point,
        pointRadius,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineWidth,
      );
      _text(
        canvas,
        format(values[i]!),
        Offset(point.dx, point.dy - OnCareSpacing.s8),
        over(values[i]!)
            ? valueStyle.copyWith(color: OnCareColors.danger)
            : valueStyle,
        anchorBottom: true,
        maxWidth: slot,
      );
    }

    if (emptyLabel != null) {
      for (var i = 0; i < values.length; i++) {
        if (drawn(i) || i >= pendingFrom) continue;
        _text(
          canvas,
          emptyLabel!,
          Offset(centerOf(i), baseline - OnCareSpacing.s4),
          emptyStyle,
          anchorBottom: true,
          maxWidth: slot,
        );
      }
    }

    for (var i = 0; i < labels.length; i++) {
      _text(
        canvas,
        labels[i],
        Offset(centerOf(i), baseline + OnCareSpacing.s4),
        i >= pendingFrom
            ? axisPendingStyle
            : highlightIndex == i
            ? axisHighlightStyle
            : axisStyle,
        maxWidth: slot,
      );
    }
  }

  /// 가운데 정렬로 한 줄 적는다. [anchorBottom] 이면 [at] 이 글자의 **아래**다.
  void _text(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    bool anchorBottom = false,
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    painter.paint(
      canvas,
      Offset(
        at.dx - painter.width / 2,
        anchorBottom ? at.dy - painter.height : at.dy,
      ),
    );
  }

  @override
  bool shouldRepaint(_BarLinePainter old) =>
      !_sameValues(old.values, values) ||
      old.ceiling != ceiling ||
      old.pendingFrom != pendingFrom ||
      old.goal != goal ||
      old.barColor != barColor ||
      old.lineColor != lineColor ||
      old.emptyLabel != emptyLabel ||
      old.highlightIndex != highlightIndex ||
      old.maxBarWidth != maxBarWidth ||
      old.labels.join() != labels.join() ||
      old.segments != segments ||
      old.textScaler != textScaler ||
      old.valueStyle != valueStyle ||
      old.emptyStyle != emptyStyle ||
      old.axisStyle != axisStyle ||
      old.axisHighlightStyle != axisHighlightStyle ||
      old.axisPendingStyle != axisPendingStyle;

  static bool _sameValues(List<double?> a, List<double?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

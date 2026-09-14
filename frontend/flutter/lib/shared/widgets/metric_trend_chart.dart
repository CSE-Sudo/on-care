/// 지표 하나의 주간 추이 꺾은선 — 홈 탭과 식단 탭이 **같은 그림**을 쓴다.
///
/// 원래 홈 탭(`dashboard_content.dart`) 안에만 있던 차트다. 식단 탭의 주간
/// 그래프가 막대라 같은 값을 두 가지 모양으로 보여 주고 있었다. 복사하면 한쪽만
/// 고쳐져 갈라지므로 여기로 옮기고 양쪽이 이것을 부른다.
///
/// 그리는 규칙은 옮기기 전과 같다.
///
///  * 선은 **오늘까지만** 잇는다 — 아직 오지 않은 요일의 0 이 급락처럼 보이지
///    않도록. x 좌표는 7칸 기준 그대로라 주끼리 정렬된다.
///  * 점 색은 그날이 목표를 넘겼는지만 말한다(초과=빨강, 그 외=브랜드). 지표
///    카드의 뱃지와 같은 두 색이라 한 카드 안에서 서로 다른 이야기를 하지 않는다.
///  * 목표선은 [ChartGoalLine] 하나다.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이번 주 꺾은선의 색. 값의 상태는 점으로 말하므로 선은 눈에 띄지 않게 둔다.
const Color kMetricTrendLine = OnCareColors.lineStrong;

/// 목표 대비 상태색: 초과(빨강) / 그 외(브랜드 파랑).
///
/// 그 외를 초록으로 칠하지 않는다 — 초록은 "정상"으로 읽히는데, 목표에 한참
/// 못 미친 값도 초과는 아니기 때문이다(#1070).
///
/// 목표가 0 이면 초과로 보지 않는다. `v > goal` 만 두면 목표가 없는 지표의 **모든**
/// 기록이 빨간 점이 되어, 같은 카드의 평균 뱃지(목표가 있을 때만 초과 판정)와 서로
/// 다른 이야기를 한다.
Color metricStatusColor(double v, double goal) => goal > 0 && v > goal
    ? OnCareColors.danger
    : OnCareBrand.member.statusWithinGoal;

/// 월→일 요일 라벨. 홈 탭과 식단 탭이 **같은 문구**를 쓰도록 여기 둔다 — 한쪽만
/// 하드코딩하면 영어 로케일에서 한글 요일이 그대로 남는다.
List<String> weekDayLabels(AppLocalizations l) => <String>[
  l.dietWeekdayMon,
  l.dietWeekdayTue,
  l.dietWeekdayWed,
  l.dietWeekdayThu,
  l.dietWeekdayFri,
  l.dietWeekdaySat,
  l.dietWeekdaySun,
];

/// 소수 첫째 자리까지만 남기고 정수는 콤마만. 당류 17.8 이 18 로 반올림돼
/// 지표 카드·식단 탭 수치와 어긋나지 않도록.
String metricTrendNumber(num v) => v == v.roundToDouble()
    ? NumberFormat('#,###').format(v)
    : NumberFormat('#,##0.#').format(v);

/// 데이터와 눈금을 모두 담는 스케일. **0 을 바닥으로 두지 않는다** — 두면
/// 하루하루 차이가 거의 평평한 선으로 뭉개진다.
(double, double) metricTrendScale({
  required List<double> values,
  required List<double> ticks,
  required double goal,
}) {
  final List<double> all = <double>[...values, ...ticks, goal];
  double lo = all.reduce(math.min);
  double hi = all.reduce(math.max);
  final double range = (hi - lo) == 0 ? 1 : (hi - lo);
  hi += range * 0.10;
  lo -= range * 0.08;
  // 당류처럼 0이 최소 눈금인 지표는 바닥을 0에 고정.
  if (ticks.isNotEmpty && ticks.first <= 0 && lo < 0) lo = 0;
  return (lo, hi);
}

/// 그래프 기본 높이. 차트 기하라 맞는 토큰이 없다.
const double _kDefaultChartHeight = 68;

/// 점을 누른 것으로 보는 가로 거리. 차트 기하라 맞는 토큰이 없다. (#1122)
const double _kPointHitSlop = 18;

/// 눈금 라벨 + 꺾은선 + 요일 라벨 한 덩어리.
class MetricTrendChart extends StatelessWidget {
  const MetricTrendChart({
    required this.values,
    required this.dayLabels,
    required this.goal,
    required this.ticks,
    required this.todayIndex,
    required this.replayKey,
    required this.semanticsLabel,
    this.goalLabel,
    required this.formatTick,
    this.height = _kDefaultChartHeight,
    this.selectedIndex,
    this.onSelected,
    super.key,
  });

  /// 요일별 값(월→일). [dayLabels] 와 길이가 같아야 한다.
  final List<double> values;
  final List<String> dayLabels;
  final double goal;

  /// 축의 위아래를 정하는 값들. 그리지는 않는다 — 지표별 축 성질을 잡는
  /// [metricTrendScale] 의 입력이다.
  final List<double> ticks;

  /// 선을 여기까지만 잇는다. 지난 주처럼 전부 지난 구간이면 마지막 index.
  final int todayIndex;

  /// 바뀌면 진입 애니메이션을 처음부터 다시 그린다.
  final Object replayKey;

  /// 그래프가 말하는 내용 한 문장. `CustomPaint` 는 시맨틱 트리에 아무 노드도
  /// 남기지 않아, 이게 없으면 그래프가 음성 안내에서 통째로 사라진다(#972).
  /// [chartSemanticsLabel] 로 만든다 — 지표 이름과 단위는 부르는 쪽만 안다.
  final String semanticsLabel;

  /// 목표선에 붙는 문구(예: `목표 2,000`). null 이면 선만 그린다. 문구를 밖에서
  /// 받는 것은 두 앱의 로케일 자원이 갈라져 있어서다.
  final String? goalLabel;

  final String Function(double) formatTick;
  final double height;

  /// 고른 점. [onSelected] 를 준 화면에서만 뜻이 있다 — 고른 점은 굵은 고리로
  /// 표시하고, 부르는 쪽은 머리 숫자를 그날 값으로 바꾼다. (#1122)
  final int? selectedIndex;

  /// 점을 누르면 그 index 로, 점에서 먼 곳을 누르면 null 로 부른다. null 이면
  /// 그래프는 예전처럼 만질 수 없는 그림이다.
  final ValueChanged<int?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final (double lo, double hi) = metricTrendScale(
      values: values,
      ticks: ticks,
      goal: goal,
    );
    final TextStyle axisStyle = chartAxisLabelStyle(context);
    final TextStyle valueStyle = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );
    // 눈금·요일 라벨은 낱개로 읽어 봐야 `월` `화` 뿐이라 그래프가 무슨 값을
    // 말하는지 알 수 없다. 한 덩어리로 묶고 요약 한 문장만 읽힌다.
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 목표치 칸 — 모든 그래프가 같은 칸을 쓴다. (#1071)
            ChartGoalAxis(
              height: height,
              label: goalLabel,
              lineBottom:
                  goalLabel != null && goal > 0 && goal >= lo && goal <= hi
                  ? ((goal - lo) / ((hi - lo) <= 0 ? 1 : (hi - lo))) * height
                  : null,
            ),
            const SizedBox(width: chartGoalAxisGap),
            Expanded(
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: height,
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints c) {
                        final Widget chart = ChartReveal(
                          replayKey: replayKey,
                          builder: (BuildContext context, double t) =>
                              CustomPaint(
                                size: Size.infinite,
                                painter: MetricTrendPainter(
                                  cur: values,
                                  goal: goal,
                                  ticks: ticks,
                                  lo: lo,
                                  hi: hi,
                                  todayIndex: todayIndex,
                                  progress: t,
                                  selectedIndex: selectedIndex,
                                  valueStyle: valueStyle,
                                ),
                              ),
                        );
                        final ValueChanged<int?>? onSelected = this.onSelected;
                        if (onSelected == null) return chart;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (TapUpDetails d) =>
                              onSelected(_hit(d.localPosition.dx, c.maxWidth)),
                          child: chart,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      // 폭이 모자라면(영어 요일 등) 라벨만 줄여 넘치지 않게 한다.
                      for (int i = 0; i < dayLabels.length; i++)
                        if (i == todayIndex)
                          // 오늘: 브랜드색 원 안에 흰 글씨.
                          Flexible(
                            child: Container(
                              width: OnCareSize.countBadgeMin,
                              height: OnCareSize.countBadgeMin,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: tokens.brand.primary,
                                shape: BoxShape.circle,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  dayLabels[i],
                                  maxLines: 1,
                                  style: axisStyle.copyWith(
                                    color: OnCareColors.textOnFill,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(dayLabels[i], style: axisStyle),
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 누른 x 좌표에서 가장 가까운 점의 index. 점에서 멀면 null 이라 선택이 풀린다
/// — 그래프 아무 데나 누르면 다시 평균으로 돌아온다. (#1122)
extension on MetricTrendChart {
  int? _hit(double dx, double width) {
    if (values.length < 2 || width <= 0) return null;
    final double step = width / (values.length - 1);
    final int i = (dx / step).round().clamp(0, values.length - 1);
    // 점에서 [_kPointHitSlop] 안쪽만 그 점을 누른 것으로 본다. 반 칸까지 넓히면
    // 그래프 어디를 눌러도 어느 점엔가 붙어, 선택을 풀 자리가 없어진다. (#1122)
    if ((dx - i * step).abs() > _kPointHitSlop) return null;
    // 아직 그리지 않은(오늘 이후) 점은 고를 수 없다 — 0 을 그날 값이라고
    // 말하게 된다.
    if (i > todayIndex.clamp(0, values.length - 1)) return null;
    // 고른 점을 다시 누르면 풀린다.
    return i == selectedIndex ? null : i;
  }
}

// --- 꺾은선 기하 — 차트 안의 선·점 크기라 맞는 토큰이 없다. ---
const double _kLineStroke = 1.6;
const double _kDotRadius = 4.2;
const double _kLastDotRadius = 5.0;

/// 점 둘레 흰 테두리 두께.
const double _kDotHalo = 1.3;

/// 고른 점을 두르는 고리 반지름과 두께. (#1122)
const double _kSelectedRingRadius = 8.5;
const double _kSelectedRingStroke = 2;

/// 값 라벨과 점 사이 거리.
const double _kValueLabelGap = 7;

/// 점이 선보다 먼저 페이드인을 시작하는 구간(선 한 칸 기준 비율).
const double _kDotFadeLead = 0.35;

/// 진입 애니메이션 진행도만큼 [color] 를 옅게 한다. 규격 색을 새로 만드는 것이
/// 아니라 등장 중인 점·라벨의 진행 상태라서 투명도 토큰 대신 진행값을 곱한다.
Color _fade(Color color, double progress) => Color.from(
  alpha: color.a * progress,
  red: color.r,
  green: color.g,
  blue: color.b,
  colorSpace: color.colorSpace,
);

/// 꺾은선 본체. 홈 탭에 있던 `_TrendChartPainter` 를 그대로 옮긴 것이다.
class MetricTrendPainter extends CustomPainter {
  MetricTrendPainter({
    required this.cur,
    required this.goal,
    required this.ticks,
    required this.lo,
    required this.hi,
    required this.todayIndex,
    this.progress = 1,
    this.selectedIndex,
    this.valueStyle,
  });

  final List<double> cur;
  final double goal;
  final List<double> ticks;
  final double lo;
  final double hi;

  /// 선을 여기까지만 그린다(미래 요일의 0값이 급락처럼 보이지 않도록).
  final int todayIndex;

  /// 0 → 1 진입 애니메이션 진행도. 선은 월요일부터 오늘 쪽으로 이어지고,
  /// 각 데이터 포인트와 값 라벨은 선이 도달하는 순간 나타난다.
  final double progress;

  /// 고른 점. 그 점만 고리를 둘러 어느 날을 보고 있는지 알린다. (#1122)
  final int? selectedIndex;

  /// 점 위 값 라벨 글자. 색은 점의 상태색으로 덮는다. null 이면 `caption` 600.
  final TextStyle? valueStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double span = (hi - lo) <= 0 ? 1 : (hi - lo);
    double dx(int i) => cur.length <= 1 ? w / 2 : (i / (cur.length - 1)) * w;
    double dy(double v) => h - ((v - lo) / span) * h;

    // 목표선 하나. 점선이라 데이터 꺾은선과 경쟁하지 않는다. 축 밖으로 나가는
    // 목표(범위를 벗어난 주)는 그리지 않는다 — 가장자리에 붙어 테두리처럼
    // 보인다.
    if (goal > 0 && goal >= lo && goal <= hi) {
      // 네 그래프가 같은 모양의 목표선을 쓴다 (#1015).
      ChartGoalLine.paint(canvas, y: dy(goal), left: 0, right: w);
    }

    final int lastIdx = todayIndex.clamp(0, cur.length - 1);
    final List<Offset> pts = <Offset>[
      for (int i = 0; i <= lastIdx; i++) Offset(dx(i), dy(cur[i])),
    ];

    final double p = progress.clamp(0.0, 1.0);
    final double drawn = lastIdx * p;
    if (lastIdx > 0) {
      final Path line = Path()..moveTo(pts.first.dx, pts.first.dy);
      final int whole = drawn.floor().clamp(0, lastIdx);
      for (int i = 1; i <= whole; i++) {
        line.lineTo(pts[i].dx, pts[i].dy);
      }
      if (whole < lastIdx) {
        final Offset tip = Offset.lerp(
          pts[whole],
          pts[whole + 1],
          drawn - whole,
        )!;
        line.lineTo(tip.dx, tip.dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = kMetricTrendLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kLineStroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    for (int i = 0; i <= lastIdx; i++) {
      // 선이 이 점에 닿기 직전부터 짧게 페이드인한다.
      final double a = lastIdx == 0
          ? p
          : ((drawn - i) / _kDotFadeLead + 1).clamp(0.0, 1.0);
      if (a <= 0) continue;
      final Color sc = metricStatusColor(cur[i], goal);
      if (i == selectedIndex) {
        canvas.drawCircle(
          pts[i],
          _kSelectedRingRadius,
          Paint()
            ..color = _fade(sc, OnCareAlpha.strong * a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _kSelectedRingStroke,
        );
      }
      _dot(
        canvas,
        pts[i],
        sc,
        r: i == cur.length - 1 ? _kLastDotRadius : _kDotRadius,
        alpha: a,
      );
      _text(canvas, metricTrendNumber(cur[i]), pts[i], w, sc, alpha: a);
    }
  }

  void _dot(
    Canvas c,
    Offset o,
    Color color, {
    required double r,
    double alpha = 1,
  }) {
    c.drawCircle(
      o,
      r + _kDotHalo,
      Paint()..color = _fade(OnCareColors.surfaceCard, alpha),
    );
    c.drawCircle(o, r, Paint()..color = _fade(color, alpha));
  }

  void _text(
    Canvas c,
    String s,
    Offset at,
    double w,
    Color color, {
    double alpha = 1,
  }) {
    final TextStyle base =
        valueStyle ?? OnCareTypography.strong(OnCareTypography.caption);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: base.copyWith(color: _fade(color, alpha)),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final double bx = (at.dx - tp.width / 2).clamp(0.0, w - tp.width);
    double by = at.dy - tp.height - _kValueLabelGap;
    if (by < 0) by = at.dy + _kValueLabelGap;
    tp.paint(c, Offset(bx, by));
  }

  @override
  bool shouldRepaint(covariant MetricTrendPainter old) =>
      old.cur != cur ||
      old.goal != goal ||
      old.ticks != ticks ||
      old.lo != lo ||
      old.hi != hi ||
      old.todayIndex != todayIndex ||
      old.progress != progress ||
      old.selectedIndex != selectedIndex ||
      old.valueStyle != valueStyle;
}

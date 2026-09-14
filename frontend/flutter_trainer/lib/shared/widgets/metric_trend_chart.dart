/// 지표 하나의 주간 추이 꺾은선 — 사용자 앱 홈 탭과 **같은 그림**이다.
///
/// 사용자 앱의 `shared/widgets/metric_trend_chart.dart` 를 트레이너 콘솔 토큰으로
/// 옮긴 것이다. 두 앱은 패키지가 갈라져 있어 코드를 공유할 수 없으므로, 규칙을
/// 여기에도 적어 둔다. 한쪽만 고치면 회원이 보는 그래프와 트레이너가 보는
/// 그래프가 다른 이야기를 한다.
///
///  * 선은 **오늘까지만** 잇는다 — 아직 오지 않은 요일의 0 이 급락처럼 보이지
///    않도록. x 좌표는 7칸 기준 그대로라 주끼리 정렬된다.
///  * 점 색은 그날이 목표를 넘겼는지만 말한다(초과=빨강, 그 외=초록).
///  * 목표선은 그리지 않는다. 눈금과 겹치면 선이 두꺼워 보였다.
///  * **진입 애니메이션이 없다.** 이 그래프는 식단 지표(칼로리·나트륨·당류)만
///    그리는데, 트레이너는 고객을 바꾸고 기간을 바꾸며 하루에도 여러 번 다시
///    읽는다. 그때마다 선이 처음부터 그려지면 값을 읽기까지 기다려야 했다.
///    (#1027 — #653 에서 넣었던 것을 되돌린다)
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:oncare_ui/oncare_ui.dart';

/// 이번 주 꺾은선의 색. 값의 상태는 점으로 말하므로 선은 눈에 띄지 않게 둔다.
const Color kMetricTrendLine = Color(0xFFDDE2E8);

/// 목표 대비 상태색: 초과(빨강) / 그 외(목표 안쪽).
///
/// 목표가 0 이면 초과로 보지 않는다 — 목표 없는 지표의 모든 기록이 빨간 점이
/// 되어 버린다.
///
/// 목표 안쪽은 [OnCareBrand.trainer.primary](= 트레이너 메인 색)이다. 회원 앱
/// 꺾은선이 자기 메인 색을 쓰는 자리와 같다 — 같은 날이 두 화면에서 같은
/// 뜻으로 찍힌다. 초록이었던 때에는 목표에 한참 못 미친 날까지 "정상" 이라고
/// 말했다. (#1168)
Color metricStatusColor(double v, double goal) =>
    goal > 0 && v > goal ? OnCareColors.danger : OnCareBrand.trainer.primary;

/// 소수 첫째 자리까지만 남기고 정수는 콤마만. 당류 17.8 이 18 로 반올림돼
/// 요약 수치와 어긋나지 않도록.
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
  final all = <double>[...values, ...ticks, goal];
  var lo = all.reduce(math.min);
  var hi = all.reduce(math.max);
  final range = (hi - lo) == 0 ? 1.0 : (hi - lo);
  hi += range * 0.10;
  lo -= range * 0.08;
  // 당류처럼 0이 최소 눈금인 지표는 바닥을 0에 고정.
  if (ticks.isNotEmpty && ticks.first <= 0 && lo < 0) lo = 0;
  return (lo, hi);
}

/// 눈금 라벨 + 꺾은선 + 요일 라벨 한 덩어리.
class MetricTrendChart extends StatelessWidget {
  /// Creates a weekly trend chart.
  const MetricTrendChart({
    super.key,
    required this.values,
    required this.dayLabels,
    required this.goal,
    required this.ticks,
    required this.todayIndex,
    required this.semanticsLabel,
    this.goalLabel,
    required this.formatTick,
    this.markToday = true,
    this.height = 68,
    this.selectedIndex,
    this.onSelected,
  });

  /// 요일별 값(월→일). [dayLabels] 와 길이가 같아야 한다.
  final List<double> values;

  /// 요일 라벨(월→일).
  final List<String> dayLabels;

  /// 하루 목표. 점 색만 정한다(목표선은 그리지 않는다).
  final double goal;

  /// 축의 위아래를 정하는 값들. 그리지는 않는다 — 지표별 축 성질을 잡는
  /// [metricTrendScale] 의 입력이다.
  final List<double> ticks;

  /// 선을 여기까지만 잇는다. 지난 주처럼 전부 지난 구간이면 마지막 index.
  final int todayIndex;

  /// [todayIndex] 요일에 '오늘' 표시(브랜드색 원)를 그릴지. 과거 주는 선이
  /// 일요일까지 이어지는데, 그 자리에 오늘 표시가 붙으면 지난 주 일요일이
  /// 오늘인 것처럼 읽힌다(#752).
  final bool markToday;

  /// 그래프가 말하는 내용 한 문장. `CustomPaint` 는 시맨틱 트리에 아무 노드도
  /// 남기지 않아, 이게 없으면 그래프가 음성 안내에서 통째로 사라진다(#972).
  /// `chartSemanticsLabel` 로 만든다 — 지표 이름과 단위는 부르는 쪽만 안다.
  final String semanticsLabel;

  /// 목표선 문구 포맷.
  /// 목표선에 붙는 문구(예: `목표 2,000`). null 이면 선만 그린다. 문구를 밖에서
  /// 받는 것은 두 앱의 로케일 자원이 갈라져 있어서다.
  final String? goalLabel;

  final String Function(double) formatTick;

  /// 꺾은선 영역 높이(요일 라벨 제외).
  final double height;

  /// 고른 점. [onSelected] 를 준 화면에서만 뜻이 있다 — 고른 점은 굵은 고리로
  /// 표시하고, 부르는 쪽은 머리 숫자를 그날 값으로 바꾼다. 회원 앱 #1122 와
  /// 같은 규칙이다.
  final int? selectedIndex;

  /// 점을 누르면 그 index 로, 점에서 먼 곳을 누르면 null 로 부른다. null 이면
  /// 그래프는 예전처럼 만질 수 없는 그림이다.
  final ValueChanged<int?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = metricTrendScale(values: values, ticks: ticks, goal: goal);
    // 눈금·요일 라벨은 낱개로 읽어 봐야 `월` `화` 뿐이라 그래프가 무슨 값을
    // 말하는지 알 수 없다. 한 덩어리로 묶고 요약 한 문장만 읽힌다.
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 목표선의 실제 높이에 맞춰 라벨 하나. 칸은 목표가 없어도 자리를
            // 지킨다 — 지표를 바꿀 때 그래프 폭이 흔들리지 않는다.
            // 목표치 칸 — 두 앱의 모든 그래프가 같은 칸을 쓴다. (#1071)
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
                        final Widget chart = _paint(lo, hi);
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
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      for (var i = 0; i < dayLabels.length; i++)
                        if (i == todayIndex && markToday)
                          // 오늘: 브랜드색 원 안에 흰 글씨.
                          Container(
                            width: 18,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: OnCareBrand.trainer.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              dayLabels[i],
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: OnCareColors.textOnFill,
                              ),
                            ),
                          )
                        else
                          Text(
                            dayLabels[i],
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: OnCareColors.textSecondary,
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

  Widget _paint(double lo, double hi) => CustomPaint(
    size: Size.infinite,
    painter: MetricTrendPainter(
      cur: values,
      goal: goal,
      ticks: ticks,
      lo: lo,
      hi: hi,
      todayIndex: todayIndex,
      selectedIndex: selectedIndex,
    ),
  );

  /// 누른 x 좌표에서 가장 가까운 점의 index. 점에서 멀면 null 이라 선택이
  /// 풀린다 — 그래프 아무 데나 누르면 다시 평균으로 돌아온다. (회원 앱 #1122)
  int? _hit(double dx, double width) {
    if (values.length < 2 || width <= 0) return null;
    final double step = width / (values.length - 1);
    final int i = (dx / step).round().clamp(0, values.length - 1);
    // 점에서 18px 안쪽만 그 점을 누른 것으로 본다. 반 칸까지 넓히면 그래프
    // 어디를 눌러도 어느 점엔가 붙어, 선택을 풀 자리가 없어진다.
    if ((dx - i * step).abs() > 18) return null;
    // 아직 그리지 않은(오늘 이후) 점은 고를 수 없다 — 0 을 그날 값이라고
    // 말하게 된다.
    if (i > todayIndex.clamp(0, values.length - 1)) return null;
    // 고른 점을 다시 누르면 풀린다.
    return i == selectedIndex ? null : i;
  }
}


/// 꺾은선 본체.
class MetricTrendPainter extends CustomPainter {
  /// Creates the line painter.
  MetricTrendPainter({
    required this.cur,
    required this.goal,
    required this.ticks,
    required this.lo,
    required this.hi,
    required this.todayIndex,
    this.selectedIndex,
  });

  /// 요일별 값(월→일).
  final List<double> cur;

  /// 하루 목표. 점 색만 정한다.
  final double goal;

  /// 축의 위아래를 정하는 값들. 그리지는 않는다.
  final List<double> ticks;

  /// 축 바닥.
  final double lo;

  /// 축 천장.
  final double hi;

  /// 선을 여기까지만 그린다(미래 요일의 0값이 급락처럼 보이지 않도록).
  final int todayIndex;

  /// 고른 점. 그 점만 고리를 둘러 어느 날을 보고 있는지 알린다. (회원 앱 #1122)
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (cur.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final span = (hi - lo) <= 0 ? 1.0 : (hi - lo);
    double dx(int i) => cur.length <= 1 ? w / 2 : (i / (cur.length - 1)) * w;
    double dy(double v) => h - ((v - lo) / span) * h;

    // 목표선 하나. 점선이라 데이터 꺾은선과 경쟁하지 않는다. 축 밖으로 나가는
    // 목표(범위를 벗어난 주)는 그리지 않는다 — 가장자리에 붙어 테두리처럼
    // 보인다.
    if (goal > 0 && goal >= lo && goal <= hi) {
      // 네 그래프가 같은 모양의 목표선을 쓴다 (#1015).
      ChartGoalLine.paint(canvas, y: dy(goal), left: 0, right: w);
    }

    final lastIdx = todayIndex.clamp(0, cur.length - 1);
    final pts = <Offset>[
      for (var i = 0; i <= lastIdx; i++) Offset(dx(i), dy(cur[i])),
    ];

    if (lastIdx > 0) {
      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i <= lastIdx; i++) {
        line.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = kMetricTrendLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i <= lastIdx; i++) {
      final sc = metricStatusColor(cur[i], goal);
      if (i == selectedIndex) {
        canvas.drawCircle(
          pts[i],
          8.5,
          Paint()
            ..color = sc.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      // 큰 점은 **계열의 마지막 칸**(일요일)에만 준다 — 회원 앱과 같은
      // 규칙이다. `lastIdx`(오늘)에 주면 수요일에 보는 이번 주에서 수요일
      // 점이 커져, 지난 주 그래프와 강조가 서로 다른 뜻을 갖는다.
      _dot(canvas, pts[i], sc, r: i == cur.length - 1 ? 5.0 : 4.2);
      _text(canvas, metricTrendNumber(cur[i]), pts[i], w, sc);
    }
  }

  void _dot(Canvas c, Offset o, Color color, {double r = 3.0}) {
    c.drawCircle(o, r + 1.3, Paint()..color = OnCareColors.surfaceCard);
    c.drawCircle(o, r, Paint()..color = color);
  }

  void _text(Canvas c, String s, Offset at, double w, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          // `TextPainter` 는 위젯 트리 밖이라 앱 서체를 물려받지 않는다.
          // 적어 주지 않으면 이 숫자만 시스템 기본 서체로 그려져, 같은 카드
          // 안에서 서체가 갈린다(#1177).
          fontFamily: OnCareTypography.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final bx = (at.dx - tp.width / 2).clamp(0.0, w - tp.width);
    var by = at.dy - tp.height - 7;
    if (by < 0) by = at.dy + 7;
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
      old.selectedIndex != selectedIndex;
}

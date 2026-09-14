import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays, weekdayCount, weekdayLabels;
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/four_week_metric_trend.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 어떤 영양 지표의 주간 추이를 볼지 고르는 식별자.
///
/// 화면에 보이는 라벨과 분리해 둔다 — 로케일이 내부 키가 되면 영어에서
/// 선택이 깨진다.
enum _TrendMetric { calories, sodium, sugar }

/// 그래프 하나를 한 문장으로. [points] 가 비면 비어 있다고 말한다 — 빈 그래프를
/// 말없이 두면 "값이 0" 인지 "아직 기록이 없는지"를 구분할 수 없다(#972).
String _semanticsLabel(
  AppLocalizations l, {
  required String title,
  required List<String> points,
}) => points.isEmpty
    ? l.a11yChartEmpty(title)
    : l.a11yChartSummary(title, points.join(', '));

/// 칼로리·나트륨·당류 주간 추이 — 선택한 지표 하나를 사용자 앱 홈 탭과 **같은
/// 그림**으로 그린다(#746).
///
/// 눈금은 사용자 앱 `dashboard_content.dart` 의 값을 그대로 쓴다. 지표를 바꿔도
/// 축 바닥이 항상 0 이라 세 그래프를 번갈아 봐도 기준선이 흔들리지 않는다.
class MetricTrendSection extends StatefulWidget {
  const MetricTrendSection({super.key, required this.report});

  final WeeklyReport report;

  @override
  State<MetricTrendSection> createState() => _MetricTrendSectionState();
}

class _MetricTrendSectionState extends State<MetricTrendSection> {
  _TrendMetric _metric = _TrendMetric.calories;

  String _label(AppLocalizations l, _TrendMetric metric) => switch (metric) {
    _TrendMetric.calories => l.metricCalories,
    _TrendMetric.sodium => l.metricSodium,
    _TrendMetric.sugar => l.metricSugar,
  };

  /// 고른 지표의 단위. 4주 추이 막대와 시맨틱 라벨이 **같은 것**을 써야
  /// 그래프와 음성 안내가 서로 다른 단위를 말하지 않는다.
  String _unit(AppLocalizations l) => switch (_metric) {
    _TrendMetric.calories => l.unitKcal,
    _TrendMetric.sodium => l.unitMg,
    _TrendMetric.sugar => l.unitGram,
  };

  /// 선택한 지표의 요일별 값. 계열이 7일이 아니면(구버전 응답) 비워 둔다.
  List<double> get _values {
    final report = widget.report;
    final series = switch (_metric) {
      _TrendMetric.calories => report.caloriesWeek.map((v) => v.toDouble()),
      _TrendMetric.sodium => report.sodiumWeek.map((v) => v.toDouble()),
      _TrendMetric.sugar => report.sugarWeek,
    }.toList(growable: false);
    return series.length == weekdayCount ? series : const <double>[];
  }

  double get _goal => switch (_metric) {
    _TrendMetric.calories => calorieTargetKcal.toDouble(),
    _TrendMetric.sodium => sodiumTargetMg.toDouble(),
    _TrendMetric.sugar => sugarTargetG.toDouble(),
  };

  List<double> get _ticks => switch (_metric) {
    _TrendMetric.calories => const <double>[0, 1500, 2500],
    _TrendMetric.sodium => const <double>[0, 1750, 3500],
    _TrendMetric.sugar => const <double>[0, 25, 50],
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final values = _values;
    // 이번 주 선은 오늘까지만 잇는다. 지난 주는 이미 다 지났으니 일요일까지.
    final int lastDrawn = widget.report.isCurrentWeek
        ? elapsedWeekdays(nowKst()) - 1
        : weekdayCount - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l.reportsMetricTrend(_label(l, _metric)),
                style: context.oncare
                    .text(OnCareTypography.strong(OnCareTypography.caption))
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
            for (final metric in _TrendMetric.values) ...<Widget>[
              const SizedBox(width: OnCareSpacing.s4),
              AppChoiceChip(
                key: ValueKey<String>('trend-metric-${metric.name}'),
                label: _label(l, metric),
                selected: metric == _metric,
                onSelected: (_) => setState(() => _metric = metric),
              ),
            ],
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 기록이 하나도 없는 주까지 바닥에 붙은 0 선을 그리면 "기록 없음"이
        // "하루 0kcal" 처럼 읽힌다.
        if (values.isEmpty || values.every((v) => v == 0))
          AppEmptyState(
            title: widget.report.isCurrentWeek
                ? l.reportsNoMetricRecords(_label(l, _metric))
                : l.reportsNoLastWeekMetricTrend(_label(l, _metric)),
            icon: Icons.show_chart_rounded,
            placement: AppStatePlacement.card,
          )
        else
          ReportMetricTrendChart(
            values: values,
            dayLabels: weekdayLabels(l),
            goal: _goal,
            ticks: _ticks,
            todayIndex: lastDrawn,
            // 지난 주는 선을 일요일까지 잇되, 그 자리에 '오늘' 표시를 붙이지는
            // 않는다.
            markToday: widget.report.isCurrentWeek,
            // 화면 위 제목과 같은 문구로 시작한다 — 음성 안내에서도 이 그래프가
            // 어느 지표의 것인지가 먼저 들린다(#972).
            semanticsLabel: _semanticsLabel(
              l,
              title: l.reportsMetricTrend(_label(l, _metric)),
              // 0 은 기록 없음이라 읽지 않는다. 아직 오지 않은 요일을 읽으면
              // 화면에 없는 값을 말하게 된다.
              points: <String>[
                for (var i = 0; i <= lastDrawn && i < values.length; i++)
                  if (values[i] != 0)
                    l.a11yChartPoint(
                      weekdayLabels(l)[i],
                      '${formatNumber(values[i])}${_unit(l)}',
                    ),
              ],
            ),
            goalLabel: l.chartGoalLabel(formatNumber(_goal)),
          ),
        // 칼로리를 볼 때만 그 칼로리가 무엇으로 이루어졌는지 함께 적는다
        // (#1437). 나트륨·당류는 쪼갤 성분이 없어 지금 그림 그대로다.
        if (_metric == _TrendMetric.calories) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          _WeeklyMacroStrip(report: widget.report),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
          child: AppDivider(),
        ),
        FourWeekMetricTrend(
          report: widget.report,
          label: _label(l, _metric),
          values: (WeeklyReport r) => switch (_metric) {
            _TrendMetric.calories => r.caloriesWeek,
            _TrendMetric.sodium => r.sodiumWeek,
            _TrendMetric.sugar => r.sugarWeek,
          },
          goal: _goal,
          unit: _unit(l),
        ),
      ],
    );
  }
}

/// 지표 하나의 주간 추이 꺾은선 — 사용자 앱 홈 탭과 **같은 그림**이다.
///
///  * 선은 **오늘까지만** 잇는다 — 아직 오지 않은 요일의 0 이 급락처럼 보이지
///    않도록. x 좌표는 7칸 기준 그대로라 주끼리 정렬된다.
///  * 점 색은 그날이 목표를 넘겼는지만 말한다(초과=빨강, 그 외=목표 안쪽 색,
///    #1070·#1239).
///  * 목표선은 두 앱 공통 파선 하나다(#1015).
///  * **진입 애니메이션이 없다.** 트레이너는 고객·기간을 바꾸며 하루에도 여러 번
///    다시 읽는데, 그때마다 선이 처음부터 그려지면 값을 읽기까지 기다려야 했다
///    (#1027).
class ReportMetricTrendChart extends StatelessWidget {
  /// Creates a weekly trend chart.
  const ReportMetricTrendChart({
    super.key,
    required this.values,
    required this.dayLabels,
    required this.goal,
    required this.ticks,
    required this.todayIndex,
    required this.semanticsLabel,
    this.goalLabel,
    this.markToday = true,
  });

  /// 요일별 값(월→일). [dayLabels] 와 길이가 같아야 한다.
  final List<double> values;

  /// 요일 라벨(월→일).
  final List<String> dayLabels;

  /// 하루 목표. 점 색과 목표선 높이를 정한다.
  final double goal;

  /// 축의 위아래를 정하는 값들. 그리지는 않는다.
  final List<double> ticks;

  /// 선을 여기까지만 잇는다. 지난 주처럼 전부 지난 구간이면 마지막 index.
  final int todayIndex;

  /// [todayIndex] 요일에 '오늘' 표시를 그릴지. 과거 주는 선이 일요일까지
  /// 이어지는데, 그 자리에 오늘 표시가 붙으면 지난 주 일요일이 오늘인 것처럼
  /// 읽힌다(#752).
  final bool markToday;

  /// 그래프가 말하는 내용 한 문장. `CustomPaint` 는 시맨틱 트리에 아무 노드도
  /// 남기지 않아, 이게 없으면 그래프가 음성 안내에서 통째로 사라진다(#972).
  final String semanticsLabel;

  /// 목표치 칸에 적는 문구(예: `목표 2,000`). null 이면 칸만 지킨다.
  final String? goalLabel;

  /// 꺾은선 영역 높이(요일 라벨 제외) — 요일 일곱 점의 오르내림이 읽히는
  /// 가장 낮은 높이. 카드 안에서 아래 탄단지 줄·4주 추이와 함께 선다.
  static const double _chartHeight = 68;

  /// '오늘' 요일 표시 원의 지름 — `caption` 한 글자가 가운데 들어가는 크기.
  static const double _todayMarkerSize = 20;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final (double lo, double hi) = _scale(
      values: values,
      ticks: ticks,
      goal: goal,
    );
    final TextStyle axis = chartAxisLabelStyle(context);
    // 눈금·요일 라벨은 낱개로 읽어 봐야 `월` `화` 뿐이라 그래프가 무슨 값을
    // 말하는지 알 수 없다. 한 덩어리로 묶고 요약 한 문장만 읽힌다.
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 목표치 칸 — 두 앱의 모든 그래프가 같은 칸을 쓴다. 목표가 없어도
            // 자리를 지켜 지표를 바꿀 때 그래프 폭이 흔들리지 않는다(#1071).
            ChartGoalAxis(
              height: _chartHeight,
              label: goalLabel,
              lineBottom:
                  goalLabel != null && goal > 0 && goal >= lo && goal <= hi
                  ? ((goal - lo) / ((hi - lo) <= 0 ? 1 : (hi - lo))) *
                        _chartHeight
                  : null,
            ),
            const SizedBox(width: chartGoalAxisGap),
            Expanded(
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: _chartHeight,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _TrendLinePainter(
                        values: values,
                        goal: goal,
                        lo: lo,
                        hi: hi,
                        todayIndex: todayIndex,
                        withinGoal: tokens.brand.statusWithinGoal,
                        valueStyle: OnCareTypography.numeric(
                          tokens.text(
                            OnCareTypography.strong(OnCareTypography.caption),
                          ),
                        ),
                        textScaler: MediaQuery.textScalerOf(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      for (var i = 0; i < dayLabels.length; i++)
                        if (i == todayIndex && markToday)
                          // 오늘: 브랜드색 원 안에 흰 글씨.
                          Container(
                            width: _todayMarkerSize,
                            height: _todayMarkerSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tokens.brand.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              dayLabels[i],
                              style: axis.copyWith(
                                color: OnCareColors.textOnFill,
                              ),
                            ),
                          )
                        else
                          Text(dayLabels[i], style: axis),
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

  /// 데이터와 눈금을 모두 담는 스케일. **0 을 바닥으로 두지 않는다** — 두면
  /// 하루하루 차이가 거의 평평한 선으로 뭉개진다.
  static (double, double) _scale({
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
}

/// 꺾은선 본체.
class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter({
    required this.values,
    required this.goal,
    required this.lo,
    required this.hi,
    required this.todayIndex,
    required this.withinGoal,
    required this.valueStyle,
    required this.textScaler,
  });

  final List<double> values;
  final double goal;
  final double lo;
  final double hi;
  final int todayIndex;

  /// 목표 안쪽 점 색(각 앱의 메인 색).
  final Color withinGoal;

  /// 점 위 값 라벨. 색은 점 색을 따른다.
  final TextStyle valueStyle;
  final TextScaler textScaler;

  // 리포트 탭 그래프 공통 — 막대 + 꺾은선 그래프와 같은 선 굵기·점 크기다.

  /// 꺾은선 굵기.
  static const double _lineWidth = 2;

  /// 점 반지름.
  static const double _pointRadius = 4;

  /// 계열의 마지막 칸(일요일) 점 반지름 — 한 주의 끝을 짚는다.
  static const double _lastPointRadius = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final span = (hi - lo) <= 0 ? 1.0 : (hi - lo);
    double dx(int i) =>
        values.length <= 1 ? w / 2 : (i / (values.length - 1)) * w;
    double dy(double v) => h - ((v - lo) / span) * h;

    // 축 밖으로 나가는 목표(범위를 벗어난 주)는 그리지 않는다 — 가장자리에
    // 붙어 테두리처럼 보인다.
    if (goal > 0 && goal >= lo && goal <= hi) {
      ChartGoalLine.paint(canvas, y: dy(goal), left: 0, right: w);
    }

    final lastIdx = todayIndex.clamp(0, values.length - 1);
    final pts = <Offset>[
      for (var i = 0; i <= lastIdx; i++) Offset(dx(i), dy(values[i])),
    ];

    if (lastIdx > 0) {
      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i <= lastIdx; i++) {
        line.lineTo(pts[i].dx, pts[i].dy);
      }
      // 값의 상태는 점으로 말하므로 선은 눈에 띄지 않는 중립 선이다.
      canvas.drawPath(
        line,
        Paint()
          ..color = OnCareColors.lineStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = _lineWidth
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i <= lastIdx; i++) {
      // 목표가 0 이면 초과로 보지 않는다 — 목표 없는 지표의 모든 기록이 빨간
      // 점이 되어 버린다.
      final Color color = goal > 0 && values[i] > goal
          ? OnCareColors.danger
          : withinGoal;
      // 큰 점은 **계열의 마지막 칸**에만 준다 — 회원 앱과 같은 규칙이다.
      final double r = i == values.length - 1 ? _lastPointRadius : _pointRadius;
      canvas.drawCircle(
        pts[i],
        r + OnCareSize.hairline,
        Paint()..color = OnCareColors.surfaceCard,
      );
      canvas.drawCircle(pts[i], r, Paint()..color = color);
      _text(canvas, formatNumber(values[i]), pts[i], w, color);
    }
  }

  void _text(Canvas c, String s, Offset at, double w, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: valueStyle.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final double bx = (at.dx - tp.width / 2).clamp(
      0.0,
      math.max(0.0, w - tp.width),
    );
    var by = at.dy - tp.height - OnCareSpacing.s8;
    if (by < 0) by = at.dy + OnCareSpacing.s8;
    tp.paint(c, Offset(bx, by));
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter old) =>
      old.values != values ||
      old.goal != goal ||
      old.lo != lo ||
      old.hi != hi ||
      old.todayIndex != todayIndex ||
      old.withinGoal != withinGoal ||
      old.valueStyle != valueStyle ||
      old.textScaler != textScaler;
}

/// 요일별 탄·단·지 — 요일 라벨 밑에 세 줄 글씨로. (#1437, #1570)
///
/// 위 꺾은선은 그날 **얼마나** 먹었는지를 말하고, 이 줄은 그 칼로리가
/// **무엇으로** 이루어졌는지를 말한다. 값은 리포트가 이미 들고 있는
/// `carbsWeek`·`proteinWeek`·`fatWeek` 그대로다.
///
/// 예전에는 요일마다 누적 막대를 그렸는데, 막대가 요일 칸 전체로 퍼지고 날마다
/// 같은 높이의 트랙을 채워 요일 간 차이가 드러나지 않았다. 그래서 값을 글씨로
/// 적는다 — 가리킬 색이 없어졌으니 색 범례도 함께 뺐다.
///
/// 기록이 없는 날은 값을 적지 않는다 — 0g 으로 적으면 "안 먹은 날" 과 "영양을
/// 모르는 날" 이 같아진다. 계열이 7일이 아닌 응답(옛 서버)은 줄 자체를 그리지
/// 않는다.
class _WeeklyMacroStrip extends StatelessWidget {
  const _WeeklyMacroStrip({required this.report});

  final WeeklyReport report;

  /// 7일 계열만 쓴다. 길이가 다르면 빈 목록이다.
  List<double> _series(List<double> raw) =>
      raw.length == weekdayCount ? raw : const <double>[];

  /// 요일 하나를 읽는 한 문장. 인접 문자열을 목록 안에 두지 않으려고 함수로
  /// 뺐다.
  String _dayPoint(
    AppLocalizations l,
    String day,
    double carbs,
    double protein,
    double fat,
    String Function(double) grams,
  ) =>
      '$day ${l.metricCarbs} ${grams(carbs)} · '
      '${l.metricProtein} ${grams(protein)} · '
      '${l.metricFat} ${grams(fat)}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final List<double> carbs = _series(report.carbsWeek);
    final List<double> protein = _series(report.proteinWeek);
    final List<double> fat = _series(report.fatWeek);
    if (carbs.isEmpty || protein.isEmpty || fat.isEmpty) {
      return const SizedBox.shrink();
    }
    bool recorded(int i) => carbs[i] > 0 || protein[i] > 0 || fat[i] > 0;
    // 하루라도 영양이 있어야 그린다. 셋 다 0 인 주는 값이 없는 주다.
    if (!<int>[for (int i = 0; i < weekdayCount; i++) i].any(recorded)) {
      return const SizedBox.shrink();
    }

    final List<String> days = weekdayLabels(l);
    String grams(double v) => '${formatNumber(v)}${l.unitGram}';
    // 음성 안내는 요일마다 세 값을 함께 읽는다 — 글씨는 낱개로 읽히지 않게 묶는다.
    final List<String> points = <String>[
      for (int i = 0; i < weekdayCount; i++)
        if (recorded(i))
          _dayPoint(l, days[i], carbs[i], protein[i], fat[i], grams),
    ];

    // 위 그래프의 요일 라벨과 같은 자리에 선다 — 왼쪽 목표치 칸만큼 비우고, 남은
    // 폭에서 요일 라벨처럼 양 끝을 붙여 늘어놓는다.
    final double axisInset =
        chartGoalAxisWidth * MediaQuery.textScalerOf(context).scale(1) +
        chartGoalAxisGap;

    return Semantics(
      container: true,
      label: _semanticsLabel(
        l,
        title: l.reportsMetricTrend(l.dietMacros),
        points: points,
      ),
      child: ExcludeSemantics(
        child: Padding(
          key: const ValueKey<String>('trend-macro-strip'),
          padding: EdgeInsets.only(left: axisInset),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) => Stack(
              children: <Widget>[
                for (int i = 0; i < weekdayCount; i++)
                  if (recorded(i))
                    Align(
                      alignment: Alignment(-1 + 2 * i / (weekdayCount - 1), -1),
                      child: _MacroDayText(
                        key: ValueKey<String>('trend-macro-day-$i'),
                        // 칸을 넘으면 옆 요일과 겹친다 — 넘치는 만큼만 줄인다.
                        maxWidth: c.maxWidth / weekdayCount,
                        align: i == 0
                            ? CrossAxisAlignment.start
                            : i == weekdayCount - 1
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.center,
                        lines: <String>[
                          '${l.metricCarbs} ${grams(carbs[i])}',
                          '${l.metricProtein} ${grams(protein[i])}',
                          '${l.metricFat} ${grams(fat[i])}',
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 하루치 `탄수화물 ng / 단백질 ng / 지방 ng` 세 줄.
class _MacroDayText extends StatelessWidget {
  const _MacroDayText({
    super.key,
    required this.maxWidth,
    required this.align,
    required this.lines,
  });

  final double maxWidth;
  final CrossAxisAlignment align;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = context.oncare
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textSecondary);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: align,
          children: <Widget>[
            for (final String line in lines)
              Text(line, maxLines: 1, style: style),
          ],
        ),
      ),
    );
  }
}

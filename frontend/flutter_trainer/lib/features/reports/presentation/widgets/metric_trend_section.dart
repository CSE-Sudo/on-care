import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/design_system/tokens/spacing.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays, weekdayCount, weekdayLabels;
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/four_week_metric_trend.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/chart_semantics.dart';
import 'package:oncare_trainer/shared/widgets/goal_line.dart';
import 'package:oncare_trainer/shared/widgets/metric_pill.dart';
import 'package:oncare_trainer/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_trainer/shared/widgets/section_card.dart';

/// 어떤 영양 지표의 주간 추이를 볼지 고르는 식별자.
///
/// 화면에 보이는 라벨과 분리해 둔다 — 로케일이 내부 키가 되면 영어에서
/// 선택이 깨진다.
enum _TrendMetric { calories, sodium, sugar }

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l.reportsMetricTrend(_label(l, _metric)),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.subtleForeground,
                ),
              ),
            ),
            for (final metric in _TrendMetric.values) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              MetricPill(
                key: ValueKey<String>('trend-metric-${metric.name}'),
                label: _label(l, metric),
                selected: metric == _metric,
                onTap: () => setState(() => _metric = metric),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // 기록이 하나도 없는 주까지 바닥에 붙은 0 선을 그리면 "기록 없음"이
        // "하루 0kcal" 처럼 읽힌다.
        if (values.isEmpty || values.every((v) => v == 0))
          EmptyHint(
            message: widget.report.isCurrentWeek
                ? l.reportsNoMetricRecords(_label(l, _metric))
                : l.reportsNoLastWeekMetricTrend(_label(l, _metric)),
          )
        else
          MetricTrendChart(
            values: values,
            dayLabels: weekdayLabels(l),
            goal: _goal,
            ticks: _ticks,
            // 지난 주는 이미 다 지났으니 선을 일요일까지 잇되, 그 자리에
            // '오늘' 표시를 붙이지는 않는다.
            todayIndex: widget.report.isCurrentWeek
                ? elapsedWeekdays(nowKst()) - 1
                : weekdayCount - 1,
            markToday: widget.report.isCurrentWeek,
            // 화면 위 제목과 같은 문구로 시작한다 — 음성 안내에서도 이 그래프가
            // 어느 지표의 것인지가 먼저 들린다(#972).
            semanticsLabel: chartSemanticsLabel(
              l,
              title: l.reportsMetricTrend(_label(l, _metric)),
              points: chartSeriesPoints(
                l,
                values: values,
                dayLabels: weekdayLabels(l),
                format: (double v) => '${metricTrendNumber(v)}${_unit(l)}',
                // 이번 주 선은 오늘까지만 잇는다. 아직 오지 않은 요일을 읽으면
                // 화면에 없는 값을 말하게 된다.
                upTo: widget.report.isCurrentWeek
                    ? elapsedWeekdays(nowKst()) - 1
                    : weekdayCount - 1,
              ),
            ),
            goalLabel: l.chartGoalLabel(metricTrendNumber(_goal)),
            formatTick: metricTrendNumber,
          ),
        // 칼로리를 볼 때만 그 칼로리가 무엇으로 이루어졌는지 함께 적는다
        // (#1437). 나트륨·당류는 쪼갤 성분이 없어 지금 그림 그대로다.
        if (_metric == _TrendMetric.calories) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _WeeklyMacroStrip(report: widget.report),
        ],
        const Divider(height: AppSpacing.xl, color: AppColors.border),
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
    String grams(double v) => '${metricTrendNumber(v)}${l.unitGram}';
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
      label: chartSemanticsLabel(
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
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align,
        children: <Widget>[
          for (final String line in lines)
            Text(
              line,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedForeground,
              ),
            ),
        ],
      ),
    ),
  );
}

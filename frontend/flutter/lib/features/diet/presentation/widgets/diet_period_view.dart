
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/design_system/charts/period_scroll_chart.dart';
import 'package:oncare/design_system/figma/figma_kit.dart';
import 'package:oncare/design_system/tokens/colors.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/chart_semantics.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';

/// 식단 탭의 기간 뷰(이번 주 / 이번 달).
///
/// 홈은 식단을 주간으로도 보여주는데 식단 탭에는 하루치밖에 없었다(#670). 운동
/// 영양 요약 카드의 기준 높이. 오늘·이번 주·전체 세 화면이 함께 쓴다 — 기간
/// 토글을 눌렀을 때 카드가 커졌다 작아지면 그 아래 내용이 그때마다 뛴다.
/// 최소 높이라 글자 배율이 커지면 셋이 함께 커진다. (#1124)
///
/// 공용 테마의 역할 글자로 그리면 `오늘` 카드 내용이 240 을 조금 넘어 세 카드
/// 높이가 어긋났다 — 4 격자의 다음 값으로 올려 셋을 다시 맞춘다(#1699).
const double kDietSummaryCardHeight = 248;

/// 탭의 `운동 현황` 과 같은 기간 토글 아래에서, 고른 지표(칼로리·나트륨·당류)의
/// 일별 막대와 **하루 평균**을 보여준다. 합계가 아니라 평균을 머리 숫자로 두는
/// 이유는 주(7일)와 달(30일)의 길이가 달라 합계끼리는 견줄 수 없기 때문이다.
class DietPeriodView extends ConsumerStatefulWidget {
  const DietPeriodView({
    required this.range,
    required this.weekly,
    this.profile,
    super.key,
  });

  final DietDateRange range;

  /// 이번 주인가. 주간은 홈 탭과 **같은 꺾은선**으로, 이번 달은 일별 막대로
  /// 그린다 — 30칸을 꺾은선으로 그리면 점과 값 라벨이 서로 겹친다.
  final bool weekly;

  final UserProfile? profile;

  @override
  ConsumerState<DietPeriodView> createState() => _DietPeriodViewState();
}

enum _Metric { calories, sodium, sugar }

class _DietPeriodViewState extends ConsumerState<DietPeriodView> {
  _Metric _metric = _Metric.calories;

  /// `전체` 그래프의 스크롤 위치와 고른 날. 머리의 숫자와 막대가 같은 상태를
  /// 봐야 해서 여기서 들고 둘에게 건넨다. (#1018)
  final PeriodChartSelection _selection = PeriodChartSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  String _label(AppLocalizations l, _Metric m) => switch (m) {
    _Metric.calories => l.dietCalories,
    _Metric.sodium => l.dietSodium,
    _Metric.sugar => l.dietSugar,
  };

  String _unit(AppLocalizations l, _Metric m) => switch (m) {
    _Metric.calories => l.unitKcal,
    _Metric.sodium => l.dietUnitMg,
    _Metric.sugar => l.dietUnitG,
  };

  double _valueOf(DietPeriodDay d, _Metric m) => switch (m) {
    _Metric.calories => d.calories.toDouble(),
    _Metric.sodium => d.sodiumMg.toDouble(),
    _Metric.sugar => d.sugarG,
  };

  void _selectMetric(_Metric m) {
    // 지표를 바꾸면 고른 날의 숫자는 뜻을 잃는다 — 같이 푼다.
    _selection.reset();
    setState(() => _metric = m);
  }

  int _goalOf(_Metric m) {
    final UserProfile? p = widget.profile;
    return switch (m) {
      _Metric.calories =>
        p?.effectiveDailyCalories ?? UserProfile.defaultDailyCalories,
      _Metric.sodium =>
        p?.effectiveDailySodiumMg ?? UserProfile.defaultDailySodiumMg,
      _Metric.sugar =>
        p?.effectiveDailySugarG ?? UserProfile.defaultDailySugarG,
    };
  }

  /// 꺾은선의 가로 눈금. **홈 탭과 같은 값**이라 두 화면의 눈금이 어긋나지
  /// 않는다(`dashboard_content.dart` 의 지표 설정과 짝).
  List<double> _ticks(_Metric m) => switch (m) {
    _Metric.calories => const <double>[0, 1500, 2500],
    _Metric.sodium => const <double>[0, 1750, 3500],
    _Metric.sugar => const <double>[0, 25, 50],
  };

  /// 소수 첫째 자리까지만 남기고 정수는 콤마만 붙인다(당류 17.8 이 18 로
  /// 반올림돼 하루 뷰와 어긋나지 않도록).
  String _number(num v) => v == v.roundToDouble()
      ? NumberFormat('#,###').format(v)
      : NumberFormat('#,##0.#').format(v);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<DietPeriod> async = ref.watch(
      dietPeriodProvider(widget.range),
    );
    final DateFormat fmt = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    );

    // 바깥 섹션(영양 요약)이 이미 제목과 좌우 여백을 갖는다 — 여기서 또 두면
    // 제목이 두 줄로 겹치고 여백이 이중으로 들어간다(#681).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 지표 버튼과 날짜 범위를 **한 줄에** 둔다. 범위만 따로 한 줄을 쓰면
        // 제목·범위·버튼 세 줄이 되어 정작 그래프가 아래로 밀린다.
        Row(
          children: <Widget>[
            for (final _Metric m in _Metric.values) ...<Widget>[
              _MetricPill(
                label: _label(l, m),
                // 버튼은 **무엇을 고르는가**만 말한다. 지표마다 색이 다르면
                // 고르기 전부터 셋이 서로 다른 뜻을 가진 것처럼 보인다.
                // 지표별 색은 아래 그래프가 계속 쓴다.
                color: FigmaColors.primary,
                active: _metric == m,
                onTap: () => _selectMetric(m),
              ),
              if (m != _Metric.values.last) const SizedBox(width: 8),
            ],
            const SizedBox(width: 8),
            // 좁은 화면에서 먼저 줄어드는 쪽은 범위다 — 버튼은 눌러야 하는
            // 것이라 잘리면 안 된다.
            Expanded(
              child: Text(
                l.dietPeriodRange(
                  fmt.format(widget.range.from),
                  fmt.format(widget.range.to),
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedForeground,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          ),
          error: (Object e, StackTrace _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: <Widget>[
                Text(
                  l.dietLoadError,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.foreground,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  // 실패는 날짜별 provider 에 남아 있다. 집계만 무효화하면
                  // 같은 에러를 다시 읽어 와 아무 일도 일어나지 않는다.
                  onPressed: () {
                    for (final DateTime d in dietRangeDates(widget.range)) {
                      ref.invalidate(dietByDateProvider(d));
                    }
                    ref.invalidate(dietPeriodProvider(widget.range));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FigmaColors.primary,
                    side: BorderSide(color: FigmaColors.primaryA(0.4)),
                  ),
                  child: Text(l.actionRetry),
                ),
              ],
            ),
          ),
          data: (DietPeriod period) => period.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      l.dietPeriodEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                )
              : _PeriodBody(
                  period: period,
                  metricLabel: _label(l, _metric),
                  unit: _unit(l, _metric),
                  // 세 지표가 같은 파랑을 쓴다. 지표마다 색이 다르면 같은
                  // 카드 안에서 버튼(파랑 통일)과 그래프가 서로 다른 말을
                  // 한다 — 목표를 넘긴 막대만 색으로 튄다(#694).
                  color: FigmaColors.primary,
                  goal: _goalOf(_metric).toDouble(),
                  values: <double>[
                    for (final DietPeriodDay d in period.days)
                      _valueOf(d, _metric),
                  ],
                  dates: <DateTime>[
                    for (final DietPeriodDay d in period.days) d.date,
                  ],
                  // 칼로리 막대는 탄단지로 쌓아 그린다. 나트륨·당류는 쌓을
                  // 성분이 없으므로 지금처럼 한 색이다.
                  days: _metric == _Metric.calories ? period.days : null,
                  format: _number,
                  // 지표를 바꾸면 그래프가 처음부터 다시 그려진다.
                  replayKey: _metric,
                  metric: _metric,
                  weekly: widget.weekly,
                  ticks: _ticks(_metric),
                  selection: _selection,
                ),
        ),
      ],
    );
  }
}

class _PeriodBody extends StatelessWidget {
  const _PeriodBody({
    required this.period,
    required this.metricLabel,
    required this.unit,
    required this.color,
    required this.goal,
    required this.values,
    required this.dates,
    required this.format,
    required this.replayKey,
    required this.weekly,
    required this.ticks,
    required this.metric,
    required this.selection,
    this.days,
  });

  final DietPeriod period;
  final String metricLabel;
  final String unit;
  final Color color;
  final double goal;
  final List<double> values;
  final List<DateTime> dates;
  final String Function(num) format;
  final Object replayKey;

  /// 칼로리 막대를 탄단지로 쌓기 위한 원본. 나트륨·당류를 볼 때는 null 이다.
  final List<DietPeriodDay>? days;

  /// 지금 고른 지표. 툴팁이 탄단지를 덧붙일지 판단한다.
  final _Metric metric;

  /// 이번 주면 꺾은선, 이번 달이면 막대.
  final bool weekly;

  /// 꺾은선의 가로 눈금. 홈 탭과 같은 값을 쓴다.
  final List<double> ticks;

  /// `전체` 그래프의 스크롤·선택 상태. 머리의 숫자가 이걸 보고 평균과 하루
  /// 값을 오간다. (#1018)
  final PeriodChartSelection selection;

  /// 고른 날의 머리 문구 — `2026. 8. 17.` 처럼 로케일 형식의 날짜.
  String _dayHeadline(BuildContext context, DateTime date) =>
      DateFormat.yMd(Localizations.localeOf(context).toString()).format(date);

  /// 머리 숫자 옆에 붙일 탄단지. [picked] 이 있으면 그날 값, 없으면 기록이
  /// 있는 날의 하루 평균이다. 칼로리를 보고 있지 않거나(나트륨·당류) 서버가
  /// 영양을 주지 않은 기간이면 null 이라 아무것도 붙지 않는다.
  _Macros? _macrosFor(int? picked) {
    final List<DietPeriodDay>? all = days;
    if (metric != _Metric.calories || all == null) return null;
    if (picked != null) {
      final DietPeriodDay d = all[picked];
      return d.hasMacros
          ? _Macros(carbs: d.carbsG, protein: d.proteinG, fat: d.fatG)
          : null;
    }
    final List<DietPeriodDay> logged = all
        .where((DietPeriodDay d) => d.hasMacros)
        .toList();
    if (logged.isEmpty) return null;
    double avg(double Function(DietPeriodDay) of) =>
        logged.fold<double>(0, (double a, DietPeriodDay d) => a + of(d)) /
        logged.length;
    return _Macros(
      carbs: avg((DietPeriodDay d) => d.carbsG),
      protein: avg((DietPeriodDay d) => d.proteinG),
      fat: avg((DietPeriodDay d) => d.fatG),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<String> labels = weekDayLabels(l);
    // 카드의 빈 곳을 누르면 고른 날이 풀려 다시 하루 평균이 뜬다 (#1123).
    // 막대·점은 자기 탭을 먼저 받으므로 이 손짓은 그 밖의 자리에만 닿는다.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => selection.select(null),
      child: Container(
        key: const Key('diet-period-card'),
        width: double.infinity,
        // 오늘 카드와 같은 높이 (#1124) — 기간 토글을 눌러도 카드가 커졌다
        // 작아지지 않는다.
        constraints: const BoxConstraints(minHeight: kDietSummaryCardHeight),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: ListenableBuilder(
                    listenable: selection,
                    builder: (BuildContext context, Widget? _) {
                      // 이번 주도 점을 골라 그날 값을 볼 수 있다 (#1122).
                      // 스크롤이 없을 뿐, 머리 숫자가 평균과 하루를 오가는
                      // 규칙은 `전체` 와 같다.
                      final int? picked = selection.selected;
                      // 평소에는 **보이는 구간의** 평균, 날을 고르면 그날의 값.
                      // 보이지 않는 날까지 섞은 평균은 지금 화면을 설명하지
                      // 못한다. (#1018)
                      final double value = picked == null
                          ? selection.averageOf(values)
                          : values[picked];
                      final bool over = goal > 0 && value > goal;
                      // 칼로리를 볼 때만 탄단지를 곁들인다 — 나트륨·당류는
                      // 탄단지로 쪼갤 수 있는 값이 아니다. 날을 고르면 그날의
                      // 탄단지, 아니면 기록이 있는 날의 하루 평균이다. (#1121)
                      final _Macros? macros = _macrosFor(picked);
                      return PeriodChartHeadline(
                        selected: picked != null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    picked == null
                                        ? '${l.dietPeriodAverage} · $metricLabel'
                                        : '${_dayHeadline(context, dates[picked])} · '
                                              '$metricLabel',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.mutedForeground,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text.rich(
                                      TextSpan(
                                        children: <InlineSpan>[
                                          TextSpan(
                                            text: format(value),
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w800,
                                              color: over
                                                  ? FigmaColors.dangerRed
                                                  : FigmaColors.ink,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          TextSpan(
                                            text: ' / ${format(goal)} $unit',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.mutedForeground,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (macros != null) ...<Widget>[
                              const SizedBox(width: 12),
                              _MacroDetail(macros: macros, muted: weekly),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            // 기간 합계는 뺐다 (#1121). 주와 달은 길이가 달라 합계끼리 견줄 수
            // 없고, 카드가 답해야 할 질문은 "하루에 얼마나" 하나다.
            //
            // 머리와 그래프 사이의 구분선도 뺐다 (#1123). 한 카드가 한 가지를
            // 말하는데 선이 둘로 갈랐고, 고른 막대에서 머리 카드로 올라가는
            // 세로선이 그 선에서 끊겼다. `전체` 는 그 빈 칸을 그래프가 들고
            // 있어(topGap) 세로선이 머리 카드까지 닿는다.
            SizedBox(height: weekly ? 14 : 0),
            if (weekly)
              Builder(
                builder: (BuildContext context) {
                  final AppLocalizations l = AppLocalizations.of(context);
                  final List<String> days = <String>[
                    for (final DateTime d in dates) labels[d.weekday - 1],
                  ];
                  final int today = _todayIndexIn(dates);
                  return ListenableBuilder(
                    listenable: selection,
                    builder: (BuildContext context, Widget? _) =>
                        MetricTrendChart(
                          values: values,
                          dayLabels: days,
                          goal: goal,
                          ticks: ticks,
                          selectedIndex: selection.selected,
                          onSelected: selection.select,
                          // 이번 주는 오늘까지만 잇는다. 오늘이 이 범위 밖이면
                          // (지난 주를 보고 있으면) 마지막 칸까지 전부 그린다.
                          todayIndex: today,
                          replayKey: replayKey,
                          // 카드 머리의 `평균 · 칼로리` 와 같은 지표 이름으로
                          // 시작한다.
                          semanticsLabel: chartSemanticsLabel(
                            l,
                            title: metricLabel,
                            points: chartSeriesPoints(
                              l,
                              values: values,
                              dayLabels: days,
                              format: (double v) => '${format(v)} $unit',
                              upTo: today,
                            ),
                          ),
                          goalLabel: '${l.homeGoal}\n${format(goal)}',
                          formatTick: (double v) => format(v),
                          // 남는 자리는 그래프가 쓴다 — 세 화면의 카드 높이를
                          // 같게 두면서(#1124) 빈 칸을 만들지 않는다.
                          height: 105,
                        ),
                  );
                },
              )
            else
              _PeriodBars(
                values: values,
                dates: dates,
                goal: goal,
                color: color,
                replayKey: replayKey,
                // 막대 툴팁이 "무슨 값을 얼마나" 라고 말하려면 지표 이름·단위와
                // 숫자 서식이 카드 머리 숫자와 같아야 한다.
                metricLabel: metricLabel,
                unit: unit,
                format: format,
                selection: selection,
                days: days,
              ),
          ],
        ),
      ),
    );
  }
}

/// 머리 숫자 옆의 탄단지 한 덩어리. 막대를 쌓은 색을 그대로 써서, 예전 그래프
/// 아래 범례가 하던 말(어느 색이 무엇인지)까지 여기서 함께 한다. (#1121)
class _Macros {
  const _Macros({
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  final double carbs;
  final double protein;
  final double fat;
}

class _MacroDetail extends StatelessWidget {
  const _MacroDetail({required this.macros, required this.muted});

  final _Macros macros;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<(String, double, Color)> rows = <(String, double, Color)>[
      (
        l.homeMacroCarbs,
        macros.carbs,
        muted ? AppColors.mutedForeground : FigmaColors.macroCarbs,
      ),
      (
        l.homeMacroProtein,
        macros.protein,
        muted ? AppColors.mutedForeground : FigmaColors.macroProtein,
      ),
      (
        l.homeMacroFat,
        macros.fat,
        muted ? AppColors.mutedForeground : FigmaColors.macroFat,
      ),
    ];
    return Column(
      key: const Key('diet-period-macros'),
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (String label, double value, Color color) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _macroGrams(value),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: FigmaColors.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// `204g` — 소수점은 버린다. 옆의 머리 숫자가 주인공이고 이 줄은 곁들이다.
String _macroGrams(double v) => '${v.round()}g';

/// 일별 막대. 목표선을 얇은 점선처럼 얹어 그날이 목표를 넘었는지 한눈에 보이게
/// 하고, 목표를 넘은 날만 경고색으로 칠한다.
class _PeriodBars extends StatelessWidget {
  const _PeriodBars({
    required this.values,
    required this.dates,
    required this.goal,
    required this.color,
    required this.replayKey,
    required this.metricLabel,
    required this.unit,
    required this.format,
    required this.selection,
    this.days,
  });

  final List<double> values;
  final List<DateTime> dates;
  final double goal;

  /// 스크롤 위치와 고른 날. 카드 머리의 숫자가 같은 상태를 본다. (#1018)
  final PeriodChartSelection selection;
  final Color color;
  final Object replayKey;

  /// 칼로리를 볼 때의 원본. 막대의 탄단지 구간과 툴팁에 사용한다.
  final List<DietPeriodDay>? days;

  /// 탄단지를 쌓지 않는 나트륨·당류와 영양 정보가 없는 칼로리 막대의 색.
  Color get _barColor => color;

  /// 툴팁이 부를 지표 이름(칼로리·나트륨·당류)과 단위, 그리고 카드 머리 숫자와
  /// 같은 숫자 서식.
  final String metricLabel;
  final String unit;
  final String Function(num) format;

  /// [i] 번째 칸의 원본. 칼로리를 보고 있지 않으면 null 이다.
  DietPeriodDay? _dayAt(int i) {
    final List<DietPeriodDay>? source = days;
    if (source == null || i >= source.length) return null;
    return source[i];
  }

  /// 아직 오지 않은 날인가. (#950)
  ///
  /// 기록하지 않은 것이 아니라 **기록할 수 없는** 날이다. 둘을 같은 말로 그리면
  /// 한 달을 훑으며 "며칠을 빠뜨렸나" 를 셀 때 미래의 빈 칸까지 빠뜨린 날처럼
  /// 읽힌다 — 달 초에는 그 수가 스무 날이 넘는다.
  ///
  /// 운동 쪽은 트레이너 리포트의 `BarSeriesChart` 가 `pendingFromIndex` 로 이미
  /// 같은 구분을 한다(#754). 같은 규칙을 여기에도 둔다.
  bool _isPending(int i) =>
      DateUtils.dateOnly(dates[i]).isAfter(DateUtils.dateOnly(nowKst()));

  /// 툴팁과 **같은 내용**을 한 줄짜리 시맨틱 라벨로. 색 사각형(`WidgetSpan`)은
  /// 빼고 줄바꿈은 쉼표로 바꾼다 — 음성 안내는 줄을 나누어 읽지 않는다.
  String _tipText(
    AppLocalizations l,
    DateFormat dayFormat,
    int i,
    bool hasGoal,
  ) => TextSpan(children: _tipSpans(l, dayFormat, i, hasGoal))
      .toPlainText(includePlaceholders: false)
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .join(', ');

  /// 한 막대의 툴팁 내용 — 운동 탭 `운동 현황` 툴팁과 같은 구조다.
  /// `[색 사각형] 지표  값 단위` 한 줄, 목표를 넘긴 날은 초과분을 한 줄 더.
  List<InlineSpan> _tipSpans(
    AppLocalizations l,
    DateFormat dayFormat,
    int i,
    bool hasGoal,
  ) {
    final double value = values[i];
    final bool over = hasGoal && value > goal;
    final List<InlineSpan> spans = <InlineSpan>[
      TextSpan(
        text: '${dayFormat.format(dates[i])}\n',
        style: const TextStyle(color: AppColors.mutedForeground),
      ),
    ];
    // 아직 오지 않은 날과 지나갔는데 비운 날은 다른 말이다(#950). 하루 평균이
    // 이미 **기록이 있는 날만으로** 나누므로, 계산은 둘을 구분하는데 화면만
    // 구분하지 않는 셈이었다.
    if (_isPending(i)) {
      spans.add(TextSpan(text: l.dietPeriodNotYet));
      return spans;
    }
    // 기록이 없는 날은 0 이 아니라 '기록 없음' 이다. 0 으로 적으면 굶은 날과
    // 적지 않은 날이 같은 말이 된다.
    if (value <= 0) {
      spans.add(TextSpan(text: l.dietPeriodNoRecord));
      return spans;
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            // 막대와 같은 색이어야 툴팁의 첫 줄이 그 막대를 가리킨다.
            color: over ? FigmaColors.dangerRed : _barColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
    spans.add(TextSpan(text: '$metricLabel   ${format(value)} $unit'));
    // 칼로리 뒤에는 그 칼로리가 어디서 왔는지를 적는다 — 숫자 하나만 보고는
    // 같은 2,000kcal 이 밥에서 왔는지 기름에서 왔는지 알 수 없다.
    final DietPeriodDay? day = _dayAt(i);
    if (day != null && day.hasMacros) {
      for (final ({Color color, String label, double grams}) m
          in <({Color color, String label, double grams})>[
            (
              color: FigmaColors.macroCarbs,
              label: l.homeMacroCarbs,
              grams: day.carbsG,
            ),
            (
              color: FigmaColors.macroProtein,
              label: l.homeMacroProtein,
              grams: day.proteinG,
            ),
            (
              color: FigmaColors.macroFat,
              label: l.homeMacroFat,
              grams: day.fatG,
            ),
          ]) {
        spans.add(const TextSpan(text: '\n'));
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: m.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
        spans.add(
          TextSpan(text: '${m.label}   ${format(m.grams)} ${l.dietUnitG}'),
        );
      }
    }
    // 막대가 왜 빨간지를 색이 아니라 글로도 말한다.
    if (over) {
      spans.add(
        TextSpan(
          text: '\n${l.dietPeriodOverGoal(format(value - goal), unit)}',
          style: const TextStyle(color: FigmaColors.dangerRed),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // `8월 12일 (화)` / `Tue, Aug 12` — 어느 막대가 며칠인지 x축 라벨만으로는
    // 짚을 수 없다(달은 6칸에 하나만 적는다).
    final DateFormat dayFormat = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    );
    // 카드 높이를 오늘·이번 주와 같게 맞추기 위한 값이다 (#1124) —
    // 여기서 1px 을 바꾸면 `전체` 카드 높이가 그만큼 달라진다.
    const double chartHeight = 109;
    // 축 위쪽에 여유를 둔다. 목표를 넘은 날이 없으면 목표가 곧 최댓값이 되어
    // 목표선이 차트 맨 위(=바깥)에 놓여 잘려 보이지 않았다.
    final double peak = <double>[
      goal,
      ...values,
    ].fold<double>(1, (double a, double b) => b > a ? b : a);
    final double maxValue = peak * 1.15;
    // 목표가 0이면(프로필에 목표를 0으로 넣은 경우) 초과 판정을 하지 않는다 —
    // 카드 위쪽 배지도 같은 규칙이라, 배지는 '정상'인데 막대만 빨간 일이 없다.
    final bool hasGoal = goal > 0;
    // 달(30칸)에서도 라벨이 겹치지 않도록 몇 칸에 하나만 적는다.
    final int labelStep = values.length > 10 ? (values.length / 6).ceil() : 1;
    // 기록이 하나도 없는 달은 막대마다 `기록 없음` 을 서른 번 읽히는 대신
    // 비어 있다고 한 번만 말한다(#972).
    final bool empty = values.every((double v) => v <= 0);

    return Semantics(
      container: true,
      label: empty
          ? chartSemanticsLabel(l, title: metricLabel, points: const <String>[])
          : null,
      child: ExcludeSemantics(
        excluding: empty,
        child: ListenableBuilder(
          listenable: selection,
          builder: (BuildContext context, Widget? _) => PeriodScrollChart(
            count: values.length,
            height: chartHeight,
            selectedIndex: selection.selected,
            onSelected: selection.select,
            onVisibleRangeChanged: selection.setVisible,
            // 목표선은 스크롤 안쪽에 얹혀 밀어도 막대와 같은 높이를 따라가고
            // (#1015), 목표치는 왼쪽 칸에 두 줄로 적힌다 (#1071).
            goalBottom: hasGoal
                ? chartHeight * (goal / maxValue).clamp(0.0, 1.0)
                : null,
            goalLabel: '${l.homeGoal}\n${format(goal)}',
            // 머리 카드와 막대 사이의 빈 칸 — 고른 날의 세로선이 여기까지
            // 올라와 회색 카드에 닿는다 (#1123).
            topGap: 14,
            // 지표를 바꾸면 막대가 바닥에서 다시 자란다 (#1148). 칸 수만 보면
            // 칼로리 → 나트륨처럼 개수가 같은 전환에서 그림만 슬쩍 바뀌어,
            // 무엇이 달라졌는지 눈으로 따라갈 수가 없다.
            revealKey: replayKey,
            // 날짜만 적으면 `26`, `9` 가 무슨 날인지 알 수 없다 — 달을 함께
            // 적는다 (#1123).
            labelBuilder: (int i) =>
                i % labelStep == 0 ? '${dates[i].month}/${dates[i].day}' : '',
            calloutBuilder: (BuildContext context, int i) =>
                const SizedBox.shrink(),
            barBuilder: (BuildContext context, int i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Semantics(
                label: _tipText(l, dayFormat, i, hasGoal),
                child: Tooltip(
                  key: Key('diet-period-bar-tip-$i'),
                  richMessage: TextSpan(
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: FigmaColors.ink,
                      height: 1.3,
                    ),
                    children: _tipSpans(l, dayFormat, i, hasGoal),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: FigmaColors.hairline),
                    boxShadow: kCardShadow,
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _Bar(
                      key: Key('diet-period-bar-$i'),
                      height:
                          chartHeight * (values[i] / maxValue).clamp(0.0, 1.0),
                      pending: _isPending(i),
                      // 목표를 넘긴 날만 빨강이다. 칼로리는 탄단지 원본이 있으면
                      // 누적 구간, 나트륨·당류는 기존 브랜드 색 한 칸이다.
                      over: hasGoal && values[i] > goal,
                      color: _barColor,
                      day: _dayAt(i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 한 칸의 막대. 탄단지가 있으면 아래에서부터 탄·단·지 순으로 쌓는다.
class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.height,
    required this.day,
    required this.over,
    required this.color,
    this.pending = false,
  });

  final double height;
  final DietPeriodDay? day;

  /// 아직 오지 않은 날인가. 지나간 빈 날의 그루터기보다 **더 옅게** 그린다 —
  /// 트레이너 리포트가 `pendingFromIndex` 에 쓰는 규칙과 같다(#754, #950).
  final bool pending;

  /// 목표를 넘긴 날인가. 넘긴 날은 통째로 빨강으로 표시한다.
  final bool over;

  /// 탄단지 원본이 없을 때 사용하는 지표 색.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final DietPeriodDay? d = day;
    const BorderRadius radius = BorderRadius.vertical(top: Radius.circular(3));
    if (pending) {
      // 아직 오지 않은 날은 **빈 트랙**이다. 지나간 빈 날과 같은 그루터기를
      // 그리면 둘이 구분되지 않는다.
      return Container(
        height: 2,
        decoration: const BoxDecoration(
          color: FigmaColors.hairline,
          borderRadius: radius,
        ),
      );
    }
    if (over || d == null || !d.hasMacros) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: (over ? FigmaColors.dangerRed : color).withValues(alpha: 0.85),
          borderRadius: radius,
        ),
      );
    }
    final double total = d.carbsKcal + d.proteinKcal + d.fatKcal;
    if (total <= 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: radius,
        ),
      );
    }
    // 총높이는 기록 칼로리를 따르되, 설명되지 않는 열량은 나머지 구간으로 둔다.
    // 탄단지 환산 열량이 더 크면 음수 나머지를 만들지 않고 그 합계를 기준으로 한다.
    final double basis = math.max(d.calories.toDouble(), total);
    final double rest = basis - total;
    final List<({Color color, double kcal})> parts =
        <({Color color, double kcal})>[
          if (rest / basis > 0.01) (color: FigmaColors.track, kcal: rest),
          if (d.fatKcal > 0) (color: FigmaColors.macroFat, kcal: d.fatKcal),
          if (d.proteinKcal > 0)
            (color: FigmaColors.macroProtein, kcal: d.proteinKcal),
          if (d.carbsKcal > 0)
            (color: FigmaColors.macroCarbs, kcal: d.carbsKcal),
        ];
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final ({Color color, double kcal}) part in parts)
              Expanded(
                flex: math.max(1, (part.kcal / basis * 1000).round()),
                child: ColoredBox(color: part.color),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.12) : FigmaColors.statBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? color.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? color : AppColors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// 오늘이 이 범위의 몇 번째 칸인가. 범위 밖이면 마지막 칸 — 지난 주를 보고
/// 있을 때 선이 중간에서 끊기지 않게 한다.
int _todayIndexIn(List<DateTime> dates) {
  final DateTime today = DateUtils.dateOnly(nowKst());
  for (int i = 0; i < dates.length; i++) {
    if (DateUtils.dateOnly(dates[i]) == today) return i;
  }
  return dates.length - 1;
}

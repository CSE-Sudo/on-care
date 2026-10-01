import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oncare_report/gen/l10n/report_sheet_localizations.dart';
import 'package:oncare_report/src/report_sheet.dart';
import 'package:oncare_report/src/report_sheet_data.dart';
import 'package:oncare_report/src/report_sheet_l10n.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 PDF 한 장 — A4 한 쪽에 모든 것을 담는 결과지. (#2485, #2652)
///
/// 트레이너 웹과 회원 앱이 **같은 위젯**으로 그린다 — 트레이너가 보낸 파일과
/// 회원이 앱에서 여는 리포트가 한 모양이다. 색은 그리는 앱의 테마 토큰을 따른다.
///
/// 예전 문서는 편집기 카드를 차례로 구워 쪽을 나눠 얹어, 피드백이 길면 두세
/// 장이 되고 회원은 휴대폰에서 파일을 넘겨 가며 봐야 했다. 이 위젯은 크기가
/// A4 비율([width] × [height])로 **고정**이고, 글 칸은 모두 줄 수 제한과
/// 말줄임을 가진다. 내용이 아무리 길어도 이 한 장을 넘지 않는다.
///
/// 짜임은 체성분 결과지의 문법을 빌린다 — 머리 띠의 회원 정보 한 줄 표,
/// 왼쪽 넓은 열의 표준 범위 대비 막대·요일별 표·추이, 오른쪽 좁은 열의
/// 점수·평가·4주 평균 대비·회원 답, 아래 트레이너 코칭. 로고·배색은 빌리지
/// 않고 앱의 색·서체 토큰만 쓴다.
///
/// 앱 타이포그래피 토큰으로 그린 이 폭을 A4 폭에 담으면 본문이 8pt 남짓이
/// 된다 — 인쇄한 결과지의 밀도다.
class ReportSheetDocument extends StatelessWidget {
  /// Creates the sheet.
  const ReportSheetDocument({
    super.key,
    required this.report,
    required this.feedback,
    this.trend,
    this.history = const <ReportSheetWeek>[],
    this.today,
    this.feedbackTitle,
  });

  final ReportSheetWeek report;

  /// 아래 칸에 싣는 글 — 트레이너의 코칭.
  final String feedback;

  /// 아래 칸의 제목. 없으면 `트레이너 코칭`.
  ///
  /// 회원 앱이 포인트로 연 자기 리포트처럼 트레이너가 쓴 글이 아닌 것을 실을
  /// 때만 바꾼다.
  final String? feedbackTitle;

  /// 여덟 주 운동 실적. 읽지 못했으면 null — 유형별 줄과 추이가 `미집계`.
  final ReportSheetTrend? trend;

  /// 직전 주들의 리포트 — 4주 평균 대비에 쓴다.
  final List<ReportSheetWeek> history;

  /// 이번 주 리포트에서 지난 날 수를 셀 기준일. 없으면 지금.
  final DateTime? today;

  /// 결과지의 논리 크기. 높이는 폭의 √2 배 — A4 와 같은 비율이다.
  static const double width = 1000;
  static const double height = 1414;

  static const double _padding = OnCareSpacing.s32;
  static const double _gap = OnCareSpacing.s24;
  static const double _rightWidth = 300;
  static const double _leftWidth = width - _padding * 2 - _gap - _rightWidth;

  /// 아래 코칭 칸의 높이. 나머지는 위 두 열이 쓴다.
  static const double _feedbackHeight = 220;

  @override
  Widget build(BuildContext context) {
    final ReportSheet sheet = ReportSheet.of(
      report,
      trend: trend,
      history: history,
      today: today,
    );
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: OnCareColors.surfaceCard,
        child: Padding(
          padding: const EdgeInsets.all(_padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(report: report, sheet: sheet),
              const SizedBox(height: OnCareSpacing.s16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: _leftWidth,
                      child: _Fit(
                        width: _leftWidth,
                        child: _LeftColumn(
                          report: report,
                          sheet: sheet,
                          trend: trend,
                        ),
                      ),
                    ),
                    const SizedBox(width: _gap),
                    SizedBox(
                      width: _rightWidth,
                      child: _Fit(
                        width: _rightWidth,
                        child: _RightColumn(report: report, sheet: sheet),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: OnCareSpacing.s12),
              SizedBox(
                height: _feedbackHeight,
                child: _FeedbackBox(text: feedback, title: feedbackTitle),
              ),
              const SizedBox(height: OnCareSpacing.s8),
              const _Footnote(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 열 하나를 제 폭에 그리고, 받은 높이보다 길면 **줄여서** 담는다.
///
/// 열의 줄은 모두 한 줄·몇 줄로 묶여 있어 보통은 자리가 남는다. 그래도
/// 서체가 달라 한 줄이 조금 높아지는 날에 넘치는 대신 조금 작아지게 해,
/// 결과지가 언제나 한 장으로 서게 한다.
class _Fit extends StatelessWidget {
  const _Fit({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.topStart,
    child: SizedBox(width: width, child: child),
  );
}

// ── 머리 띠 ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.sheet});

  final ReportSheetWeek report;
  final ReportSheet sheet;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final OnCareTokens tokens = context.oncare;
    final int? due = sheet.mealDaysDue;
    final List<(String, String)> cells = <(String, String)>[
      (l.reportsSheetInfoMember, report.memberName),
      (
        l.reportsSheetInfoPeriod,
        l.reportsSheetPeriodValue(_ymd(report.weekStart), _ymd(report.weekEnd)),
      ),
      (
        l.reportsPdfLabelSessions,
        report.sessionsBooked == 0
            ? l.reportsPdfNoData
            : l.reportsPdfAttendance(
                '${report.sessionsDone}',
                '${report.sessionsBooked}',
                '${report.attendanceRate}',
              ),
      ),
      (
        l.reportsSheetInfoMealDays,
        due == null
            ? l.reportsPdfNoData
            : l.reportsSheetDaysOf('${sheet.mealDays}', '$due'),
      ),
    ];
    return Column(
      key: const ValueKey<String>('sheet-header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l.reportsPdfDocTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens
              .text(OnCareTypography.titleLarge)
              .copyWith(color: tokens.brand.strong),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        ColoredBox(
          color: tokens.brand.primary,
          child: const SizedBox(height: OnCareSpacing.s4),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < cells.length; i++)
                Expanded(
                  // 기간이 가장 길다 — 폭을 조금 더 준다.
                  flex: i == 1 ? 3 : 2,
                  child: _InfoCell(label: cells[i].$1, value: cells[i].$2),
                ),
            ],
          ),
        ),
        const ColoredBox(
          color: OnCareColors.lineStrong,
          child: SizedBox(height: OnCareSpacing.s2),
        ),
      ],
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: OnCareColors.lineStrong),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s8,
          vertical: OnCareSpacing.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.text(
                OnCareTypography.numeric(
                  OnCareTypography.strong(OnCareTypography.bodyLarge),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 섹션 제목 띠 ─────────────────────────────────────────────────────────

class _SectionBand extends StatelessWidget {
  const _SectionBand({required this.title, this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.brand.surface,
        border: Border(bottom: BorderSide(color: tokens.brand.primary)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s8,
          vertical: OnCareSpacing.s4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.titleSmall)
                    .copyWith(color: tokens.brand.strong),
              ),
            ),
            if (hint case final String h) ...<Widget>[
              const SizedBox(width: OnCareSpacing.s8),
              Flexible(
                child: Text(
                  h,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 왼쪽 열 ─────────────────────────────────────────────────────────────

class _LeftColumn extends StatelessWidget {
  const _LeftColumn({
    required this.report,
    required this.sheet,
    required this.trend,
  });

  final ReportSheetWeek report;
  final ReportSheet sheet;
  final ReportSheetTrend? trend;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final String Function(String) pct = l.reportsPdfValuePercent;
    final String Function(String) kcal = l.reportsPdfValueKcal;
    final String Function(String) g = l.reportsPdfValueGram;
    final String Function(String) mg = l.reportsPdfValueMg;
    final ReportSheetTrend? goals = trend;

    _BarRow diet(SheetDietItem item, String label, String Function(String) u) {
      final SheetMeasure m = sheet.diet[item]!;
      return _BarRow(
        label: label,
        measure: m,
        value: _formatted(l, m.value, u),
        target: l.reportsSheetGoal(u(_formatNumber(m.target.round()))),
      );
    }

    _BarRow kind(SheetExerciseItem item, ExerciseKind k) {
      final SheetMeasure m = sheet.exercise[item]!;
      final double? v = m.value;
      return _BarRow(
        label: _kindLabel(l, k),
        measure: m,
        value: v == null ? l.reportsPdfNoData : _kindValueText(l, k, v),
        target: goals == null
            ? l.reportsPdfNoData
            : l.reportsSheetGoal(_kindValueText(l, k, goals.goalOf(k))),
      );
    }

    _BarRow rate(SheetExerciseItem item, String label, String target) {
      final SheetMeasure m = sheet.exercise[item]!;
      return _BarRow(
        label: label,
        measure: m,
        value: _formatted(l, m.value, pct),
        target: target,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _BarSection(
          key: const ValueKey<String>('sheet-diet'),
          title: l.reportsSheetDietTitle,
          hint: l.reportsSheetDietHint,
          rows: <_BarRow>[
            diet(SheetDietItem.calories, l.metricCalories, kcal),
            diet(SheetDietItem.carbs, l.metricCarbs, g),
            diet(SheetDietItem.protein, l.metricProtein, g),
            diet(SheetDietItem.fat, l.metricFat, g),
            diet(SheetDietItem.sodium, l.metricSodium, mg),
            diet(SheetDietItem.sugar, l.metricSugar, g),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        _BarSection(
          key: const ValueKey<String>('sheet-exercise'),
          title: l.reportsSheetExerciseTitle,
          hint: l.reportsSheetExerciseHint,
          rows: <_BarRow>[
            rate(
              SheetExerciseItem.completion,
              l.reportsPdfLabelCompletion,
              l.reportsSheetGoal(pct('100')),
            ),
            rate(
              SheetExerciseItem.attendance,
              l.reportsSheetAttendance,
              report.sessionsBooked == 0
                  ? l.reportsPdfNoData
                  : l.reportsSheetGoal(
                      l.reportsPdfValueSessions('${report.sessionsBooked}'),
                    ),
            ),
            kind(SheetExerciseItem.cardio, ExerciseKind.cardio),
            kind(SheetExerciseItem.strength, ExerciseKind.strength),
            kind(SheetExerciseItem.stretching, ExerciseKind.stretching),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        _DailyTable(report: report),
        const SizedBox(height: OnCareSpacing.s12),
        _TrendSection(report: report, sheet: sheet, trend: trend),
      ],
    );
  }
}

/// 값을 단위와 함께. 없으면 `미집계`.
String _formatted(
  ReportSheetLocalizations l,
  double? value,
  String Function(String) unit,
) => value == null ? l.reportsPdfNoData : unit(_formatNumber(value.round()));

/// 막대 한 줄의 내용.
class _BarRow {
  const _BarRow({
    required this.label,
    required this.measure,
    required this.value,
    required this.target,
  });

  final String label;
  final SheetMeasure measure;
  final String value;
  final String target;
}

/// 부족·적정·초과 칸의 폭 비율 — 머리 눈금과 막대가 같이 쓴다.
const int _underFlex = 3;
const int _normalFlex = 3;
const int _overFlex = 4;

/// 막대 줄의 이름 칸·값 칸 폭.
const double _barLabelWidth = 128;
const double _barValueWidth = 104;

/// 막대의 굵기.
const double _barThickness = 14;

class _BarSection extends StatelessWidget {
  const _BarSection({
    super.key,
    required this.title,
    required this.hint,
    required this.rows,
  });

  final String title;
  final String hint;
  final List<_BarRow> rows;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle scale = tokens.text(OnCareTypography.caption);

    Widget band(String text, Color fill, Color ink, int flex) => Expanded(
      flex: flex,
      child: ColoredBox(
        color: fill,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: scale.copyWith(color: ink),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SectionBand(title: title, hint: hint),
        const SizedBox(height: OnCareSpacing.s4),
        Row(
          children: <Widget>[
            const SizedBox(width: _barLabelWidth + _barValueWidth),
            band(
              l.reportsSheetBandUnder,
              OnCareColors.lineStrong,
              OnCareColors.textSecondary,
              _underFlex,
            ),
            band(
              l.reportsSheetBandNormal,
              tokens.brand.primary,
              OnCareColors.textOnFill,
              _normalFlex,
            ),
            band(
              l.reportsSheetBandOver,
              OnCareColors.lineStrong,
              OnCareColors.textSecondary,
              _overFlex,
            ),
          ],
        ),
        for (final _BarRow row in rows) _BarLine(row: row),
      ],
    );
  }
}

class _BarLine extends StatelessWidget {
  const _BarLine({required this.row});

  final _BarRow row;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: _barLabelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text(
                      OnCareTypography.strong(OnCareTypography.bodySmall),
                    ),
                  ),
                  Text(
                    row.target,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _barValueWidth,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: OnCareSpacing.s8,
                ),
                child: Text(
                  row.value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.text(
                    OnCareTypography.numeric(
                      OnCareTypography.strong(OnCareTypography.bodySmall),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: _RangeBar(measure: row.measure)),
          ],
        ),
      ),
    );
  }
}

/// 세 칸 바탕 위에 값만큼 채운 막대. 값이 없으면 바탕만 선다.
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.measure});

  final SheetMeasure measure;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final double? position = measure.position;
    final Color fill = (measure.concerning ?? false)
        ? OnCareColors.caution
        : tokens.brand.primary;
    return SizedBox(
      height: _barThickness,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: _underFlex,
                child: ColoredBox(
                  color: measure.hasUnder
                      ? OnCareColors.surfaceInput
                      : OnCareColors.surfaceCard,
                ),
              ),
              Expanded(
                flex: _normalFlex,
                child: ColoredBox(color: tokens.brand.surface),
              ),
              Expanded(
                flex: _overFlex,
                child: ColoredBox(
                  color: measure.hasOver
                      ? OnCareColors.surfaceInput
                      : OnCareColors.surfaceCard,
                ),
              ),
            ],
          ),
          if (position != null)
            FractionallySizedBox(
              key: const ValueKey<String>('sheet-bar-fill'),
              alignment: AlignmentDirectional.centerStart,
              widthFactor: math.max(position, _minFill),
              heightFactor: _fillHeight,
              child: ColoredBox(color: fill),
            ),
        ],
      ),
    );
  }

  /// 0 에 가까운 값도 막대가 보이도록 하는 가장 짧은 길이.
  static const double _minFill = 0.01;

  /// 막대는 바탕 칸보다 조금 가늘다 — 칸 경계가 막대 위아래로 보인다.
  static const double _fillHeight = 0.64;
}

// ── 요일별 기록 ──────────────────────────────────────────────────────────

class _DailyTable extends StatelessWidget {
  const _DailyTable({required this.report});

  final ReportSheetWeek report;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final OnCareTokens tokens = context.oncare;
    final List<String> weekdays = _weekdayNames(l);
    final TextStyle head = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: tokens.brand.strong);
    final TextStyle cell = tokens.text(
      OnCareTypography.numeric(OnCareTypography.caption),
    );

    T? at<T>(List<T> xs, int i) => i < xs.length ? xs[i] : null;
    String orDash(num? v, String Function(String)? unit) {
      if (v == null || v <= 0) return '-';
      final String n = _formatNumber(v);
      return unit == null ? n : unit(n);
    }

    final List<(String, List<String>)> rows = <(String, List<String>)>[
      (
        l.reportsSheetDailyCompletion,
        <String>[
          for (int i = 0; i < weekdays.length; i++)
            orDash(
              at(report.days, i)?.completion ?? at(report.weekCompletion, i),
              l.reportsPdfValuePercent,
            ),
        ],
      ),
      (
        l.reportsSheetDailyCalories,
        <String>[
          for (int i = 0; i < weekdays.length; i++)
            orDash(at(report.caloriesWeek, i), null),
        ],
      ),
      (
        l.reportsSheetDailyMeals,
        <String>[
          for (int i = 0; i < weekdays.length; i++)
            orDash(at(report.mealCounts, i), null),
        ],
      ),
      (
        l.reportsSheetDailyWorkouts,
        <String>[
          for (int i = 0; i < weekdays.length; i++)
            switch (at(report.days, i)) {
              final ReportSheetDay d when d.totalCount > 0 =>
                '${d.doneCount}/${d.totalCount}',
              _ => '-',
            },
        ],
      ),
    ];

    Widget text(
      String s,
      TextStyle style, {
      TextAlign align = TextAlign.center,
    }) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s4,
        vertical: OnCareSpacing.s2,
      ),
      child: Text(
        s,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );

    return Column(
      key: const ValueKey<String>('sheet-daily'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SectionBand(title: l.reportsSheetDailyTitle),
        const SizedBox(height: OnCareSpacing.s4),
        Table(
          columnWidths: const <int, TableColumnWidth>{
            0: FixedColumnWidth(_barLabelWidth),
          },
          border: const TableBorder(
            horizontalInside: BorderSide(color: OnCareColors.lineSubtle),
            bottom: BorderSide(color: OnCareColors.lineSubtle),
          ),
          children: <TableRow>[
            TableRow(
              decoration: const BoxDecoration(color: OnCareColors.surfaceInput),
              children: <Widget>[
                const SizedBox.shrink(),
                for (final String d in weekdays) text(d, head),
              ],
            ),
            for (final (String, List<String>) row in rows)
              TableRow(
                children: <Widget>[
                  text(
                    row.$1,
                    tokens.text(
                      OnCareTypography.strong(OnCareTypography.caption),
                    ),
                    align: TextAlign.start,
                  ),
                  for (final String v in row.$2) text(v, cell),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

// ── 추이 ────────────────────────────────────────────────────────────────

/// 꺾은선 그림의 높이.
const double _chartHeight = 100;

class _TrendSection extends StatelessWidget {
  const _TrendSection({
    required this.report,
    required this.sheet,
    required this.trend,
  });

  final ReportSheetWeek report;
  final ReportSheet sheet;
  final ReportSheetTrend? trend;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final List<ReportSheetTrendWeek> weeks =
        trend?.weeks ?? const <ReportSheetTrendWeek>[];
    final List<double?> kcal = <double?>[
      for (int i = 0; i < _weekdayNames(l).length; i++)
        i < report.caloriesWeek.length && report.caloriesWeek[i] > 0
            ? report.caloriesWeek[i].toDouble()
            : null,
    ];
    final double goal = report.calorieGoal.toDouble();
    final double kcalTop = math.max(
      goal * 1.5,
      kcal.whereType<double>().fold<double>(0, math.max) * 1.15,
    );
    return Column(
      key: const ValueKey<String>('sheet-trend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SectionBand(title: l.reportsSheetTrendTitle),
        const SizedBox(height: OnCareSpacing.s8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _Chart(
                title: l.reportsSheetTrendWeekly,
                values: sheet.weeklyRates,
                top: 1,
                labels: <String?>[
                  for (final double? r in sheet.weeklyRates)
                    r == null
                        ? null
                        : l.reportsPdfValuePercent('${(r * 100).round()}'),
                ],
                axis: <String>[
                  for (final ReportSheetTrendWeek w in weeks)
                    '${w.weekStart.month}/${w.weekStart.day}',
                ],
                empty: trend == null
                    ? l.reportsTrendUnavailable
                    : l.chartNoRecord,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s16),
            Expanded(
              child: _Chart(
                title: l.reportsSheetTrendDaily,
                values: kcal,
                top: kcalTop,
                target: goal,
                labels: <String?>[
                  for (final double? v in kcal)
                    v == null ? null : _formatNumber(v.round()),
                ],
                axis: _weekdayNames(l),
                empty: l.chartNoRecord,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.title,
    required this.values,
    required this.top,
    required this.labels,
    required this.axis,
    required this.empty,
    this.target,
  });

  final String title;
  final List<double?> values;
  final double top;
  final List<String?> labels;
  final List<String> axis;
  final String empty;
  final double? target;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextStyle caption = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    final bool hasData = values.any((double? v) => v != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.text(OnCareTypography.strong(OnCareTypography.caption)),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        SizedBox(
          height: _chartHeight,
          child: hasData
              ? CustomPaint(
                  painter: _LinePainter(
                    values: values,
                    top: top,
                    target: target,
                    labels: labels,
                    line: tokens.brand.primary,
                    grid: OnCareColors.lineSubtle,
                    goal: OnCareColors.chartGoalLine,
                    labelStyle: tokens.text(
                      OnCareTypography.numeric(OnCareTypography.caption),
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: const BoxDecoration(
                    color: OnCareColors.surfaceInput,
                    borderRadius: OnCareRadius.smAll,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(OnCareSpacing.s8),
                      child: Text(
                        empty,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: caption,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: OnCareSpacing.s2),
        Row(
          children: <Widget>[
            for (final String a in axis)
              Expanded(
                child: Text(
                  a,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: caption,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 칸마다 점 하나 — 칸 가운데에 찍고, 이웃한 점끼리 잇는다. 빈 칸에서 선이
/// 끊긴다(기록 없는 날을 0 으로 긋지 않는다).
class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.top,
    required this.target,
    required this.labels,
    required this.line,
    required this.grid,
    required this.goal,
    required this.labelStyle,
  });

  final List<double?> values;
  final double top;
  final double? target;
  final List<String?> labels;
  final Color line;
  final Color grid;
  final Color goal;
  final TextStyle labelStyle;

  /// 점 위 글씨가 들어갈 윗자리.
  static const double _headroom = 18;
  static const double _dot = 3;
  static const double _stroke = 2;
  static const double _dash = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || top <= 0) return;
    final double slot = size.width / values.length;
    final double plotHeight = size.height - _headroom;
    double yOf(double v) =>
        _headroom + plotHeight * (1 - (v / top).clamp(0.0, 1.0));

    final Paint gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      gridPaint,
    );

    if (target case final double t) {
      final double y = yOf(t);
      final Paint dash = Paint()
        ..color = goal
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += _dash * 2) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + _dash, size.width), y),
          dash,
        );
      }
    }

    final Paint stroke = Paint()
      ..color = line
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke;
    final Paint dot = Paint()..color = line;
    Offset? previous;
    for (int i = 0; i < values.length; i++) {
      final double? v = values[i];
      if (v == null) {
        previous = null;
        continue;
      }
      final Offset p = Offset(slot * (i + 0.5), yOf(v));
      if (previous != null) canvas.drawLine(previous, p, stroke);
      canvas.drawCircle(p, _dot, dot);
      previous = p;

      final String? label = i < labels.length ? labels[i] : null;
      if (label == null) continue;
      final TextPainter tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: slot + slot / 2);
      tp.paint(
        canvas,
        Offset(p.dx - tp.width / 2, math.max(0, p.dy - tp.height - _dot)),
      );
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.top != top || old.target != target;
}

// ── 오른쪽 열 ────────────────────────────────────────────────────────────

class _RightColumn extends StatelessWidget {
  const _RightColumn({required this.report, required this.sheet});

  final ReportSheetWeek report;
  final ReportSheet sheet;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _ScoreBox(score: sheet.score),
      const SizedBox(height: OnCareSpacing.s16),
      _Evaluation(sheet: sheet),
      const SizedBox(height: OnCareSpacing.s16),
      _Averages(sheet: sheet),
      const SizedBox(height: OnCareSpacing.s16),
      _MemberAnswers(feedback: report.answers),
    ],
  );
}

class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.score});

  final SheetScore score;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final OnCareTokens tokens = context.oncare;
    final int? value = score.value;
    final TextStyle caption = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    String partLabel(SheetScorePart p) => switch (p) {
      SheetScorePart.completion => l.reportsPdfLabelCompletion,
      SheetScorePart.attendance => l.reportsSheetAttendance,
      SheetScorePart.mealLogging => l.reportsSheetInfoMealDays,
      SheetScorePart.calorieDays => l.reportsSheetCalorieDays,
    };
    return Column(
      key: const ValueKey<String>('sheet-score'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SectionBand(title: l.reportsSheetScoreTitle),
        const SizedBox(height: OnCareSpacing.s8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value == null ? '-' : '$value',
              style: tokens
                  .text(OnCareTypography.numeric(OnCareTypography.display))
                  .copyWith(color: tokens.brand.primary),
            ),
            const SizedBox(width: OnCareSpacing.s4),
            Text(
              l.reportsSheetScoreUnit,
              style: tokens.text(OnCareTypography.bodySmall),
            ),
          ],
        ),
        if (value == null)
          Text(
            l.reportsSheetScoreNone,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: caption,
          ),
        for (final SheetScorePart p in SheetScorePart.values)
          _KeyValue(
            label: partLabel(p),
            value: switch (score.parts[p]) {
              final double v => l.reportsPdfValuePercent('${v.round()}'),
              null => l.reportsPdfNoData,
            },
          ),
        const SizedBox(height: OnCareSpacing.s4),
        Text(
          l.reportsSheetScoreFormula,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: caption,
        ),
      ],
    );
  }
}

/// 이름과 값 한 줄.
class _KeyValue extends StatelessWidget {
  const _KeyValue({
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: tokens.text(
                OnCareTypography.numeric(
                  OnCareTypography.strong(OnCareTypography.caption),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Evaluation extends StatelessWidget {
  const _Evaluation({required this.sheet});

  final ReportSheet sheet;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final List<(String, SheetMeasure)> items = <(String, SheetMeasure)>[
      (l.metricCalories, sheet.diet[SheetDietItem.calories]!),
      (l.metricCarbs, sheet.diet[SheetDietItem.carbs]!),
      (l.metricProtein, sheet.diet[SheetDietItem.protein]!),
      (l.metricFat, sheet.diet[SheetDietItem.fat]!),
      (l.metricSodium, sheet.diet[SheetDietItem.sodium]!),
      (l.metricSugar, sheet.diet[SheetDietItem.sugar]!),
      (
        l.reportsPdfLabelCompletion,
        sheet.exercise[SheetExerciseItem.completion]!,
      ),
      (l.reportsSheetAttendance, sheet.exercise[SheetExerciseItem.attendance]!),
    ];
    return Column(
      key: const ValueKey<String>('sheet-eval'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SectionBand(title: l.reportsSheetEvalTitle),
        const SizedBox(height: OnCareSpacing.s4),
        for (final (String, SheetMeasure) item in items)
          _EvalRow(label: item.$1, measure: item.$2),
      ],
    );
  }
}

/// 한 항목의 칸 고르기 — 체성분 결과지의 평가 칸처럼 해당 칸에 표시한다.
class _EvalRow extends StatelessWidget {
  const _EvalRow({required this.label, required this.measure});

  final String label;
  final SheetMeasure measure;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final OnCareTokens tokens = context.oncare;
    final SheetBand? band = measure.band;
    final List<(SheetBand, String)> options = <(SheetBand, String)>[
      if (measure.hasUnder) (SheetBand.under, l.reportsSheetBandUnder),
      (SheetBand.normal, l.reportsSheetBandNormal),
      if (measure.hasOver) (SheetBand.over, l.reportsSheetBandOver),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.text(
                OnCareTypography.strong(OnCareTypography.caption),
              ),
            ),
          ),
          for (int i = 0; i < 3; i++)
            Expanded(
              flex: 3,
              child: i < options.length
                  ? _Check(
                      text: options[i].$2,
                      checked: band == options[i].$1,
                      warn:
                          band == options[i].$1 &&
                          (measure.concerning ?? false),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

/// 네모 칸과 이름. 고른 칸은 채운다.
class _Check extends StatelessWidget {
  const _Check({required this.text, required this.checked, required this.warn});

  final String text;
  final bool checked;
  final bool warn;

  static const double _box = 10;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color ink = warn ? OnCareColors.caution : tokens.brand.primary;
    return Row(
      children: <Widget>[
        Container(
          key: checked ? const ValueKey<String>('sheet-eval-checked') : null,
          width: _box,
          height: _box,
          decoration: BoxDecoration(
            color: checked ? ink : OnCareColors.surfaceCard,
            border: Border.all(
              color: checked ? ink : OnCareColors.textDisabled,
            ),
          ),
        ),
        const SizedBox(width: OnCareSpacing.s4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens
                .text(
                  checked
                      ? OnCareTypography.strong(OnCareTypography.caption)
                      : OnCareTypography.caption,
                )
                .copyWith(color: checked ? ink : OnCareColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _Averages extends StatelessWidget {
  const _Averages({required this.sheet});

  final ReportSheet sheet;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle head = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    final TextStyle cell = tokens.text(
      OnCareTypography.numeric(OnCareTypography.caption),
    );

    (String, String Function(String)) spec(SheetAverageItem item) =>
        switch (item) {
          SheetAverageItem.calories => (
            l.metricCalories,
            l.reportsPdfValueKcal,
          ),
          SheetAverageItem.completion => (
            l.reportsPdfLabelCompletion,
            l.reportsPdfValuePercent,
          ),
          SheetAverageItem.sodium => (l.metricSodium, l.reportsPdfValueMg),
          SheetAverageItem.mealDays => (
            l.reportsSheetMealDaysLabel,
            l.reportsPdfValueDays,
          ),
        };

    String change(double? d, String Function(String) unit) {
      if (d == null) return l.reportsPdfNoData;
      final int r = d.round();
      if (r == 0) return unit('0');
      return '${r > 0 ? '▲' : '▼'} ${unit(_formatNumber(r.abs()))}';
    }

    Widget text(String s, TextStyle style, {TextAlign align = TextAlign.end}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
          child: Text(
            s,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );

    return Column(
      key: const ValueKey<String>('sheet-average'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SectionBand(title: l.reportsSheetAverageTitle),
        const SizedBox(height: OnCareSpacing.s4),
        Table(
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(5),
            1: FlexColumnWidth(4),
            2: FlexColumnWidth(4),
            3: FlexColumnWidth(4),
          },
          border: const TableBorder(
            horizontalInside: BorderSide(color: OnCareColors.lineSubtle),
          ),
          children: <TableRow>[
            TableRow(
              children: <Widget>[
                const SizedBox.shrink(),
                text(l.reportsSheetAverageNow, head),
                text(l.reportsSheetAverageBase, head),
                text(l.reportsSheetAverageChange, head),
              ],
            ),
            for (final SheetAverageItem item in SheetAverageItem.values)
              TableRow(
                children: <Widget>[
                  text(
                    spec(item).$1,
                    tokens.text(
                      OnCareTypography.strong(OnCareTypography.caption),
                    ),
                    align: TextAlign.start,
                  ),
                  text(
                    _formatted(l, sheet.averages[item]!.current, spec(item).$2),
                    cell,
                  ),
                  text(
                    _formatted(l, sheet.averages[item]!.average, spec(item).$2),
                    cell,
                  ),
                  text(
                    change(sheet.averages[item]!.change, spec(item).$2),
                    cell,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _MemberAnswers extends StatelessWidget {
  const _MemberAnswers({required this.feedback});

  final ReportSheetAnswers? feedback;

  /// 회원 메모의 줄 수. 넘치면 말줄임으로 끝난다.
  static const int noteLines = 4;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final ReportSheetAnswers? given = feedback;
    String pain(ReportSheetAnswers f) {
      if (!f.hasPain) return l.reportsMemberFeedbackPainNone;
      final DateTime? on = f.painOn;
      if (on == null) return f.painArea;
      return l.reportsMemberFeedbackPainOn(
        f.painArea,
        l.dateMonthDay(on.month, on.day),
      );
    }

    final String none = l.reportsMemberFeedbackUnanswered;
    return Column(
      key: const ValueKey<String>('sheet-member'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _SectionBand(title: l.reportsMemberFeedbackTitle),
        const SizedBox(height: OnCareSpacing.s4),
        _KeyValue(
          label: l.reportsMemberFeedbackConditionLabel,
          value: given == null ? none : _conditionLabel(l, given.conditionWire),
        ),
        _KeyValue(
          label: l.reportsMemberFeedbackIntensityLabel,
          value: given == null ? none : _intensityLabel(l, given.intensityWire),
        ),
        _KeyValue(
          label: l.reportsMemberFeedbackPainLabel,
          value: given == null ? none : pain(given),
        ),
        _KeyValue(
          label: l.reportsMemberFeedbackNoteLabel,
          value: given == null
              ? none
              : given.note.isEmpty
              ? l.reportsMemberFeedbackNoteNone
              : given.note,
          maxLines: noteLines,
        ),
      ],
    );
  }
}

// ── 트레이너 코칭 ────────────────────────────────────────────────────────

class _FeedbackBox extends StatelessWidget {
  const _FeedbackBox({required this.text, this.title});

  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final OnCareTokens tokens = context.oncare;
    final String body = text.trim().isEmpty
        ? l.reportsPdfNoFeedback
        : text.trim();
    final TextStyle style = tokens.text(OnCareTypography.bodySmall);
    return Column(
      key: const ValueKey<String>('sheet-feedback'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionBand(title: title ?? l.reportsFeedbackTitle),
        const SizedBox(height: OnCareSpacing.s8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                // 칸에 들어가는 만큼만 줄을 준다 — 넘치는 글은 잘리는 대신
                // 말줄임으로 끝난다.
                final TextPainter probe = TextPainter(
                  text: TextSpan(text: body, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                );
                final double line = probe.preferredLineHeight;
                probe.dispose();
                final int lines = math.max(1, (box.maxHeight / line).floor());
                return Text(
                  body,
                  key: const ValueKey<String>('sheet-feedback-text'),
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final ReportSheetLocalizations l = reportSheetLocalizationsOf(context);
    final OnCareTokens tokens = context.oncare;
    return Text(
      l.reportsSheetFootnote,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens
          .text(OnCareTypography.caption)
          .copyWith(color: OnCareColors.textTertiary),
    );
  }
}

// ── 표기 ─────────────────────────────────────────────────────────────────

/// 요일 이름(월 … 일).
List<String> _weekdayNames(ReportSheetLocalizations l) => <String>[
  l.weekdayMon,
  l.weekdayTue,
  l.weekdayWed,
  l.weekdayThu,
  l.weekdayFri,
  l.weekdaySat,
  l.weekdaySun,
];

/// `YYYY-MM-DD`.
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 천 단위 쉼표. 정수가 아니면 소수 한 자리.
String _formatNumber(num value) => reportFormatNumber(value);

/// 운동 유형의 이름.
String _kindLabel(ReportSheetLocalizations l, ExerciseKind kind) =>
    switch (kind) {
      ExerciseKind.cardio => l.routineTypeCardio,
      ExerciseKind.strength => l.routineTypeStrength,
      ExerciseKind.stretching => l.routineTypeStretching,
    };

/// 유형의 값을 그 유형의 단위로 — 유산소·스트레칭은 분, 근력은 세트.
String _kindValueText(
  ReportSheetLocalizations l,
  ExerciseKind kind,
  num value,
) => switch (kind) {
  ExerciseKind.cardio ||
  ExerciseKind.stretching => l.minutesShort(value.round()),
  ExerciseKind.strength => l.progSetsValue(value.round()),
};

/// 컨디션 답의 이름. 모르는 값은 그대로 적는다.
String _conditionLabel(ReportSheetLocalizations l, String wire) =>
    switch (wire) {
      'great' => l.reportsMemberFeedbackConditionGreat,
      'good' => l.reportsMemberFeedbackConditionGood,
      'ok' => l.reportsMemberFeedbackConditionOk,
      'tired' => l.reportsMemberFeedbackConditionTired,
      'bad' => l.reportsMemberFeedbackConditionBad,
      _ => wire,
    };

/// 강도 답의 이름. 모르는 값은 그대로 적는다.
String _intensityLabel(ReportSheetLocalizations l, String wire) =>
    switch (wire) {
      'too_easy' => l.reportsMemberFeedbackIntensityTooEasy,
      'right' => l.reportsMemberFeedbackIntensityRight,
      'hard' => l.reportsMemberFeedbackIntensityHard,
      'too_hard' => l.reportsMemberFeedbackIntensityTooHard,
      _ => wire,
    };

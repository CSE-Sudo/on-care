import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// ① 이번 주 — 네 줄을 **하나의 요일 축**에 겹쳐 놓은 격자. (#2232)
///
/// 예전 리포트는 운동 카드·식단 카드·나트륨 카드가 따로 서 있었다. 그러면
/// 화요일에 운동을 안 했다는 것과 화요일에 식단을 안 적었다는 것을 두 번
/// 스크롤해서 알아내야 하고, **같이 무너진 날**은 끝내 보이지 않는다. 이
/// 격자가 답하는 질문은 "무엇이 나빴나"가 아니라 "어느 날이 무너졌나"다.
///
/// 줄 순서는 PT 세션 → 개인 운동 → 식단 기록 → 섭취 칼로리다. 위의 둘은
/// 트레이너가 정한 것이고 아래 둘은 회원이 한 것이라, 위에서 아래로 읽으면
/// `정해 준 것 대비 한 것` 이 된다.
///
/// 아래 두 줄의 생김새가 서로 다른 것은 값의 성질이 달라서다. 수행·기록 횟수는
/// **셀 수 있는 것**이라 칸마다 하나의 수로 서고, 칼로리는 **오르내리는 것**이라
/// 목표선 위아래로 흐르는 꺾은선으로 그린다. 칼로리를 칸에 숫자로만 적으면
/// 2,340 과 1,540 이 같은 크기의 글씨라 어느 날이 튀었는지가 읽히지 않는다.
class ReportWeekGrid extends StatelessWidget {
  /// Creates the grid.
  const ReportWeekGrid({super.key, required this.report, this.calorieBaseline});

  final WeeklyReport report;

  /// 직전 넉 주의 하루 평균 섭취 칼로리 — 칼로리 줄이 견주는 `평소`.
  /// 모르면 null 이고, 그때는 비교 줄을 그리지 않는다.
  final double? calorieBaseline;

  /// 왼쪽 이름 칸의 폭. 요일 칸은 남는 자리를 똑같이 나눠 갖는다.
  static const double _labelWidth = 104;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<String> names = weekdayNames(l);
    final List<ReportDay> days = report.days;
    final List<int> meals = report.mealCounts;
    // 아직 오지 않은 날은 `0회` 가 아니라 `–` 다. 이번 주를 주 중에 열면
    // 남은 요일이 전부 0 으로 채워져 오는데, 그걸 그대로 적으면 목요일에 연
    // 화면에서 토·일이 **안 한 날**로 보인다 — 트레이너가 아직 오지도 않은
    // 이틀을 근거로 회원을 나무라게 된다. 지난 주에는 그런 날이 없다.
    final int lastDay = report.isCurrentWeek ? nowKst().weekday - 1 : 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Row(
          label: l.reportsGridPtSession,
          sub: l.reportsGridPtPerWeek(report.sessionsBooked),
          cells: <Widget>[
            for (int d = 0; d < weekdayCountInGrid; d++)
              _PtCell(done: _ptOn(d)),
          ],
        ),
        const _RowGap(),
        _Row(
          label: l.reportsGridPersonal,
          sub: l.reportsGridPersonalUnit,
          cells: <Widget>[
            for (int d = 0; d < weekdayCountInGrid; d++)
              _ChipCell(
                text: d <= lastDay && d < days.length
                    ? l.reportsGridDoneOfAssigned(days[d].done, days[d].total)
                    : _dash,
                // 배정이 있는데 하나도 안 한 날만 붉게 짚는다. 배정이 없는
                // 날(쉬는 날)까지 붉으면 격자가 매주 절반쯤 빨갛고, 그러면
                // 빨강이 아무것도 가리키지 않는다.
                alarming:
                    d <= lastDay &&
                    d < days.length &&
                    days[d].total > 0 &&
                    days[d].done == 0,
              ),
          ],
        ),
        const _RowGap(),
        _Row(
          label: l.reportsGridMeals,
          sub: l.reportsGridMealsUnit,
          cells: <Widget>[
            for (int d = 0; d < weekdayCountInGrid; d++)
              _ChipCell(
                text: d <= lastDay && d < meals.length
                    ? l.reportsGridMealCount(meals[d])
                    : _dash,
                alarming: d <= lastDay && d < meals.length && meals[d] == 0,
              ),
          ],
        ),
        const _RowGap(),
        ReportCalorieLine(
          report: report,
          labelWidth: _labelWidth,
          baseline: calorieBaseline,
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 요일 머리글은 **맨 아래**에 둔다. 위에 두면 네 줄을 읽고 나서 다시
        // 위로 눈을 올려야 어느 요일인지 알 수 있다.
        Row(
          children: <Widget>[
            const SizedBox(width: _labelWidth),
            for (int d = 0; d < weekdayCountInGrid; d++)
              Expanded(
                child: Center(
                  child: Text(
                    names[d],
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ),
              ),
          ],
        ),
        // 합계 줄이 있던 자리다. `개인 운동 14/16회` 같은 수는 바로 위 격자를
        // 다시 세어 적은 것이라 새로 아는 것이 없었다. 이 자리에는 격자만
        // 봐서는 알 수 없는 것 — 이 회원의 평소와 견준 이번 주 — 을 둔다.
        if (recordedMean(report.caloriesWeek) != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          // 꺾은선이 시작하는 자리에서 함께 시작한다 — 그래프 아래에 붙은
          // 설명으로 읽히도록.
          Padding(
            padding: const EdgeInsetsDirectional.only(start: _labelWidth),
            child: _CalorieCompare(
              thisWeek: recordedMean(report.caloriesWeek)!,
              baseline: calorieBaseline,
            ),
          ),
        ],
      ],
    );
  }

  /// 그 요일에 PT 를 했는가.
  ///
  /// 데모·실서버 모두 세션의 요일을 따로 싣지 않는다. 주에 잡힌 횟수만 알므로,
  /// 실제로 나온 세션 수만큼 **앞에서부터** 채운다 — 어느 요일이었는지를
  /// 지어내지 않고, 몇 번이었는지만 말하는 표시다.
  bool _ptOn(int day) => day < report.sessionsDone;
}

/// 격자의 요일 칸 수. 월→일 일곱이다.
const int weekdayCountInGrid = 7;

/// 기록이 없는 칸.
const String _dash = '–';

/// 섭취 칼로리 줄 — 목표선 위아래로 흐르는 꺾은선. (#2232)
///
/// 값 글씨는 점 **위**에 적는다. 점만 그리면 정확한 수를 읽을 수 없고, 수만
/// 적으면 어느 날이 튀었는지가 안 보인다 — 둘 다 필요하다.
///
/// 적지 않은 날은 선을 잇지 않고 바닥에 옅은 점만 남긴다. 0 으로 이으면
/// "하루 굶었다" 가 되는데, 그건 우리가 모르는 사실이다.
class ReportCalorieLine extends StatelessWidget {
  /// Creates the row.
  const ReportCalorieLine({
    super.key,
    required this.report,
    required this.labelWidth,
    this.baseline,
  });

  final WeeklyReport report;

  /// 왼쪽 이름 칸의 폭 — 격자의 다른 줄과 같은 자리에서 시작해야 한다.
  final double labelWidth;

  /// 직전 넉 주의 하루 평균(kcal). 모르면 null.
  ///
  /// 선을 하나 더 긋지 않고 **숫자로** 적는다. 그래프에는 이미 목표선이
  /// 있어서, 회색 선을 더하면 볼 때마다 어느 쪽이 목표인지를 먼저 가려야
  /// 한다. 여기서 얻을 것은 `평소보다 높나 낮나` 한 문장뿐이고, 그건 선보다
  /// 수 한 줄이 빨리 읽힌다.
  final double? baseline;

  /// 꺾은선이 차지하는 높이.
  static const double _chartHeight = 72;

  /// 점 위 수치 한 칸의 폭·높이.
  static const double _valueLabelWidth = 56;
  static const double _valueLabelHeight = 16;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<int> calories = report.caloriesWeek;
    // 회원이 하루 목표를 적어 두지 않았으면 기본 목표로 되돌아간다. 요약과
    // ③ 판정이 이미 같은 기본값으로 말하고 있어서, 여기만 선을 지우면 글은
    // `기본 목표 2,000kcal 대비 부족` 이라는데 그래프에는 견줄 선이 없다.
    final int target = report.calorieTarget ?? calorieTargetKcal;
    final bool ownTarget = report.calorieTarget != null;
    final List<int?> values = <int?>[
      for (int d = 0; d < weekdayCountInGrid; d++)
        d < calories.length && calories[d] > 0 ? calories[d] : null,
    ];

    return Row(
      children: <Widget>[
        SizedBox(
          width: labelWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l.reportsGridCalories,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.text(
                  OnCareTypography.strong(OnCareTypography.bodySmall),
                ),
              ),
              Text(
                ownTarget
                    ? l.reportsGridCalorieTarget(formatNumber(target))
                    : l.reportsGridCalorieTargetDefault(formatNumber(target)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
          ),
        ),
        Expanded(
          // 수치는 **그 점 바로 위**에 선다. 위 줄에 따로 적으면 눈이 수와
          // 점을 세로로 짝지어야 하는데, 점이 오르내리니 그 거리가 날마다
          // 다르다.
          child: SizedBox(
            height: _chartHeight + _CaloriePainter.topInset,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final Size size = Size(
                  constraints.maxWidth,
                  _chartHeight + _CaloriePainter.topInset,
                );
                final _CalorieScale scale = _CalorieScale(
                  values: values,
                  target: target,
                  size: size,
                );
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CaloriePainter(
                          values: values,
                          target: target,
                          line: OnCareColors.lineStrong,
                          under: tokens.brand.primary,
                          over: OnCareColors.danger,
                        ),
                      ),
                    ),
                    for (int d = 0; d < weekdayCountInGrid; d++)
                      if (values[d] != null)
                        Positioned(
                          left: scale.xOf(d) - _valueLabelWidth / 2,
                          width: _valueLabelWidth,
                          top:
                              scale.yOf(values[d]!) -
                              _CaloriePainter.dot -
                              _valueLabelHeight,
                          height: _valueLabelHeight,
                          child: Center(
                            child: Text(
                              formatNumber(values[d]!),
                              maxLines: 1,
                              softWrap: false,
                              style: tokens
                                  .text(
                                    OnCareTypography.numeric(
                                      OnCareTypography.strong(
                                        OnCareTypography.caption,
                                      ),
                                    ),
                                  )
                                  .copyWith(
                                    color: values[d]! > target
                                        ? OnCareColors.danger
                                        : tokens.brand.primary,
                                  ),
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// `이번 주 평균 2,340kcal · 지난 4주 평균 2,180kcal ▲160`. (#2232)
///
/// 견줄 것이 없으면(새로 온 회원, 넉 주 내내 무기록) 이번 주 평균만 적는다.
/// `평소 0kcal` 은 모른다는 뜻이 아니라 굶었다는 뜻이라 적을 수 없다.
class _CalorieCompare extends StatelessWidget {
  const _CalorieCompare({required this.thisWeek, required this.baseline});

  final double thisWeek;
  final double? baseline;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle base = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textTertiary);
    final double? past = baseline;
    if (past == null) {
      return Text(
        l.reportsCalorieThisWeekAvg(formatNumber(thisWeek.round())),
        style: base,
      );
    }
    final int delta = (thisWeek - past).round();
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: l.reportsCalorieThisWeekAvg(formatNumber(thisWeek.round())),
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                .copyWith(color: OnCareColors.textSecondary),
          ),
          TextSpan(
            text:
                ' · '
                '${l.reportsCalorieBaselineAvg(kCalorieBaselineWeeks, formatNumber(past.round()))}',
            style: base,
          ),
          // 바뀐 양은 **초과와 다른 색**이다. 목표를 넘긴 날은 붉게 짚고
          // 있는데, 평소보다 늘었다는 것은 잘못이 아니라 달라짐일 뿐이다.
          // 같은 빨강을 쓰면 늘어난 주가 모두 잘못한 주로 읽힌다.
          if (delta != 0)
            TextSpan(
              text:
                  '  ${delta > 0 ? '▲' : '▼'}${formatNumber(delta.abs())}kcal',
              style: tokens
                  .text(
                    OnCareTypography.numeric(
                      OnCareTypography.strong(OnCareTypography.bodySmall),
                    ),
                  )
                  .copyWith(color: OnCareColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// 꺾은선·목표선·점을 그리는 붓.
class _CaloriePainter extends CustomPainter {
  const _CaloriePainter({
    required this.values,
    required this.target,
    required this.line,
    required this.under,
    required this.over,
  });

  /// 요일별 값. 적지 않은 날은 null 이다.
  final List<int?> values;

  /// 회원이 적어 둔 하루 목표. 없으면 목표선을 그리지 않는다.
  final int? target;

  final Color line;
  final Color under;
  final Color over;

  /// 점의 반지름.
  static const double dot = 5;

  /// 가장 높은 점 위에 수치가 설 자리.
  static const double topInset = 20;

  /// 기록이 없는 날에 남기는 옅은 점의 반지름.
  static const double _ghostDot = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final List<int> recorded = <int>[...values.whereType<int>()];
    if (recorded.isEmpty) return;

    final int? t = target;
    final _CalorieScale scale = _CalorieScale(
      values: values,
      target: t,
      size: size,
    );
    final double Function(num) yOf = scale.yOf;
    final double Function(int) xOf = scale.xOf;

    // 목표선을 먼저 — 점과 선이 그 위에 온다.
    if (t != null) {
      final Paint dash = Paint()
        ..color = OnCareColors.chartGoalLine
        ..strokeWidth = 1;
      final double y = yOf(t);
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
      }
    }

    // 적은 날끼리 잇는다. 사이에 빠진 날이 있으면 건너뛰어 잇지 않는다 —
    // 이으면 없는 날의 값을 눈이 지어낸다.
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = line;
    for (int d = 0; d + 1 < values.length; d++) {
      final int? a = values[d];
      final int? b = values[d + 1];
      if (a == null || b == null) continue;
      canvas.drawLine(
        Offset(xOf(d), yOf(a)),
        Offset(xOf(d + 1), yOf(b)),
        stroke,
      );
    }

    for (int d = 0; d < values.length; d++) {
      final int? v = values[d];
      if (v == null) {
        canvas.drawCircle(
          Offset(xOf(d), size.height - _ghostDot),
          _ghostDot,
          Paint()..color = OnCareColors.lineStrong,
        );
        continue;
      }
      canvas.drawCircle(
        Offset(xOf(d), yOf(v)),
        dot,
        Paint()..color = t != null && v > t ? over : under,
      );
    }
  }

  @override
  bool shouldRepaint(_CaloriePainter old) =>
      old.target != target || !listEquals(old.values, values);
}

/// 꺾은선의 눈금 — 붓과 점 위 수치가 **같은** 자리를 쓰도록 한 곳에서 잰다.
class _CalorieScale {
  _CalorieScale({
    required List<int?> values,
    required int? target,
    required this.size,
  }) : _count = values.length {
    final List<int> recorded = <int>[...values.whereType<int>()];
    // 값과 목표를 모두 담되, 아래로 조금 여유를 둬 점이 테두리에 붙지 않게
    // 한다. 위 여유는 수치가 설 [_CaloriePainter.topInset] 이 맡는다.
    final List<double> all = <double>[
      ...recorded.map((int v) => v.toDouble()),
      if (target != null) target.toDouble(),
    ];
    _low = all.isEmpty ? 0 : all.reduce(math.min) * 0.9;
    _high = all.isEmpty ? 0 : all.reduce(math.max);
  }

  final Size size;
  final int _count;
  late final double _low;
  late final double _high;

  /// 그 값의 세로 자리. 한 날만 적고 그 값이 목표와 같아 눈금이 한 점으로
  /// 눌리면 가운데 높이에 그린다.
  double yOf(num value) {
    const double top = _CaloriePainter.topInset;
    final double bottom = size.height - _CaloriePainter.dot;
    final double span = _high - _low;
    if (span <= 0) return (top + bottom) / 2;
    return bottom - ((value - _low) / span) * (bottom - top);
  }

  /// 그 요일 칸의 가운데.
  double xOf(int day) {
    final double step = size.width / _count;
    return step * day + step / 2;
  }
}

/// 두 목록이 같은가 — `package:flutter/foundation.dart` 의 것과 같은 일을
/// 하지만, 이 파일에서 쓰는 것은 이 한 곳뿐이다.
bool listEquals(List<int?> a, List<int?> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 이름·단위와 일곱 칸으로 이루어진 한 줄.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.sub, required this.cells});

  final String label;

  /// 이 줄이 무엇을 재는지 — `수행 / 배정`, `기록 횟수`.
  final String sub;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      children: <Widget>[
        SizedBox(
          width: ReportWeekGrid._labelWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.text(
                  OnCareTypography.strong(OnCareTypography.bodySmall),
                ),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
            ],
          ),
        ),
        for (final Widget cell in cells) Expanded(child: cell),
      ],
    );
  }
}

/// 줄 사이의 옅은 선 — 눈이 요일 축을 따라 세로로 내려갈 수 있게.
class _RowGap extends StatelessWidget {
  const _RowGap();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s8),
    child: AppDivider(),
  );
}

/// PT 를 한 날의 표시. 안 한 날은 가운뎃점이다.
///
/// 숫자를 적지 않는 까닭: 이 줄이 답하는 것은 `했다/안 했다` 뿐이고, 한 날에
/// `1` 이 서면 아래 줄의 `3 / 3회` 와 같은 종류의 수처럼 읽힌다.
class _PtCell extends StatelessWidget {
  const _PtCell({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Center(
      child: done
          ? Icon(
              Icons.check_rounded,
              size: OnCareSize.iconSmall,
              color: tokens.brand.primary,
            )
          : Text(
              '·',
              style: tokens
                  .text(OnCareTypography.body)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
    );
  }
}

/// 숫자 한 칸 — 옅은 알약. 걱정해야 하는 값은 붉은 알약이다.
///
/// 글씨만 두면 일곱 칸의 경계가 보이지 않아, 어느 수가 어느 요일인지 눈이
/// 아래 요일 줄까지 내려가 맞춰 봐야 한다.
class _ChipCell extends StatelessWidget {
  const _ChipCell({required this.text, required this.alarming});

  final String text;
  final bool alarming;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color ink = alarming ? OnCareColors.danger : OnCareColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s2),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: OnCareRadius.smAll,
          color: OnCareColors.onWhite(
            alarming ? OnCareColors.danger : tokens.brand.primary,
            OnCareAlpha.subtle,
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens
              .text(
                OnCareTypography.numeric(
                  OnCareTypography.strong(OnCareTypography.bodySmall),
                ),
              )
              .copyWith(color: text == _dash ? OnCareColors.textTertiary : ink),
        ),
      ),
    );
  }
}

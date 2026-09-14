import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays, weekdayCount, weekdayLabels;
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/bar_line_chart.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 주간 소모 칼로리 — 요일별 막대 위에 그 주의 꺾은선.
///
/// 막대 **높이**는 그날 소모 칼로리고, 막대 **안**은 그 칼로리를 유산소·근력·
/// 스트레칭이 각각 낸 몫으로 나눈 것이다. 식단의 칼로리 막대가 탄·단·지로
/// 쌓이는 것과 같은 규칙이다(#1177).
///
/// 예전에는 막대가 **이행률(%)** 이었다(#1289). 회원 앱은 세 유형을 한 축에서
/// 비교하는 값을 칼로리로 못 박았는데(#1276) 트레이너 앱만 이행률로 남아, 같은
/// 회원의 같은 한 주가 두 앱에서 다른 그림으로 읽혔다.
///
/// 축을 바꾸면서 얻는 것이 하나 더 있다. 이행률은 분모(배정)가 있어야 하는데
/// 배정에는 날짜가 없다 — `exercise_date` 를 채우는 생성 경로가 없다(#1288).
/// 소모 칼로리는 실제 기록만으로 성립하므로 그 의존이 사라진다.
///
/// 이행률 지표를 없애지는 않는다. 카드 제목 줄의 요약 칩과 4주 추이가 그대로
/// 들고 있고, `routine_ai` 도 저순응 판단에 계속 쓴다.
class WeeklyCompletionChart extends ConsumerWidget {
  /// Creates the chart.
  const WeeklyCompletionChart({super.key, required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final OnCareBrand brand = context.oncare.brand;
    final period = ref
        .watch(
          clientExercisePeriodProvider((
            clientId: report.client.id,
            period: ClientPeriod.week,
            day: report.weekStart,
          )),
        )
        .valueOrNull;
    // 막대의 재료가 통째로 이 응답에서 온다. 못 읽었을 때 0 으로 그리면 "그
    // 주에 아무것도 안 했다" 는 다른 말이 되므로 아무것도 그리지 않는다.
    if (period == null) return const SizedBox.shrink();

    final Map<String, ClientExerciseDay> byDate = <String, ClientExerciseDay>{
      for (final day in period.days) ymd(day.date): day,
    };
    ClientExerciseDay? dayAt(int i) =>
        byDate[ymd(report.weekStart.add(Duration(days: i)))];

    // 지난 날인데 기록이 없는 요일. 아직 오지 않은 날과 구분해서 그린다.
    final int elapsed = report.isCurrentWeek
        ? elapsedWeekdays(nowKst())
        : weekdayCount;
    final List<double?> values = <double?>[
      for (var i = 0; i < weekdayCount; i++)
        // 기록이 없는 날을 0kcal 로 그리면 '0kcal 소모' 라는 다른 뜻이 되고,
        // 평균에서 빠진 이유도 화면에서 사라진다.
        (dayAt(i)?.calories ?? 0) == 0 && i < elapsed
            ? null
            : (dayAt(i)?.calories ?? 0).toDouble(),
    ];
    final List<String> days = weekdayLabels(l);
    String kcal(double v) => '${v.round()}${l.unitKcal}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BarLineChart(
          key: const ValueKey<String>('reports-burn-chart'),
          values: values,
          labels: days,
          ceiling: _ceilingOf(values, period.dailyGoalCalories),
          format: kcal,
          emptyLabel: l.chartNoRecord,
          // 아직 오지 않은 요일은 이번 주에만 있다.
          pendingFrom: report.isCurrentWeek ? elapsed : null,
          segments: <List<BarSegment>?>[
            for (var i = 0; i < weekdayCount; i++) _segmentsOf(dayAt(i), brand),
          ],
          semanticsLabel: _semanticsLabel(
            l,
            title: l.reportsBurnByDay,
            // 0 은 기록 없음이라 읽지 않고, 아직 오지 않은 요일도 읽지 않는다.
            points: <String>[
              for (var i = 0; i < elapsed && i < weekdayCount; i++)
                if ((dayAt(i)?.calories ?? 0) != 0)
                  l.a11yChartPoint(
                    days[i],
                    kcal((dayAt(i)?.calories ?? 0).toDouble()),
                  ),
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        // 추정이라고 밝힌다. 트레이너가 이 수를 회원에게 말할 때 근거를 대야
        // 하는데, 중량은 계산에 넣지 않는다 — 같은 무게라도 사람마다 소모가
        // 달라 추정식에 넣으면 근거 없는 정밀도가 된다.
        Text(
          l.reportsBurnEstimateNote,
          style: context.oncare
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ],
    );
  }

  /// 그래프 하나를 한 문장으로. 읽을 값이 없으면 비어 있다고 말한다 — 빈
  /// 그래프를 말없이 두면 "값이 0" 인지 "아직 기록이 없는지"를 구분할 수 없다.
  static String _semanticsLabel(
    AppLocalizations l, {
    required String title,
    required List<String> points,
  }) => points.isEmpty
      ? l.a11yChartEmpty(title)
      : l.a11yChartSummary(title, points.join(', '));

  /// 눈금 끝 — 하루 목표와 그 주 최댓값 중 큰 쪽.
  ///
  /// 목표를 끝으로 삼아야 "목표를 채운 날은 막대가 꽉 찬다" 가 성립한다. 다만
  /// 목표를 넘긴 날의 막대는 잘리므로([BarLineChart] 가 눈금 끝에서 자른다)
  /// 실제 최댓값이 더 크면 그쪽을 쓴다 — 넘겼다는 사실이 사라지면 안 된다.
  /// 이행률이던 시절에는 이 값이 늘 100 이었다.
  static double _ceilingOf(List<double?> values, double dailyGoal) {
    final double observed = values.whereType<double>().fold<double>(
      0,
      math.max,
    );
    final double ceiling = math.max(
      dailyGoal > 0 ? dailyGoal : kDailyBurnKcal,
      observed,
    );
    return ceiling > 0 ? ceiling : kDailyBurnKcal;
  }

  /// 그날 칼로리를 유형별로 나눈 몫. 유형 기록이 없으면 null — 막대를 한 색으로
  /// 채운다(쌓을 것이 없는데 억지로 나누면 없는 구분을 보여 주는 셈이다).
  ///
  /// 분이 아니라 칼로리로 나눈다. 유형마다 분당 소모가 달라, 분 비중으로 나누면
  /// 근력 40분이 유산소 40분과 같은 몫을 차지한다. 색은 운동 유형 램프다(#1168).
  static List<BarSegment>? _segmentsOf(
    ClientExerciseDay? day,
    OnCareBrand brand,
  ) {
    if (day == null) return null;
    final segments = <BarSegment>[
      (value: day.cardioCalories.toDouble(), color: brand.exerciseCardio),
      (value: day.strengthCalories.toDouble(), color: brand.exerciseStrength),
      (
        value: day.stretchingCalories.toDouble(),
        color: brand.exerciseStretching,
      ),
    ];
    return segments.every((s) => s.value <= 0) ? null : segments;
  }
}

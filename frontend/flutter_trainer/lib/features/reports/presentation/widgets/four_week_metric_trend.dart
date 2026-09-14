import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/week_trend_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 선택한 영양 지표의 최근 4주 주간 평균 — 운동 카드의 같은 블록과 짝이다.
///
/// 이번 주 꺾은선은 "이번 주에 언제 튀었나"만 말한다. 트레이너가 정말 알고
/// 싶은 건 **코칭이 먹히고 있나**이고, 그건 주 단위 평균 넷을 나란히 놓아야
/// 보인다(#754).
///
/// 새로 받아 오는 값이 없다 — 운동 카드가 이미 지난 세 주의 리포트를 보고
/// 있고, 그 리포트가 각자 자기 주의 계열을 들고 있다.
class FourWeekMetricTrend extends ConsumerWidget {
  const FourWeekMetricTrend({
    super.key,
    required this.report,
    required this.label,
    required this.values,
    required this.goal,
    required this.unit,
  });

  final WeeklyReport report;

  /// 지표 이름(칼로리·나트륨·당류).
  final String label;

  /// 한 주의 리포트에서 이 지표의 요일별 계열을 꺼내는 방법.
  final List<num> Function(WeeklyReport) values;

  /// 목표. 눈금과 주의 색의 기준을 겸한다.
  final double goal;

  /// 값 뒤에 붙는 단위.
  final String unit;

  /// 값 칸 너비 — `2,288kcal` 처럼 단위가 붙은 값이 한 줄에 들어가는 폭.
  static const double _valueWidth = 62;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final weeks = <AsyncValue<WeeklyReport>>[
      for (var offset = 3; offset >= 0; offset--)
        ref.watch(
          weeklyReportProvider((
            client: report.client,
            weekStart: report.weekStart.subtract(Duration(days: 7 * offset)),
          )),
        ),
    ];
    final labels = <String>[
      l.reportsWeeksAgo(3),
      l.reportsWeeksAgo(2),
      l.reportsLastWeek,
      report.isCurrentWeek ? l.reportsThisWeek : l.reportsSelectedWeek,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 목표 표기는 적지 않는다. 눈금 위 세로선과 초과한 주의 빨간 막대가
        // 이미 같은 말을 하고 있었고, 줄 끝의 `│ 목표 2,000mg` 은 그 세로선과
        // 겹쳐 읽혀 오히려 눈금처럼 보였다(#1177).
        Text(
          '${l.reportsRecentWeeks} · $label',
          style: context.oncare
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: OnCareColors.textTertiary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        for (var i = 0; i < weeks.length; i++)
          () {
            final week = weeks[i].valueOrNull;
            // 기록한 날만 평균한다 — 아직 오지 않은 날을 0 으로 세면 이번 주가
            // 늘 나아 보인다. 화면 곳곳이 같은 규칙을 쓴다.
            final mean = week == null ? null : recordedMean(values(week));
            return WeekTrendBar(
              label: labels[i],
              // 눈금 끝이 곧 목표다. 막대가 트랙을 다 채웠다는 것이 목표에
              // 닿았다는 뜻이 되고, 넘긴 주는 꽉 찬 빨간 막대로 남는다(#1177).
              fraction: mean == null ? null : mean / goal,
              // 정수로 반올림한 평균이라 천 단위 콤마만 붙는다.
              text: mean == null ? '-' : '${formatNumber(mean.round())}$unit',
              loading: weeks[i].isLoading,
              current: i == weeks.length - 1,
              warn: mean != null && mean > goal,
              valueWidth: _valueWidth,
            );
          }(),
      ],
    );
  }
}

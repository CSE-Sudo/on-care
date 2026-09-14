import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/week_trend_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 최근 4주 이행률 — 얇은 가로 막대 넷.
///
/// 예전에는 세로 막대 네 개짜리 카드였다. 값이 넷뿐인데 카드 하나를 통째로
/// 썼다. 가로로 눕히면 길이를 바로 견줄 수 있어 자리를 훨씬 덜 쓰고도 흐름이
/// 읽힌다(#754).
///
/// 지난 주 대비 변화는 적지 않는다 — 위 '이번 주 vs 지난 주' 카드가 이미 같은
/// 값을 말한다. 이 블록이 더 말해 주는 것은 **네 주의 흐름**이다: 두 주만 보면
/// 나아지는 것처럼 보이는 주도 네 주를 늘어놓으면 오르내림이 드러난다.
class FourWeekComplianceTrend extends ConsumerWidget {
  const FourWeekComplianceTrend({super.key, required this.report});

  final WeeklyReport report;

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
    // 폭은 위 요일별 그래프에 맞춘다. 좁게 묶으면 같은 카드 안에서 두 블록이
    // 남남처럼 보이고, 길게 뻗을수록 84% 와 87% 의 차이가 눈에 들어온다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l.reportsRecentWeeks,
          style: context.oncare
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: OnCareColors.textTertiary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        for (var i = 0; i < weeks.length; i++)
          () {
            final value = weeks[i].valueOrNull?.completionAvg;
            return WeekTrendBar(
              label: labels[i],
              fraction: value == null ? null : value / 100,
              text: value == null ? '-' : '$value%',
              loading: weeks[i].isLoading,
              current: i == weeks.length - 1,
              // 낮은 주를 빨강으로 칠하지 않는다. 이 앱에서 빨강은 `목표 초과`
              // 라는 다른 뜻으로 이미 쓰이고 있어(#690·#913), 이행률이 낮은 주가
              // 나트륨을 넘긴 주와 같은 색이 되면 둘이 같은 일처럼 읽힌다.
              // 낮다는 사실은 막대 길이와 값이 말한다(#1177).
            );
          }(),
      ],
    );
  }
}

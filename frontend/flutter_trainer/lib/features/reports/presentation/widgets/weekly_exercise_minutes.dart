import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 그 주에 **실제로 운동한 시간** — 유산소·근력·스트레칭으로 쌓은 한 줄.
///
/// 이행률은 "배정한 루틴을 얼마나 했나"만 말한다. 고객 화면의 운동 탭은 그와
/// 별개로 유형별 운동 시간과 주간 목표를 들고 있는데(#943·#1015), 리포트에는
/// 그 값이 어디에도 없어 트레이너가 탭을 오가며 맞춰 봐야 했다. 같은 주를
/// 말하는 두 값이라 같은 카드에 둔다(#1177).
class WeeklyExerciseMinutes extends ConsumerWidget {
  /// Creates the weekly minutes row.
  const WeeklyExerciseMinutes({super.key, required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ClientPeriodKey key = (
      clientId: report.client.id,
      period: ClientPeriod.week,
      day: report.weekStart,
    );
    final period = ref.watch(clientExercisePeriodProvider(key)).valueOrNull;
    // 못 읽었으면 아무것도 그리지 않는다. 이 줄은 카드의 곁가지라, 실패를
    // 알리는 문구가 이행률 그래프보다 눈에 띄면 안 된다.
    if (period == null || period.totalMinutes <= 0) {
      return const SizedBox.shrink();
    }
    final int total = period.totalMinutes;
    final int goal = period.weeklyGoalMinutes;
    // 유형 셋은 다른 운동 그래프와 같은 램프다(#1168). 목표가 없는 `기타` 는
    // 램프 밖의 중립 회색이다.
    final parts = <({String label, int minutes, Color color})>[
      (
        label: l.routineTypeCardio,
        minutes: period.totalCardioMinutes,
        color: tokens.brand.exerciseCardio,
      ),
      (
        label: l.routineTypeStrength,
        minutes: period.totalStrengthMinutes,
        color: tokens.brand.exerciseStrength,
      ),
      (
        label: l.routineTypeStretching,
        minutes: period.totalStretchingMinutes,
        color: tokens.brand.exerciseStretching,
      ),
      (
        label: l.routineTypeOther,
        minutes: period.totalOtherMinutes,
        color: OnCareColors.lineStrong,
      ),
    ].where((p) => p.minutes > 0).toList(growable: false);
    // 눈금 끝은 목표와 실제 중 큰 쪽. 목표를 넘긴 주의 막대가 잘리면 넘겼다는
    // 사실이 사라진다.
    final int ceiling = goal > total ? goal : total;
    final TextStyle heading = tokens
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textTertiary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(l.clientTrendWorkoutMinutes, style: heading)),
            Text(
              goal > 0
                  ? '${l.minutesShort(total)} · ${l.reportsGoalOf(l.minutesShort(goal))}'
                  : l.minutesShort(total),
              style: OnCareTypography.numeric(
                tokens.text(OnCareTypography.strong(OnCareTypography.caption)),
              ).copyWith(color: OnCareColors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s4),
        ClipRRect(
          borderRadius: OnCareRadius.pillAll,
          child: SizedBox(
            // 리포트 탭의 가로 막대는 모두 진행 막대와 같은 굵기다.
            height: OnCareSize.progressBar,
            child: Row(
              // 세로로 늘려야 한다 — 가운데 정렬(기본값)이면 자식이 스스로
              // 높이를 못 정해 막대가 통째로 사라진다.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final part in parts)
                  Expanded(
                    flex: part.minutes,
                    child: ColoredBox(color: part.color),
                  ),
                // 목표까지 남은 자리는 빈 트랙으로 둔다 — 막대가 늘 꽉 차면
                // 목표를 채웠는지가 길이에서 사라진다.
                if (ceiling > total)
                  Expanded(
                    flex: ceiling - total,
                    child: const ColoredBox(color: OnCareColors.surfaceInput),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Wrap(
          spacing: OnCareSpacing.s12,
          runSpacing: OnCareSpacing.s4,
          children: <Widget>[
            for (final part in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppChartSwatch(color: part.color),
                  const SizedBox(width: OnCareSpacing.s4),
                  Text(
                    '${part.label} ${l.minutesShort(part.minutes)}',
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

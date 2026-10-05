/// 개인운동 이행 카드 — 회원 상세 운동 탭과 프로그램 화면이 같은 카드를
/// 쓴다(#2508, #3004). 두 화면이 같은 기간에 같은 그림으로 같은 말을 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/clients/data/repositories/routine_days_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_days.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_routine_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// `이번 주` 개인운동 이행 — 프로그램 화면 `개인운동 이행` 카드와 같은 그림을
/// 이번 주 월~일 7칸으로 그린다. (#2508)
///
/// 위 링은 유형별 시간이 목표에 닿았는지를 말할 뿐, "보낸 개인운동을 했나" 는
/// 펼친 날을 하나씩 열어야 알았다. 두 화면이 같은 단계 색으로 같은 말을 한다.
/// 이번 주 오늘까지 걸린 개인운동이 하나도 없으면 두지 않는다.
class ClientWeekRoutineAdherenceCard extends ConsumerWidget {
  /// Creates the `이번 주` card for [clientId].
  const ClientWeekRoutineAdherenceCard({
    super.key,
    required this.clientId,
    this.cardKey = const ValueKey<String>('workout-routine-adherence-card'),
    this.padding = const EdgeInsets.only(bottom: OnCareSpacing.s16),
  });

  /// The member whose assigned routines are drawn.
  final String clientId;

  /// The card's key — each screen names its own.
  final Key cardKey;

  /// Space around the card; the two screens stack it differently.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RoutineDaysKey key = routineDaysKeyNow(clientId);
    final RoutineDays? days = ref
        .watch(clientRoutineDaysProvider(key))
        .valueOrNull;
    final DateTime monday = clientMondayOf(key.day);
    if (days == null ||
        !days
            .between(monday, key.day)
            .any((RoutineDay d) => d.items.isNotEmpty)) {
      return const SizedBox.shrink();
    }
    final TextStyle caption = context.oncare
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textSecondary);
    return Padding(
      padding: padding,
      child: AppCard(
        key: cardKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 했나(요약)는 제목 줄 오른쪽, 무엇을 보냈나는 칸 아래 — 두 말을
            // 한 줄에 잇지 않는다. 좁으면 요약이 다음 줄로 넘어간다.
            AppSectionHeader(
              title: l.coachRoutineAdherenceTitle,
              icon: AppIcons.personalRoutine,
              trailingFit: AppSectionTrailingFit.wrap,
              trailing: Text(
                routineWeekSummary(l, days, monday, key.day),
                key: const ValueKey<String>(
                  'workout-routine-adherence-summary',
                ),
                style: caption,
              ),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            ClientRoutineAdherenceStrip.week(
              days: days,
              monday: monday,
              today: key.day,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            for (final (int i, String line) in routineWeekSentLines(
              l,
              days,
              monday,
              key.day,
            ).indexed)
              Text(
                line,
                key: ValueKey<String>('workout-routine-adherence-sent-$i'),
                style: caption,
              ),
          ],
        ),
      ),
    );
  }
}

/// 링 한 칸의 최소 폭 — 링과 `8/18(화) 보냄` 이 들어갈 만큼.
const double _ringSlotMin = 104;

/// 링 지름.
const double _ringSize = 72;

/// `전체` 개인운동 이행 — 보낸 개인운동 기간마다 링 하나. (#2508)
///
/// 위 막대는 주마다 얼마나 움직였나를 말할 뿐, "보낸 지도를 따라왔나" 는
/// 날을 하나씩 열어야 알았다. 달력 주가 아니라 **보낸 기간** 단위로 묶어,
/// 트레이너가 보낸 것마다 얼마나 했는지와 그 흐름을 본다. 링을 고르면 그
/// 7일이 `이번 주` 카드와 같은 칸으로 펼쳐진다. 링이 폭보다 많으면 위 막대처럼
/// 옆으로 스크롤한다(최근 것이 기본).
class ClientAllRoutineAdherenceCard extends ConsumerStatefulWidget {
  /// Creates the `전체` card for [clientId].
  const ClientAllRoutineAdherenceCard({
    super.key,
    required this.clientId,
    this.cardKey = const ValueKey<String>('workout-routine-all-card'),
    this.padding = const EdgeInsets.only(bottom: OnCareSpacing.s16),
  });

  /// The member whose sent routines are drawn.
  final String clientId;

  /// The card's key — each screen names its own.
  final Key cardKey;

  /// Space around the card; the two screens stack it differently.
  final EdgeInsets padding;

  @override
  ConsumerState<ClientAllRoutineAdherenceCard> createState() =>
      _ClientAllRoutineAdherenceCardState();
}

class _ClientAllRoutineAdherenceCardState
    extends ConsumerState<ClientAllRoutineAdherenceCard> {
  final ScrollController _scroll = ScrollController();

  /// 처음 한 번 최근 링(오른쪽 끝)으로 옮겼나.
  bool _placed = false;

  /// 고른 링의 시작일. 비우면 가장 최근 링이다.
  DateTime? _selected;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RoutineDaysKey key = routineDaysKeyNow(widget.clientId);
    final RoutineDays? days = ref
        .watch(clientRoutineDaysProvider(key))
        .valueOrNull;
    if (days == null) return const SizedBox.shrink();
    final List<RoutineGroupAdherence> rings = routineGroupAdherence(
      days,
      key.day,
    );
    if (rings.isEmpty) return const SizedBox.shrink();
    final RoutineGroupAdherence selected = rings.lastWhere(
      (RoutineGroupAdherence r) => r.group.activeFrom == _selected,
      orElse: () => rings.last,
    );
    final List<RoutineDayGroup> ongoing = <RoutineDayGroup>[
      for (final RoutineDayGroup g in days.groupsOf(
        days.routines.map((RoutineDayRoutine r) => r.id),
      ))
        // 기한 없는 따로 배정 중 오늘도 걸린 것만 — 끝난 일반 배정까지 `계속` 으로
        // 적으면 지난 것을 지금 것처럼 말한다.
        if (!g.personal && g.activeOn(key.day)) g,
    ];
    final TextStyle caption = context.oncare
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textSecondary);
    return Padding(
      padding: widget.padding,
      child: AppCard(
        key: widget.cardKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppSectionHeader(
              title: l.coachRoutineAdherenceTitle,
              icon: AppIcons.personalRoutine,
              trailingFit: AppSectionTrailingFit.wrap,
              // `7번 보냄` 옆에 평균을 연한 파랑 태그로 — 이 카드가 답하는
              // 말이 평균이다.
              trailing: Row(
                key: const ValueKey<String>('workout-routine-all-summary'),
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(l.workoutRoutineAllCount(rings.length), style: caption),
                  const SizedBox(width: OnCareSpacing.s8),
                  AppTag(
                    key: const ValueKey<String>('workout-routine-all-average'),
                    label: switch (routineAllAverage(rings)) {
                      final int avg => l.workoutRoutineAllAverage(avg),
                      null => l.workoutRoutineAllFirstDay,
                    },
                    tone: AppTagTone.brand,
                  ),
                ],
              ),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // 다 들어가면 폭을 나눠 채운다. 넘치면 위 `전체` 막대처럼
                // 옆으로 스크롤하고, 처음에는 최근 링이 보이게 오른쪽 끝에
                // 둔다 — 화살표는 두지 않는다(같은 탭의 두 그래프가 같은
                // 방식으로 넘어간다).
                final double viewport = constraints.maxWidth;
                final int fit = (viewport / _ringSlotMin).floor().clamp(
                  1,
                  rings.length,
                );
                final double slot = viewport / fit;
                final bool scrolls = fit < rings.length;
                if (scrolls) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_scroll.hasClients || _placed) return;
                    _placed = true;
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  });
                }
                return SingleChildScrollView(
                  key: const ValueKey<String>('workout-routine-all-rings'),
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: scrolls
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: <Widget>[
                      for (final RoutineGroupAdherence r in rings)
                        SizedBox(
                          width: slot,
                          child: _RoutineRing(
                            ring: r,
                            // 하나뿐이면 고를 것이 없다 — 폭 전체에 선택
                            // 배경을 깔면 빈 회색 상자가 된다.
                            selected:
                                rings.length > 1 && identical(r, selected),
                            onTap: () =>
                                setState(() => _selected = r.group.activeFrom),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: OnCareSpacing.s12),
            // 고른 링의 7일 — `이번 주` 카드와 같은 칸이다.
            ClientRoutineAdherenceStrip.period(
              days: days.only(<String>{
                for (final RoutineDayRoutine r in selected.group.routines) r.id,
              }),
              group: selected.group,
              today: key.day,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            Text(
              // 보낸 날은 고른 링이 말한다 — 여기서는 무엇을 보냈나만.
              routineGroupNames(l, selected.group),
              key: const ValueKey<String>('workout-routine-all-names'),
              style: caption,
            ),
            for (final RoutineDayGroup g in ongoing)
              Text(
                l.workoutRoutineWeekOngoing(routineGroupNames(l, g)),
                style: caption,
              ),
          ],
        ),
      ),
    );
  }
}

/// 링 하나 — 가운데 완료율, 아래 보낸 날 · 끝난 날(또는 진행 중 며칠째).
///
/// 완료 수(`9/14개`)는 적지 않는다 — 가운데 % 가 같은 말을 한다.
class _RoutineRing extends StatelessWidget {
  const _RoutineRing({
    required this.ring,
    required this.selected,
    required this.onTap,
  });

  final RoutineGroupAdherence ring;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RoutineDayGroup g = ring.group;
    final int? percent = ring.percent;
    final DateTime? last = g.lastDay;
    final TextStyle caption = context.oncare
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textSecondary);
    final String key = '${g.activeFrom.month}-${g.activeFrom.day}';
    return Semantics(
      button: true,
      selected: selected,
      label: percent == null
          ? null
          : l.workoutRoutineAllRing(routineDayLabel(l, g.sentOn), percent),
      child: Material(
        color: selected ? OnCareColors.surfacePage : Colors.transparent,
        borderRadius: OnCareRadius.mdAll,
        child: InkWell(
          key: ValueKey<String>('workout-routine-all-ring-$key'),
          borderRadius: OnCareRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: OnCareSpacing.s8,
              horizontal: OnCareSpacing.s4,
            ),
            child: Column(
              children: <Widget>[
                SizedBox.square(
                  dimension: _ringSize,
                  child: AppRingGauge(
                    value: (percent ?? 0) / 100,
                    color: context.oncare.brand.primary,
                    stroke: 8,
                    child: Center(
                      child: Text(
                        percent == null ? '-' : '$percent%',
                        style: OnCareTypography.numeric(
                          context.oncare.text(
                            OnCareTypography.strong(OnCareTypography.body),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  l.workoutRoutineAllSent(routineDayLabel(l, g.sentOn)),
                  style: context.oncare.text(
                    OnCareTypography.strong(OnCareTypography.caption),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // 진행 중은 `이번 주` 칸의 오늘처럼 브랜드색 알약으로 알린다
                // — 회색 글자 한 줄로는 끝난 링과 구분되지 않았다.
                if (ring.ongoing)
                  Container(
                    key: ValueKey<String>('workout-routine-all-ongoing-$key'),
                    margin: const EdgeInsets.symmetric(
                      vertical: OnCareSpacing.s2,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: OnCareSpacing.s8,
                    ),
                    decoration: BoxDecoration(
                      color: context.oncare.brand.primary,
                      borderRadius: OnCareRadius.pillAll,
                    ),
                    child: Text(
                      l.workoutRoutineAllOngoing(ring.day),
                      style: context.oncare
                          .text(
                            OnCareTypography.strong(OnCareTypography.caption),
                          )
                          .copyWith(color: OnCareColors.textOnFill),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Text(
                    last == null
                        ? ''
                        // 7일을 다 채우지 못하고 바뀐 묶음은 걸린 일수를 함께
                        // 적는다 — 칸의 빈 테두리와 같은 말이다.
                        : last.difference(g.activeFrom).inDays + 1 < 7
                        ? l.workoutRoutineAllUntilShort(
                            routineDayLabel(l, last),
                            last.difference(g.activeFrom).inDays + 1,
                          )
                        : l.workoutRoutineAllUntil(routineDayLabel(l, last)),
                    style: caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

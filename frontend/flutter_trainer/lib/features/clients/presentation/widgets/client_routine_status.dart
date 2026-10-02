import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_trainer/features/clients/domain/entities/routine_days.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show weekdayLabels;
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 개인운동 매일 완료 현황의 공통 조각 — 날짜 표기, 하루 완료 단계, 프로그램
/// 화면 `개인운동 이행` 카드. (#2508, #2509)
///
/// 하루 단위 칸은 그날 완료 비율의 진하기다(배정 없음 · 하나도 안 함 · 일부 ·
/// 절반 이상 · 모두).

/// `9/29(화)` — 머리 줄과 오늘 목록 오른쪽에 쓰는 날짜.
String routineDayLabel(AppLocalizations l, DateTime d) =>
    l.workoutRoutineDay(d.month, d.day, weekdayLabels(l)[d.weekday - 1]);

/// 그날 완료 비율의 단계. 걸린 것이 없으면 [RoutineLevel.none].
enum RoutineLevel { none, zero, some, half, all }

/// [day] 의 단계.
RoutineLevel routineLevelOf(RoutineDay? day) {
  final double? ratio = day?.ratio;
  if (ratio == null) return RoutineLevel.none;
  if (ratio >= 1) return RoutineLevel.all;
  if (ratio >= 0.5) return RoutineLevel.half;
  if (ratio > 0) return RoutineLevel.some;
  return RoutineLevel.zero;
}

/// 단계 색 — `전체` 달력과 프로그램 화면 카드가 같은 단계를 쓴다.
Color routineLevelFill(BuildContext context, RoutineLevel level) {
  final Color brand = context.oncare.brand.primary;
  return switch (level) {
    RoutineLevel.none => OnCareRecordColors.empty,
    RoutineLevel.zero => OnCareColors.danger.withValues(alpha: 0.2),
    RoutineLevel.some => brand.withValues(alpha: 0.25),
    RoutineLevel.half => brand.withValues(alpha: 0.55),
    RoutineLevel.all => brand,
  };
}

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

const double _cellGap = OnCareSpacing.s4;

/// 프로그램 화면 `개인운동 이행` 칸의 최대 한 변 — `6/6` 이 들어갈 만큼만.
const double _stripCellMax = 36;

TextStyle _caption(BuildContext context, {Color? color}) => context.oncare
    .text(OnCareTypography.caption)
    .copyWith(color: color ?? OnCareColors.textSecondary);

/// 프로그램 화면 `개인운동 이행` — 지금 걸린 개인운동을 보낸 날부터 7칸. (#2509)
///
/// 칸마다 `완료 수/그날 걸린 수`(기한 없는 따로 배정 포함)를 적고 완료 비율로
/// 진하기를 준다(`전체` 달력과 같은 단계). 오늘은 빈 테두리, 오지 않은 날은
/// 빈칸이다. 지금 걸린 개인운동이 없으면 그리지 않는다 — 부르는 쪽이
/// [RoutineDays.currentPersonal] 로 가린다.
class ClientRoutineAdherenceStrip extends StatelessWidget {
  /// Creates the strip.
  const ClientRoutineAdherenceStrip({
    super.key,
    required this.days,
    required this.group,
    required this.today,
  });

  final RoutineDays days;
  final RoutineDayGroup group;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime start = group.activeFrom;
    final List<DateTime> dates = <DateTime>[
      for (int i = 0; i < 7; i++) _addDays(start, i),
    ];
    final List<String> labels = weekdayLabels(l);
    final List<RoutineDay> past = days.between(start, _addDays(today, -1));
    final int full = past
        .where(
          (RoutineDay d) => d.items.isNotEmpty && d.completed == d.items.length,
        )
        .length;
    RoutineDay? lateDay;
    for (final RoutineDay d in past) {
      if (d.items.any(
        (RoutineDayItem i) => i.status == RoutineDayStatus.late,
      )) {
        lateDay = d;
        break;
      }
    }
    final String summary = past.isEmpty
        ? l.coachRoutineAdherenceFirstDay
        : <String>[
            l.coachRoutineAdherenceSummary(past.length, full),
            if (lateDay case final RoutineDay d)
              l.coachRoutineAdherenceLate(
                labels[d.date.weekday - 1],
                d.items
                    .where(
                      (RoutineDayItem i) => i.status == RoutineDayStatus.late,
                    )
                    .length,
              ),
          ].join(' · ');
    return Column(
      key: const ValueKey<String>('program-routine-adherence'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 칸은 작게 둔다 — 넓은 열에서 폭을 채우면 상자가 지나치게 커진다.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double cell = math.min(
              _stripCellMax,
              (constraints.maxWidth - _cellGap * 6) / 7,
            );
            return Row(
              children: <Widget>[
                for (final (int i, DateTime d) in dates.indexed) ...<Widget>[
                  if (i > 0) const SizedBox(width: _cellGap),
                  SizedBox(
                    width: cell,
                    child: _AdherenceCell(date: d, today: today, days: days),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Text(
          summary,
          key: const ValueKey<String>('program-routine-adherence-summary'),
          style: _caption(context),
        ),
      ],
    );
  }
}

class _AdherenceCell extends StatelessWidget {
  const _AdherenceCell({
    required this.date,
    required this.today,
    required this.days,
  });

  final DateTime date;
  final DateTime today;
  final RoutineDays days;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool future = date.isAfter(today);
    final bool isToday = !future && !date.isBefore(today);
    final RoutineDay? day = future ? null : days.dayOf(date);
    final int total = day?.items.length ?? 0;
    final int done = day?.completed ?? 0;
    final RoutineLevel level = routineLevelOf(day);
    // 오늘은 끝나지 않았다 — 진하기 대신 빈 테두리로 두고 수만 적는다.
    final Color fill = future || isToday
        ? Colors.transparent
        : routineLevelFill(context, level);
    final bool strong = !isToday && level == RoutineLevel.all;
    final String? text = future || total == 0 ? null : '$done/$total';
    final Widget box = AspectRatio(
      aspectRatio: 1,
      child: Container(
        key: ValueKey<String>(
          'program-routine-adherence-${date.month}-${date.day}',
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: OnCareRadius.smAll,
          border: isToday || future
              ? Border.all(
                  color: isToday
                      ? OnCareColors.lineStrong
                      : OnCareColors.lineSubtle,
                )
              : null,
        ),
        child: text == null
            ? null
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  style: OnCareTypography.numeric(
                    context.oncare
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(
                          color: strong
                              ? OnCareColors.textOnFill
                              : OnCareColors.textPrimary,
                        ),
                  ),
                ),
              ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          weekdayLabels(l)[date.weekday - 1],
          style: _caption(context, color: OnCareColors.textTertiary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        if (text == null)
          box
        else
          Semantics(
            label: l.coachRoutineAdherenceCell(
              routineDayLabel(l, date),
              done,
              total,
            ),
            child: box,
          ),
      ],
    );
  }
}

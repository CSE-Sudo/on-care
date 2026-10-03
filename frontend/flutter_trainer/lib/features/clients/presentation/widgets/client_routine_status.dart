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

/// `개인운동 이행` — [start] 부터 7칸. (#2508, #2509)
///
/// 칸마다 `완료 수/그날 걸린 수`(기한 없는 따로 배정 포함)를 적고 완료 비율로
/// 진하기를 준다(`전체` 달력과 같은 단계). 오늘은 테두리를 두르고 한 만큼만
/// 칠하며(아직 0개면 빈칸, 빨강 없음), 오지 않은 날은
/// 빈칸이다.
///
/// 두 자리가 같은 그림을 쓴다 — 프로그램 화면은 지금 걸린 개인운동을 보낸
/// 날부터([ClientRoutineAdherenceStrip.new]), 운동 탭 `이번 주` 는 그 주
/// 월요일부터([ClientRoutineAdherenceStrip.week]) 7칸이다. 부르는 쪽이 그릴
/// 것이 없는 회원을 가린다.
class ClientRoutineAdherenceStrip extends StatelessWidget {
  /// 프로그램 화면 — [group] 을 보낸 날부터 7칸, 칸은 작은 정사각형이다.
  ClientRoutineAdherenceStrip({
    super.key,
    required this.days,
    required RoutineDayGroup group,
    required this.today,
  }) : start = group.activeFrom,
       fillWidth = false,
       showSummary = true,
       keyPrefix = 'program-routine-adherence';

  /// 운동 탭 `이번 주` — [monday] 부터 일요일까지, 칸이 카드 폭을 채운다.
  /// 요약은 칸 아래가 아니라 카드 제목 줄에 선다([routineWeekSummary]).
  const ClientRoutineAdherenceStrip.week({
    super.key,
    required this.days,
    required DateTime monday,
    required this.today,
  }) : start = monday,
       fillWidth = true,
       showSummary = false,
       keyPrefix = 'workout-routine-adherence';

  final RoutineDays days;
  final DateTime today;

  /// 첫 칸의 날.
  final DateTime start;

  /// 칸이 폭을 나눠 채우는가. 거짓이면 [_stripCellMax] 한 변의 정사각형이다.
  final bool fillWidth;

  /// 칸 아래에 요약 한 줄을 두는가.
  final bool showSummary;

  /// 카드·칸·요약 키의 앞부분.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<DateTime> dates = <DateTime>[
      for (int i = 0; i < 7; i++) _addDays(start, i),
    ];
    final _Stats stats = _Stats.of(days, start, today);
    final String summary = stats.past == 0
        ? l.coachRoutineAdherenceFirstDay
        : <String>[
            l.coachRoutineAdherenceSummary(stats.past, stats.full),
            if (stats.lateDay case final RoutineDay d)
              l.coachRoutineAdherenceLate(
                weekdayLabels(l)[d.date.weekday - 1],
                stats.lateCount,
              ),
          ].join(' · ');
    return Column(
      key: ValueKey<String>(keyPrefix),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 프로그램 화면은 칸을 작게 둔다 — 넓은 열에서 정사각형이 폭을 채우면
        // 상자가 지나치게 커진다. 운동 탭은 폭을 나눠 채우고 높이만 그대로 둔다
        // — 카드 오른쪽에 빈칸이 남지 않게.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double share = (constraints.maxWidth - _cellGap * 6) / 7;
            final double cell = fillWidth
                ? share
                : math.min(_stripCellMax, share);
            return Row(
              children: <Widget>[
                for (final (int i, DateTime d) in dates.indexed) ...<Widget>[
                  if (i > 0) const SizedBox(width: _cellGap),
                  SizedBox(
                    width: cell,
                    child: _AdherenceCell(
                      date: d,
                      today: today,
                      days: days,
                      keyPrefix: keyPrefix,
                      height: fillWidth ? _stripCellMax : null,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        if (showSummary) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            summary,
            key: ValueKey<String>('$keyPrefix-summary'),
            style: _caption(context),
          ),
        ],
      ],
    );
  }
}

/// [start]~어제 중 개인운동이 걸린 날의 셈.
class _Stats {
  const _Stats({
    required this.past,
    required this.full,
    required this.lateDay,
    required this.lateCount,
  });

  factory _Stats.of(RoutineDays days, DateTime start, DateTime today) {
    // 걸린 것이 없는 날은 세지 않는다 — 주 가운데 보낸 개인운동이면 그 앞
    // 요일은 아직 할 것이 없던 날이다.
    final List<RoutineDay> past = days
        .between(start, _addDays(today, -1))
        .where((RoutineDay d) => d.items.isNotEmpty)
        .toList();
    bool isLate(RoutineDayItem i) => i.status == RoutineDayStatus.late;
    final RoutineDay? lateDay = past
        .where((RoutineDay d) => d.items.any(isLate))
        .firstOrNull;
    return _Stats(
      past: past.length,
      full: past.where((RoutineDay d) => d.completed == d.items.length).length,
      lateDay: lateDay,
      lateCount: lateDay?.items.where(isLate).length ?? 0,
    );
  }

  /// 지난 날 중 개인운동이 걸린 날 수.
  final int past;

  /// 그중 모두 완료한 날 수.
  final int full;

  /// 다음 날 이후에 체크한 것이 있는 첫날과 그날 그런 것의 수.
  final RoutineDay? lateDay;
  final int lateCount;
}

/// 운동 탭 `이번 주` 제목 줄 오른쪽 요약 — `3일 중 모두 완료 2일 · 수 1건
/// 늦게`. 제목 줄에 서므로 프로그램 화면 요약보다 짧게 쓴다.
String routineWeekSummary(
  AppLocalizations l,
  RoutineDays days,
  DateTime monday,
  DateTime today,
) {
  final _Stats stats = _Stats.of(days, monday, today);
  if (stats.past == 0) return l.workoutRoutineWeekFirstDay;
  return <String>[
    l.workoutRoutineWeekSummary(stats.past, stats.full),
    if (stats.lateDay case final RoutineDay d)
      l.workoutRoutineWeekLate(
        weekdayLabels(l)[d.date.weekday - 1],
        stats.lateCount,
      ),
  ].join(' · ');
}

/// 보낸 운동 이름을 셋까지 적는다 — 넘치면 `외 N개`.
const int _sentNamesMax = 3;

/// 운동 탭 `이번 주` 칸 아래 — 이번 주(오늘까지) 걸렸던 개인운동을 보낸
/// 묶음마다 한 줄. `8/17(월) 보냄 · 인터벌 런닝 · 스쿼트 · 플랭크`.
///
/// 일찍 보낸 묶음이 위다. 기한 없는 따로 배정은 그 주에 보낸 날이 없어
/// `계속 · …` 으로 맨 아래에 적는다.
List<String> routineWeekSentLines(
  AppLocalizations l,
  RoutineDays days,
  DateTime monday,
  DateTime today,
) {
  final Set<String> ids = <String>{
    for (final RoutineDay d in days.between(monday, today))
      for (final RoutineDayItem i in d.items) i.routineId,
  };
  final List<RoutineDayGroup> groups = days.groupsOf(ids);
  final List<RoutineDayGroup> personal =
      groups.where((RoutineDayGroup g) => g.personal).toList()..sort(
        (RoutineDayGroup a, RoutineDayGroup b) => a.sentOn.compareTo(b.sentOn),
      );
  String names(RoutineDayGroup g) {
    final List<String> all = <String>[
      for (final RoutineDayRoutine r in g.routines) r.name,
    ];
    if (all.length <= _sentNamesMax) return all.join(' · ');
    return l.workoutRoutineWeekMore(
      all.take(_sentNamesMax).join(' · '),
      all.length - _sentNamesMax,
    );
  }

  return <String>[
    for (final RoutineDayGroup g in personal)
      l.workoutRoutineWeekSent(routineDayLabel(l, g.sentOn), names(g)),
    for (final RoutineDayGroup g in groups)
      if (!g.personal) l.workoutRoutineWeekOngoing(names(g)),
  ];
}

class _AdherenceCell extends StatelessWidget {
  const _AdherenceCell({
    required this.date,
    required this.today,
    required this.days,
    required this.keyPrefix,
    this.height,
  });

  final DateTime date;
  final DateTime today;
  final RoutineDays days;
  final String keyPrefix;

  /// 칸 높이. 비우면 폭과 같은 정사각형이다.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool future = date.isAfter(today);
    final bool isToday = !future && !date.isBefore(today);
    final RoutineDay? day = future ? null : days.dayOf(date);
    final int total = day?.items.length ?? 0;
    final int done = day?.completed ?? 0;
    final RoutineLevel level = routineLevelOf(day);
    // 오늘은 끝나지 않았다 — 한 만큼은 같은 단계로 칠하되 `하나도 안 함`
    // (빨강)은 쓰지 않는다. 아침의 0개는 안 한 것이 아니라 아직이다. 테두리가
    // 오늘임을 알린다.
    final bool blank =
        future ||
        (isToday && (level == RoutineLevel.none || level == RoutineLevel.zero));
    final Color fill = blank
        ? Colors.transparent
        : routineLevelFill(context, level);
    final bool strong = level == RoutineLevel.all;
    final String? text = future || total == 0 ? null : '$done/$total';
    final Widget cell = Container(
      key: ValueKey<String>('$keyPrefix-${date.month}-${date.day}'),
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
    );
    final double? height = this.height;
    final Widget box = height == null
        ? AspectRatio(aspectRatio: 1, child: cell)
        : SizedBox(height: height, child: cell);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 오늘 칸도 칠하므로 테두리만으로는 오늘이 안 보인다 — 요일 글자로
        // 알린다.
        Text(
          weekdayLabels(l)[date.weekday - 1],
          style: isToday
              ? context.oncare
                    .text(OnCareTypography.strong(OnCareTypography.caption))
                    .copyWith(color: context.oncare.brand.primary)
              : _caption(context, color: OnCareColors.textTertiary),
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

import 'package:flutter/material.dart';

import 'package:oncare_trainer/features/clients/domain/entities/routine_days.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show weekdayLabels;
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 개인운동 매일 완료 현황의 공통 조각 — 날짜 표기, 하루 완료 단계, `개인운동
/// 이행` 칸. (#2508, #2509, #3004)
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
    RoutineLevel.zero => OnCareColors.onWhite(
      OnCareColors.danger,
      OnCareRoutineLevelAlpha.none,
    ),
    RoutineLevel.some => OnCareColors.onWhite(
      brand,
      OnCareRoutineLevelAlpha.some,
    ),
    RoutineLevel.half => OnCareColors.onWhite(
      brand,
      OnCareRoutineLevelAlpha.half,
    ),
    RoutineLevel.all => brand,
  };
}

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

const double _cellGap = OnCareSpacing.s4;

/// `개인운동 이행` 칸 높이 — `6/6` 이 들어갈 만큼만.
const double _stripCellHeight = 36;

TextStyle _caption(BuildContext context, {Color? color}) => context.oncare
    .text(OnCareTypography.caption)
    .copyWith(color: color ?? OnCareColors.textSecondary);

/// `개인운동 이행` — [start] 부터 7칸. (#2508, #2509)
///
/// 칸마다 `완료 수/그날 걸린 수`(기한 없는 따로 배정 포함)를 적고 완료 비율로
/// 진하기를 준다(`전체` 달력과 같은 단계). 오늘은 요일 알약으로 알리고 한 만큼만
/// 칠하며(아직 0개면 빈칸, 빨강 없음), 오지 않은 날은
/// 빈칸이다.
///
/// `이번 주` 는 그 주 월요일부터([ClientRoutineAdherenceStrip.week]), `전체` 는
/// 고른 링의 보낸 날부터([ClientRoutineAdherenceStrip.period]) 7칸이다. 회원 상세
/// 운동 탭과 프로그램 화면이 같은 카드로 쓴다(#3004). 부르는 쪽이 그릴 것이
/// 없는 회원을 가린다.
class ClientRoutineAdherenceStrip extends StatelessWidget {
  /// 운동 탭 `이번 주` — [monday] 부터 일요일까지, 칸이 카드 폭을 채운다.
  /// 요약은 칸 아래가 아니라 카드 제목 줄에 선다([routineWeekSummary]).
  const ClientRoutineAdherenceStrip.week({
    super.key,
    required this.days,
    required DateTime monday,
    required this.today,
  }) : start = monday,
       end = null,
       keyPrefix = 'workout-routine-adherence';

  /// 운동 탭 `전체` — 고른 링([group])의 보낸 날부터 7칸, 폭을 채운다.
  /// [days] 는 그 묶음 배정만 남긴 것이다([RoutineDays.only]) — 링의 % 와
  /// 칸의 수가 같은 것을 센다.
  ClientRoutineAdherenceStrip.period({
    super.key,
    required this.days,
    required RoutineDayGroup group,
    required this.today,
  }) : start = group.activeFrom,
       end = group.lastDay,
       keyPrefix = 'workout-routine-all';

  final RoutineDays days;
  final DateTime today;

  /// 첫 칸의 날.
  final DateTime start;

  /// 묶음이 걸린 마지막 날. 7일보다 일찍 끝났으면 그 뒤 칸은 오지 않은 날처럼
  /// 빈 테두리다 — "배정 없음" 회색으로 칠하면 비어 있던 날과 구분되지 않는다.
  final DateTime? end;

  /// 칸 키의 앞부분.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final List<DateTime> dates = <DateTime>[
      for (int i = 0; i < 7; i++) _addDays(start, i),
    ];
    // 칸은 폭을 나눠 채우고 높이만 고정한다 — 카드 오른쪽에 빈칸이 남지 않게.
    return Row(
      key: ValueKey<String>(keyPrefix),
      children: <Widget>[
        for (final (int i, DateTime d) in dates.indexed) ...<Widget>[
          if (i > 0) const SizedBox(width: _cellGap),
          Expanded(
            child: _AdherenceCell(
              date: d,
              today: today,
              days: days,
              keyPrefix: keyPrefix,
              ended: end != null && d.isAfter(end!),
            ),
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
  return <String>[
    for (final RoutineDayGroup g in personal)
      l.workoutRoutineWeekSent(
        routineDayLabel(l, g.sentOn),
        routineGroupNames(l, g),
      ),
    for (final RoutineDayGroup g in groups)
      if (!g.personal) l.workoutRoutineWeekOngoing(routineGroupNames(l, g)),
  ];
}

/// 운동 탭 `전체` 링 하나 — 보낸 개인운동 한 묶음을 얼마나 따라왔나.
class RoutineGroupAdherence {
  /// Creates one ring.
  const RoutineGroupAdherence({
    required this.group,
    required this.done,
    required this.total,
    required this.ongoing,
    required this.day,
  });

  final RoutineDayGroup group;

  /// 완료한 수 / 센 수. 오늘은 한 만큼만 양쪽에 더한다 — 이번 주 칸처럼
  /// 끝나지 않은 오늘의 0개를 안 한 것으로 세지 않는다.
  final int done;
  final int total;

  /// 오늘도 걸려 있는가.
  final bool ongoing;

  /// 오늘이 보낸 기간의 며칠째인가(1부터). [ongoing] 일 때만 뜻이 있다.
  final int day;

  /// 완료율(0..100). 아직 셀 것이 없으면 null.
  int? get percent => total == 0 ? null : (done * 100 / total).round();
}

/// 오늘까지 걸린 개인운동 묶음마다 링 하나 — 일찍 보낸 것이 앞이다. 기한
/// 없는 따로 배정은 기간이 없어 링으로 그리지 않는다(`계속` 줄).
List<RoutineGroupAdherence> routineGroupAdherence(
  RoutineDays days,
  DateTime today,
) {
  final List<RoutineDayGroup> groups =
      days
          .groupsOf(days.routines.map((RoutineDayRoutine r) => r.id))
          .where(
            (RoutineDayGroup g) =>
                g.personal &&
                !g.activeFrom.isAfter(today) &&
                // 하루도 걸리지 않고 내려간 묶음(보낸 날 바로 바뀐 것)은 그릴
                // 날이 없다.
                !(g.lastDay?.isBefore(g.activeFrom) ?? false),
          )
          .toList()
        ..sort(
          (RoutineDayGroup a, RoutineDayGroup b) =>
              a.activeFrom.compareTo(b.activeFrom),
        );
  return <RoutineGroupAdherence>[
    for (final RoutineDayGroup g in groups) _groupAdherence(days, g, today),
  ];
}

RoutineGroupAdherence _groupAdherence(
  RoutineDays days,
  RoutineDayGroup group,
  DateTime today,
) {
  final Set<String> ids = <String>{
    for (final RoutineDayRoutine r in group.routines) r.id,
  };
  final DateTime? last = group.lastDay;
  final DateTime end = last == null || last.isAfter(today) ? today : last;
  int done = 0;
  int total = 0;
  for (final RoutineDay d in days.between(group.activeFrom, end)) {
    final List<RoutineDayItem> items = <RoutineDayItem>[
      for (final RoutineDayItem i in d.items)
        if (ids.contains(i.routineId)) i,
    ];
    final int completed = items
        .where((RoutineDayItem i) => i.status.completed)
        .length;
    done += completed;
    total += d.date.isBefore(today) ? items.length : completed;
  }
  return RoutineGroupAdherence(
    group: group,
    done: done,
    total: total,
    ongoing: group.activeOn(today),
    day: today.difference(group.activeFrom).inDays + 1,
  );
}

/// 운동 탭 `전체` 제목 줄 오른쪽의 평균 — 셀 것이 있는 링들의 % 평균이다
/// (링마다 같은 무게). 아직 셀 링이 없으면 null.
int? routineAllAverage(List<RoutineGroupAdherence> rings) {
  final List<int> percents = <int>[
    for (final RoutineGroupAdherence r in rings)
      if (r.percent case final int p) p,
  ];
  if (percents.isEmpty) return null;
  return (percents.reduce((int a, int b) => a + b) / percents.length).round();
}

/// 보낸 운동 이름 — 셋까지, 넘치면 `외 N개`.
String routineGroupNames(AppLocalizations l, RoutineDayGroup g) {
  final List<String> all = <String>[
    for (final RoutineDayRoutine r in g.routines) r.name,
  ];
  if (all.length <= _sentNamesMax) return all.join(' · ');
  return l.workoutRoutineWeekMore(
    all.take(_sentNamesMax).join(' · '),
    all.length - _sentNamesMax,
  );
}

class _AdherenceCell extends StatelessWidget {
  const _AdherenceCell({
    required this.date,
    required this.today,
    required this.days,
    required this.keyPrefix,
    this.ended = false,
  });

  final DateTime date;
  final DateTime today;
  final RoutineDays days;
  final String keyPrefix;

  /// 묶음이 끝난 뒤의 날인가 — 오지 않은 날처럼 그린다.
  final bool ended;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool future = ended || date.isAfter(today);
    final bool isToday = !future && !date.isBefore(today);
    final RoutineDay? day = future ? null : days.dayOf(date);
    final int total = day?.items.length ?? 0;
    final int done = day?.completed ?? 0;
    final RoutineLevel level = routineLevelOf(day);
    // 오늘은 끝나지 않았다 — 한 만큼은 같은 단계로 칠하되 `하나도 안 함`
    // (빨강)은 쓰지 않는다. 아침의 0개는 안 한 것이 아니라 아직이다. 오늘은
    // 요일 알약이 알린다.
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
        // 아직 칠할 것이 없는 칸(오지 않은 날·0개인 오늘)은 옅은 테두리.
        border: future || (isToday && blank)
            ? Border.all(color: OnCareColors.lineSubtle)
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
    final Widget box = SizedBox(height: _stripCellHeight, child: cell);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 오늘은 요일을 브랜드색 알약으로 — 달력의 오늘처럼. 칸에 테두리를
        // 두르면 같은 파랑으로 다 칠한 칸(모두 완료)에 묻힌다.
        if (isToday)
          Container(
            key: ValueKey<String>('$keyPrefix-today'),
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
            decoration: BoxDecoration(
              color: context.oncare.brand.primary,
              borderRadius: OnCareRadius.pillAll,
            ),
            child: Text(
              weekdayLabels(l)[date.weekday - 1],
              style: context.oncare
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.textOnFill),
            ),
          )
        else
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

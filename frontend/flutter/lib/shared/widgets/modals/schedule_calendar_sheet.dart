import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/schedule/domain/entities/schedule_event.dart';
import 'package:oncare/features/schedule/presentation/controllers/schedule_controller.dart';
import 'package:oncare/features/schedule/presentation/schedule_category_color.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/modals/add_event_dialog.dart';
import 'package:oncare/shared/widgets/modals/day_events_sheet.dart';
import 'package:oncare_ui/oncare_ui.dart';

String _monthKey(DateTime m) =>
    '${m.year}-${m.month.toString().padLeft(2, '0')}';

/// Bottom sheet showing a month calendar backed by real schedule events
/// (`GET /schedule/events?month=…`). Events are colored by category so the
/// same category always reads the same color.
///
/// 모양은 `2db5b04` 시점의 달력이다(#1778) — 칸 경계선, 오늘 칸 옅은 브랜드색,
/// 칸 안 일정 제목 칩, 제목 옆 연하늘 원형 닫기.
Future<void> showScheduleCalendarSheet(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showAppSheet<void>(
    // 탭 페이지에는 저마다 Navigator 가 있고 MainShell 은 extendBody 라, 탭의
    // Navigator 에 올리면 시트가 하단 내비게이션 **뒤쪽**까지 펼쳐져 마지막 주가
    // 바에 가린다(#680). 루트 Navigator 의 context 로 열어 바 위를 덮는다 — 식단
    // 추가 시트와 같은 규칙. 폭 상한(콘텐츠 최대 폭)은 테마가 정한다.
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (BuildContext ctx) =>
        _CalendarBody(initialDate: initialDate ?? nowKst()),
  );
}

class _CalendarBody extends ConsumerStatefulWidget {
  const _CalendarBody({required this.initialDate});
  final DateTime initialDate;

  @override
  ConsumerState<_CalendarBody> createState() => _CalendarBodyState();
}

class _CalendarBodyState extends ConsumerState<_CalendarBody> {
  late DateTime _month = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
  );

  /// 그리드의 요일 머리. 일요일부터 시작한다 — 문구는 식단 탭이 쓰는 것과 같은
  /// 키를 재사용한다(#847).
  static List<String> _weekdays(AppLocalizations l) => <String>[
    l.dietWeekdaySun,
    l.dietWeekdayMon,
    l.dietWeekdayTue,
    l.dietWeekdayWed,
    l.dietWeekdayThu,
    l.dietWeekdayFri,
    l.dietWeekdaySat,
  ];

  /// 그 날의 일정을 펼친다. 시트에서 무언가 바뀌었으면 달을 다시 읽는다 —
  /// 수정·삭제·추가가 그리드에 곧바로 보여야 한다.
  Future<void> _openDay(DateTime day, List<ScheduleEvent> events) async {
    final bool? changed = await showDayEventsSheet(
      context,
      date: day,
      events: events,
    );
    if (changed != true || !mounted) return;
    ref.invalidate(scheduleMonthProvider(_monthKey(_month)));
  }

  Map<int, List<ScheduleEvent>> _groupByDay(List<ScheduleEvent> events) {
    final map = <int, List<ScheduleEvent>>{};
    for (final ScheduleEvent e in events) {
      final day = int.tryParse(e.date.split('-').last);
      if (day == null) continue;
      (map[day] ??= <ScheduleEvent>[]).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MaterialLocalizations m = MaterialLocalizations.of(context);
    final monthKey = _monthKey(_month);
    final async = ref.watch(scheduleMonthProvider(monthKey));
    final today = nowKst();

    return AppCalendarSheetFrame(
      header: <Widget>[
        AppMonthCalendarHeader(
          title: l.scheduleSheetTitle,
          // 연·월 표기는 로케일마다 순서가 다르다. 직접 조립하지 않고 플랫폼
          // 형식을 쓴다(#847). 달 이동도 플랫폼이 이미 제 언어로 부르는 이름이
          // 있다.
          monthLabel: m.formatMonthYear(_month),
          previousTooltip: m.previousMonthTooltip,
          nextTooltip: m.nextMonthTooltip,
          onPrevious: () =>
              setState(() => _month = DateTime(_month.year, _month.month - 1)),
          onNext: () =>
              setState(() => _month = DateTime(_month.year, _month.month + 1)),
          actionLabel: l.eventAddTitle,
          onAction: () async {
            await showAddEventDialog(context);
            // 추가된 일정이 이 달 그리드에 반영되도록 새로고침.
            ref.invalidate(scheduleMonthProvider(monthKey));
          },
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppCalendarLegend(
          entries: <(Color, String)>[
            for (final ScheduleCategory c in ScheduleCategory.values)
              (scheduleCategoryColor(c), scheduleCategoryLabel(l, c)),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 요일 띠는 달을 불러오는 동안에도 남긴다.
        AppMonthWeekdayHeader(labels: _weekdays(l)),
      ],
      body: async.when(
        skipLoadingOnRefresh: true,
        data: (List<ScheduleEvent> events) {
          final byDay = _groupByDay(events);
          // 주 줄은 남은 세로 공간을 나눠 갖고, 최소 높이에 걸리면 격자만
          // 스크롤한다 — 6주짜리 달도 잘라내지 않는다(#669).
          return AppMonthGrid(
            month: _month,
            weekdayLabels: _weekdays(l),
            firstWeekday: DateTime.sunday,
            showWeekdayHeader: false,
            today: today,
            dayKey: (DateTime day) => Key('calendar-day-${day.day}'),
            // 칸을 눌러 그 날의 일정을 펼친다. 예전에는 칸도 칩도 어떤 탭에도
            // 반응하지 않아, 한 번 넣은 일정을 열어 보거나 고치거나 지울
            // 방법이 없었다(#784).
            onSelected: (DateTime day) =>
                _openDay(day, byDay[day.day] ?? const <ScheduleEvent>[]),
            dayBuilder: (BuildContext _, DateTime day) {
              final List<ScheduleEvent> dayEvents =
                  byDay[day.day] ?? const <ScheduleEvent>[];
              if (dayEvents.isEmpty) return null;
              return _DayEventChips(events: dayEvents);
            },
          );
        },
        loading: () => const AppLoading(),
        error: (Object e, _) => AppErrorState(
          title: l.eventsLoadFailed,
          retryLabel: l.actionRetry,
          onRetry: () => ref.invalidate(scheduleMonthProvider(monthKey)),
        ),
      ),
    );
  }
}

/// 한 칸 안의 일정 칩 세로 묶음 — 카테고리 색, `시각 제목`. 칸을 넘치는 칩은
/// 격자가 잘라낸다. 전부는 날짜를 눌러 펼친 하루 시트에서 본다.
class _DayEventChips extends StatelessWidget {
  const _DayEventChips({required this.events});

  final List<ScheduleEvent> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final ScheduleEvent e in events)
          AppCalendarEventChip(
            color: scheduleCategoryColor(e.category),
            label: '${e.time} ${e.title}'.trim(),
          ),
      ],
    );
  }
}

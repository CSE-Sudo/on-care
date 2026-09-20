import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 포인트 화면의 기록 그래프 — 깃허브 잔디와 같은 격자. (#2075, #2076)
///
/// 한 칸이 하루다. **요일이 세로 7줄**이고 주가 왼쪽에서 오른쪽으로 쌓이며,
/// 오른쪽 끝이 오늘이다. 최근 1년(53주)을 그리고 가로로 스크롤한다 — 처음 열면
/// 오른쪽 끝(오늘)에서 시작한다.
///
/// 칸의 진하기는 그날 무엇을 남겼는가 세 단계다: 아무 기록도 없음 → 식단·운동 중
/// 하나만 → 둘 다. 한 해를 한눈에 훑으면 어느 계절에 무너졌는지가 보인다.
///
/// - 칸 위에 월 라벨만 둔다. 깃허브는 왼쪽에 요일(월·수·금)도 적지만, 그 세 글자가
///   무엇인지 되묻게 되는 자리라 뺐다 — 어느 날인지는 칸을 누르면 아래 한 줄이
///   날짜로 말해 준다. 칸이 작아 날짜 숫자도 적지 않는다.
/// - 보호권으로 이어 붙인 날(#1788)은 **방패와 테두리**를 함께 둘러 실제 기록과
///   구분한다. 칸 안이 빈 칸 색 그대로라 방패만으로는 한 해치를 훑을 때 눈에
///   걸리지 않았다 — 테두리가 "여기를 이어 붙였다" 를 멀리서도 짚어 준다.
/// - 날짜를 누르면 그래프 아래 **고정된 한 줄**이 그날 기록으로 바뀐다. 그날이
///   지금 보호권을 쓸 수 있는 날이면 그 줄 오른쪽에 `보호권 쓰기` 가 붙는다 —
///   누른 김에 바로 쓰되, 보려고 누른 사람에게 확인창이 튀어나오지는 않는다.
/// - 보호할 수 있는 칸은 테두리로 미리 표시해 둔다(눌러 볼 이유를 준다).
class RecordGraphCard extends StatefulWidget {
  const RecordGraphCard({
    super.key,
    required this.calendar,
    required this.onProtect,
    required this.onChangeColor,
    this.busy = false,
  });

  final ActivityCalendar calendar;

  /// 그날을 연속에 이어 붙인다. null 이면 쓸 수 없다.
  final ValueChanged<DateTime>? onProtect;

  /// 그래프 색 고르기 — 카드 오른쪽 위 팔레트 버튼이 부른다.
  final VoidCallback? onChangeColor;

  /// 보호권 사용 요청이 나가 있다.
  final bool busy;

  @override
  State<RecordGraphCard> createState() => _RecordGraphCardState();
}

class _RecordGraphCardState extends State<RecordGraphCard> {
  final ScrollController _scroll = ScrollController();

  /// 누른 날. 아무것도 누르지 않았으면 오늘 줄을 보여 준다.
  DateTime? _picked;

  @override
  void initState() {
    super.initState();
    // 오른쪽 끝(오늘)에서 시작한다 — 가장 보고 싶은 것은 최근이다. 격자의 폭은
    // 첫 배치가 끝나야 정해지므로 그다음 프레임에 민다(`initialScrollOffset` 에
    // 큰 값을 넣으면 스크롤이 자리를 잡지 못한다).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  ActivityDay? get _selected {
    final List<ActivityDay> days = widget.calendar.days;
    if (days.isEmpty) return null;
    final DateTime? picked = _picked;
    if (picked == null) return days.last;
    for (final ActivityDay d in days) {
      if (_sameDay(d.date, picked)) return d;
    }
    return days.last;
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final ActivityCalendar calendar = widget.calendar;
    final OnCareRecordRamp ramp = OnCareRecordColors.rampOf(
      calendar.color.current,
    );
    final ActivityDay? selected = _selected;
    final bool canProtect =
        selected != null &&
        widget.onProtect != null &&
        calendar.isProtectable(selected);
    return AppCard(
      key: const Key('recordGraphCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.myGraphTitle,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              AppTag(
                key: const Key('recordGraphStreak'),
                label: l.myGraphStreak(calendar.recordStreakDays),
                tone: calendar.recordStreakDays > 0
                    ? AppTagTone.brand
                    : AppTagTone.neutral,
              ),
              if (widget.onChangeColor != null) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s4),
                AppIconButton(
                  key: const Key('recordGraphColorButton'),
                  icon: AppIcons.palette,
                  tooltip: l.myGraphColorTitle,
                  color: ramp.full,
                  onPressed: widget.onChangeColor,
                ),
              ],
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _Grid(
            calendar: calendar,
            ramp: ramp,
            controller: _scroll,
            picked: _picked,
            protectable: widget.onProtect != null,
            onPick: (DateTime day) => setState(() => _picked = day),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _DayLine(
            day: selected,
            picked: _picked != null,
            busy: widget.busy,
            onProtect: canProtect
                ? () => widget.onProtect!(selected.date)
                : null,
          ),
        ],
      ),
    );
  }
}

/// 잔디 격자 — 요일 7줄, 주가 가로로 쌓이고 오른쪽 끝이 오늘.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.calendar,
    required this.ramp,
    required this.controller,
    required this.picked,
    required this.protectable,
    required this.onPick,
  });

  final ActivityCalendar calendar;
  final OnCareRecordRamp ramp;
  final ScrollController controller;
  final DateTime? picked;

  /// 보호권을 쓸 수 있는 상태인가(다른 요청이 진행 중이면 false).
  final bool protectable;

  final ValueChanged<DateTime> onPick;

  /// 칸 한 변과 칸 사이 틈. 53주가 손가락으로 밀 만한 길이가 되고, 이어 붙인 날의
  /// 방패가 테두리 안에 들어갈 만한 크기다.
  static const double _side = 15;
  static const double _gap = 3;

  /// 월 라벨 줄 높이.
  static const double _monthBar = 14;

  @override
  Widget build(BuildContext context) {
    final List<ActivityDay> days = calendar.days;
    if (days.isEmpty) return const SizedBox.shrink();

    // 첫 칸이 그 주의 요일 자리에서 시작하게 앞을 비운다 — 세로 한 줄이 늘 같은
    // 요일이라 "주말에만 빠진다" 같은 흐름이 보인다. 일요일이 맨 윗줄이다.
    final int lead = days.first.date.weekday % 7;
    final int weeks = ((lead + days.length) / 7).ceil();

    return SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      // 카드 안에서 가로로만 민다. 세로 스크롤은 화면이 가져간다.
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: _monthBar,
            // 격자와 같은 폭을 준다 — 라벨을 주 자리에 얹는 Stack 은 폭이
            // 정해져야 하고, 스크롤 안이라 부모가 정해 주지 않는다.
            width: weeks * _side + (weeks - 1) * _gap,
            child: _MonthLabels(
              days: days,
              lead: lead,
              weeks: weeks,
              side: _side,
              gap: _gap,
            ),
          ),
          const SizedBox(height: _gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int week = 0; week < weeks; week++) ...<Widget>[
                if (week > 0) const SizedBox(width: _gap),
                Column(
                  children: <Widget>[
                    for (int row = 0; row < 7; row++) ...<Widget>[
                      if (row > 0) const SizedBox(height: _gap),
                      Builder(
                        builder: (BuildContext context) {
                          final int index = week * 7 + row - lead;
                          if (index < 0 || index >= days.length) {
                            // 구간 앞과, 오늘 뒤의 남은 자리.
                            return const SizedBox(width: _side, height: _side);
                          }
                          final ActivityDay day = days[index];
                          return _Cell(
                            day: day,
                            ramp: ramp,
                            side: _side,
                            selected:
                                picked != null && _sameDay(picked!, day.date),
                            protectable:
                                protectable && calendar.isProtectable(day),
                            onTap: () => onPick(day.date),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 격자 위의 월 라벨 — 달이 바뀌는 주 자리에 그 달을 적는다.
class _MonthLabels extends StatelessWidget {
  const _MonthLabels({
    required this.days,
    required this.lead,
    required this.weeks,
    required this.side,
    required this.gap,
  });

  final List<ActivityDay> days;
  final int lead;
  final int weeks;
  final double side;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    // 주마다 그 주의 첫 칸이 속한 달. 앞선 주와 달이 다를 때만 라벨을 세운다.
    final List<int?> labels = List<int?>.filled(weeks, null);
    int? previous;
    for (int week = 0; week < weeks; week++) {
      final int index = week * 7 - lead;
      final ActivityDay? first = index >= 0 && index < days.length
          ? days[index]
          : (index < 0 && days.isNotEmpty ? days.first : null);
      if (first == null) continue;
      final int month = first.date.month;
      if (month != previous) {
        labels[week] = month;
        previous = month;
      }
    }
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        for (int week = 0; week < weeks; week++)
          if (labels[week] != null)
            Positioned(
              left: week * (side + gap),
              child: Text(
                l.myGraphMonthLabel(labels[week]!),
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
      ],
    );
  }
}

/// 칸 하나 — 채움이 그날 기록이다. 칸이 작아 날짜는 적지 않는다.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.ramp,
    required this.side,
    required this.selected,
    required this.protectable,
    required this.onTap,
  });

  final ActivityDay day;
  final OnCareRecordRamp ramp;
  final double side;
  final bool selected;

  /// 지금 보호권으로 이어 붙일 수 있는 날.
  final bool protectable;

  final VoidCallback onTap;

  /// 이어 붙인 날·고른 날의 테두리 두께.
  static const double _border = 2;

  Color get _fill => switch (day.level) {
    RecordLevel.none => ramp.none,
    RecordLevel.partial => ramp.partial,
    RecordLevel.full => ramp.full,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: recordDayLabel(l, day),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: ValueKey<String>('record-cell-${_ymd(day.date)}'),
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: OnCareRadius.xsAll,
            border: selected
                ? Border.all(color: OnCareColors.textPrimary, width: _border)
                // 이어 붙인 날이 가장 두껍다 — 한 해치를 훑을 때 먼저 눈에 걸려야
                // 하는 칸이다. 누를 수 있는 빈 칸은 그보다 연한 테두리로 권한다.
                : day.protected
                ? Border.all(color: ramp.full, width: _border)
                : protectable
                ? Border.all(color: ramp.partial, width: 1.5)
                : null,
          ),
          // 보호한 날은 실제 기록이 아니다 — 빈 칸 회색 위에 방패를 얹고 테두리를
          // 둘러 기록한 날과 구분한다.
          //
          // 테두리는 칸 **안쪽**을 먹는다. 남는 자리보다 큰 글리프를 넣으면 한쪽으로
          // 밀려 테두리를 타고 넘으므로, 남은 폭에 맞춰 줄인다.
          child: day.protected
              ? Center(
                  child: AppIcon(
                    AppIcons.streakShield,
                    size: side - _border * 2 - 1,
                    color: OnCareRecordColors.shieldOn(ramp),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// 그래프 아래 고정 한 줄 — 누른 날의 기록과, 쓸 수 있으면 `보호권 쓰기`.
class _DayLine extends StatelessWidget {
  const _DayLine({
    required this.day,
    required this.picked,
    required this.busy,
    required this.onProtect,
  });

  final ActivityDay? day;

  /// 회원이 직접 누른 날인가. 아직 누르지 않았으면 누르라는 안내를 함께 적는다.
  final bool picked;

  final bool busy;

  /// null 이면 이 날은 보호권을 쓸 수 없다.
  final VoidCallback? onProtect;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final ActivityDay? d = day;
    return Row(
      children: <Widget>[
        const AppIcon(
          AppIcons.info,
          size: OnCareSize.iconSmall,
          color: OnCareColors.textTertiary,
        ),
        const SizedBox(width: OnCareSpacing.s4),
        Expanded(
          child: Text(
            d == null
                ? l.myGraphDayHint
                : picked
                ? recordDayLabel(l, d)
                : '${recordDayLabel(l, d)} · ${l.myGraphDayHint}',
            key: const Key('recordGraphDayLine'),
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ),
        if (onProtect != null)
          AppButton(
            key: const Key('recordGraphProtect'),
            label: l.myGraphProtectAction,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
            loading: busy,
            onPressed: onProtect,
          ),
      ],
    );
  }
}

/// 날짜 하나의 한 줄 설명 — 고정 줄과 스크린 리더가 함께 쓴다.
String recordDayLabel(AppLocalizations l, ActivityDay day) {
  final String date = l.myGraphDate(day.date.month, day.date.day);
  if (day.protected) return l.myGraphDayProtected(date);
  return switch ((day.hasDiet, day.hasExercise)) {
    (true, true) => l.myGraphDayBoth(date),
    (true, false) => l.myGraphDayDiet(date),
    (false, true) => l.myGraphDayExercise(date),
    _ => l.myGraphDayNone(date),
  };
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

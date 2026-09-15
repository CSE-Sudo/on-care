import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/calendar.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 이전/다음 기간 이동(#1697) — tonal 꺾쇠 버튼 두 개와 가운데 기간 라벨.
///
/// 트레이너 스케줄·리포트의 주 이동이 쓴다.
class AppPeriodNav extends StatelessWidget {
  const AppPeriodNav({
    super.key,
    required this.label,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.onPrevious,
    required this.onNext,
    this.trailing,
  });

  final String label;
  final String previousTooltip;
  final String nextTooltip;

  /// `null` 이면 그 방향으로 갈 수 없다(비활성).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// 오른쪽 끝의 `오늘`·`이번 주` 같은 버튼.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppIconButton(
          icon: AppIcon.setOf(context).previous,
          tooltip: previousTooltip,
          variant: AppIconButtonVariant.tonal,
          onPressed: onPrevious,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
          child: Text(
            label,
            style: OnCareTypography.numeric(
              context.oncare.text(OnCareTypography.label),
            ).copyWith(color: OnCareColors.textPrimary),
          ),
        ),
        AppIconButton(
          icon: AppIcon.setOf(context).next,
          tooltip: nextTooltip,
          variant: AppIconButtonVariant.tonal,
          onPressed: onNext,
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          trailing!,
        ],
      ],
    );
  }
}

/// 주간 달력(회원앱 식단·운동, #1778) — `2db5b04` 시점 모양.
///
/// 위에 주 라벨과 `오늘` 알약([label]·[todayLabel]), 아래에 요일 + 날짜 칸 줄을
/// 그린다. 선택한 날은 브랜드 채움 칸에 카드 그림자, 오늘은 브랜드 글자다.
///
/// [previousTooltip]·[nextTooltip] 을 둘 다 주면 날짜 줄 **양옆**에 옅은 원형
/// 꺾쇠를 그린다. [onPrevious]·[onNext] 가 `null` 이면 흐리게 비활성이다.
class AppWeekStrip extends StatelessWidget {
  const AppWeekStrip({
    super.key,
    required this.days,
    required this.weekdayLabels,
    required this.selected,
    required this.onSelected,
    this.today,
    this.markedDays = const <DateTime>{},
    this.previousTooltip,
    this.nextTooltip,
    this.onPrevious,
    this.onNext,
    this.lastSelectableDay,
    this.label,
    this.todayLabel,
    this.onToday,
    this.todayKey,
  }) : assert(days.length == weekdayLabels.length),
       assert(
         (previousTooltip == null) == (nextTooltip == null),
         '양옆 꺾쇠는 두 툴팁을 함께 줘야 한다.',
       );

  /// 보여 줄 날(보통 7일).
  final List<DateTime> days;

  /// [days] 와 같은 순서의 요일 문구(앱 l10n).
  final List<String> weekdayLabels;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;
  final DateTime? today;

  /// 기록이 있는 날 — 날짜 칸 아래 점. 비우면 점 줄을 그리지 않는다.
  final Set<DateTime> markedDays;

  /// 양옆 꺾쇠의 접근성 이름. 둘 다 있을 때만 꺾쇠를 그린다.
  final String? previousTooltip;
  final String? nextTooltip;

  /// `null` 이면 그 방향으로 갈 수 없다(흐리게 비활성).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// 고를 수 있는 마지막 날. 이보다 뒤의 날은 모양은 그대로 두고 탭만 받지
  /// 않는다(아직 오지 않은 날). `null` 이면 모든 날을 고를 수 있다.
  final DateTime? lastSelectableDay;

  /// 날짜 줄 위의 주 라벨. 비우면 라벨 줄 없이 날짜 줄만 그린다.
  final String? label;

  /// 라벨 오른쪽 `오늘` 알약 문구와 동작. 둘 다 있을 때만 알약을 그린다.
  final String? todayLabel;
  final VoidCallback? onToday;

  /// `오늘` 알약 키. 오늘로 돌아오는 유일한 길이라 테스트가 지목한다.
  final Key? todayKey;

  bool _selectable(DateTime day) {
    final DateTime? last = lastSelectableDay;
    if (last == null) return true;
    return !DateTime(
      day.year,
      day.month,
      day.day,
    ).isAfter(DateTime(last.year, last.month, last.day));
  }

  @override
  Widget build(BuildContext context) {
    Widget row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        // 칸마다 제 크기를 요구하면 일곱의 합이 화면을 넘는다 — 영어 요일
        // 라벨(Mon/Tue)이 한글 한 글자보다 넓다(#743).
        for (int i = 0; i < days.length; i++)
          Expanded(
            child: _WeekDayCell(
              day: days[i],
              weekdayLabel: weekdayLabels[i],
              isToday: today != null && _sameDay(days[i], today!),
              isSelected: _sameDay(days[i], selected),
              marked: markedDays.isEmpty
                  ? null
                  : markedDays.any((DateTime d) => _sameDay(d, days[i])),
              onTap: _selectable(days[i]) ? () => onSelected(days[i]) : null,
            ),
          ),
      ],
    );
    if (previousTooltip != null && nextTooltip != null) {
      row = Row(
        children: <Widget>[
          _WeekStripArrow(
            icon: AppIcon.setOf(context).previous,
            tooltip: previousTooltip!,
            onPressed: onPrevious,
          ),
          Expanded(child: row),
          _WeekStripArrow(
            icon: AppIcon.setOf(context).next,
            tooltip: nextTooltip!,
            onPressed: onNext,
          ),
        ],
      );
    }
    if (label == null) return row;

    final OnCareTokens tokens = context.oncare;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // 영어의 주 라벨은 한국어보다 훨씬 길다. 고정 폭으로 두면 좁은
              // 화면에서 오늘 알약을 밀어내며 넘친다(#743).
              Flexible(
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareCalendar.weekLabel)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
              if (todayLabel != null && onToday != null)
                AppTodayPill(
                  key: todayKey,
                  label: todayLabel!,
                  onPressed: onToday!,
                ),
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        row,
      ],
    );
  }
}

/// [AppWeekStrip] 의 한 날 — 요일 글자 + 날짜 칸.
class _WeekDayCell extends StatelessWidget {
  const _WeekDayCell({
    required this.day,
    required this.weekdayLabel,
    required this.isToday,
    required this.isSelected,
    required this.marked,
    required this.onTap,
  });

  final DateTime day;
  final String weekdayLabel;
  final bool isToday;
  final bool isSelected;

  /// 기록 점. `null` 이면 점 줄 자체가 없다.
  final bool? marked;

  /// `null` 이면 고를 수 없는 날이다(모양은 그대로).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color primary = tokens.brand.primary;
    final Color labelColor = isSelected || isToday
        ? primary
        : OnCareColors.textTertiary;
    // 칸도 글자 배율을 따라간다 — 고정하면 날짜 숫자가 칸에 눌린다(#1004).
    final double box = MediaQuery.textScalerOf(
      context,
    ).scale(OnCareCalendar.weekDayBox);
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 말줄임이 아니라 축소다. 'Mon' 이 'M…' 이 되면 무슨 요일인지가
            // 사라진다(#743).
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                weekdayLabel,
                maxLines: 1,
                style: tokens
                    .text(OnCareCalendar.weekday)
                    .copyWith(color: labelColor),
              ),
            ),
            const SizedBox(height: OnCareCalendar.weekdayGap),
            Container(
              width: box,
              height: box,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? primary : Colors.transparent,
                borderRadius: OnCareRadius.mdAll,
                boxShadow: isSelected ? OnCareShadows.card : null,
              ),
              child: Text(
                '${day.day}',
                style: tokens
                    .text(OnCareCalendar.weekDayNumber)
                    .copyWith(
                      color: isSelected
                          ? OnCareColors.textOnFill
                          : isToday
                          ? primary
                          : OnCareColors.textTertiary,
                    ),
              ),
            ),
            if (marked != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s4),
              SizedBox(
                height: OnCareSize.dot / 2,
                child: marked!
                    ? Container(
                        width: OnCareSize.dot / 2,
                        decoration: BoxDecoration(
                          color: primary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [AppWeekStrip] 양옆의 작은 원형 꺾쇠 — 옅은 브랜드 바탕, 비활성은 흐리게.
class _WeekStripArrow extends StatelessWidget {
  const _WeekStripArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;

  /// 화살표 하나뿐이라 어느 쪽으로 가는지 말할 데가 툴팁뿐이다(#972).
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Opacity(
      opacity: onPressed == null ? OnCareCalendar.disabledArrowOpacity : 1,
      child: Material(
        color: tokens.brand.surfaceSoft,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox.square(
              dimension: OnCareCalendar.weekArrow,
              child: AppIcon(
                icon,
                size: OnCareSize.iconSmall,
                color: tokens.brand.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `오늘` 알약 — 옅은 브랜드 채움·테두리의 작은 알약 버튼(#1778).
///
/// 주간 달력에서 오늘이 아닌 날을 골랐을 때 오늘로 돌아오는 길이다.
class AppTodayPill extends StatelessWidget {
  const AppTodayPill({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color primary = tokens.brand.primary;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: OnCareCalendar.todayPillPadding,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: OnCareCalendar.todayPillFillAlpha),
            borderRadius: OnCareRadius.pillAll,
            border: Border.all(
              color: primary.withValues(
                alpha: OnCareCalendar.todayPillBorderAlpha,
              ),
            ),
          ),
          child: Text(
            label,
            style: tokens
                .text(OnCareCalendar.todayPill)
                .copyWith(color: primary),
          ),
        ),
      ),
    );
  }
}

/// 월 달력 칸 — 요일 머리글 + 날짜 격자. 칸 안의 일정 표시는 [dayBuilder] 가 그린다.
class AppMonthGrid extends StatelessWidget {
  const AppMonthGrid({
    super.key,
    required this.month,
    required this.weekdayLabels,
    required this.selected,
    required this.onSelected,
    this.today,
    this.dayBuilder,
    this.firstWeekday = DateTime.monday,
  }) : assert(weekdayLabels.length == 7);

  /// 보여 줄 달(일은 무시).
  final DateTime month;

  /// [firstWeekday] 부터 7개.
  final List<String> weekdayLabels;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;
  final DateTime? today;
  final Widget? Function(BuildContext context, DateTime day)? dayBuilder;
  final int firstWeekday;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final DateTime first = DateTime(month.year, month.month);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int leading = (first.weekday - firstWeekday) % 7;
    final int cells = ((leading + daysInMonth) / 7).ceil() * 7;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final String w in weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        for (int row = 0; row < cells ~/ 7; row++)
          Row(
            children: <Widget>[
              for (int col = 0; col < 7; col++)
                Expanded(
                  child: _cell(
                    context,
                    tokens,
                    row * 7 + col - leading + 1,
                    daysInMonth,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    OnCareTokens tokens,
    int day,
    int daysInMonth,
  ) {
    if (day < 1 || day > daysInMonth) {
      return SizedBox(height: tokens.density.chip + OnCareSpacing.s12);
    }
    final DateTime date = DateTime(month.year, month.month, day);
    final bool isSelected = selected != null && _sameDay(date, selected!);
    final bool isToday = today != null && _sameDay(date, today!);
    final Widget? extra = dayBuilder?.call(context, date);
    return InkWell(
      borderRadius: OnCareRadius.mdAll,
      onTap: () => onSelected(date),
      child: SizedBox(
        height: tokens.density.chip + OnCareSpacing.s12,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: tokens.density.chip - OnCareSpacing.s4,
              height: tokens.density.chip - OnCareSpacing.s4,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? tokens.brand.primary : Colors.transparent,
                borderRadius: OnCareRadius.mdAll,
              ),
              child: Text(
                '$day',
                style:
                    OnCareTypography.numeric(
                      tokens.text(
                        isToday
                            ? OnCareTypography.strong(
                                OnCareTypography.bodySmall,
                              )
                            : OnCareTypography.bodySmall,
                      ),
                    ).copyWith(
                      color: isSelected
                          ? OnCareColors.textOnFill
                          : isToday
                          ? tokens.brand.primary
                          : OnCareColors.textPrimary,
                    ),
              ),
            ),
            ?extra,
          ],
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_button.dart';
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
          icon: Icons.chevron_left_rounded,
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
          icon: Icons.chevron_right_rounded,
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
            icon: Icons.chevron_left_rounded,
            tooltip: previousTooltip!,
            onPressed: onPrevious,
          ),
          Expanded(child: row),
          _WeekStripArrow(
            icon: Icons.chevron_right_rounded,
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
              child: Icon(
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

/// 원형 닫기 — 옅은 브랜드(accent) 원 안의 작은 X(#1778, 월간 달력 시트 제목 옆).
///
/// [onPressed] 를 비우면 현재 경로를 닫는다.
class AppCircleCloseButton extends StatelessWidget {
  const AppCircleCloseButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.oncare.brand.surfaceAccent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed ?? () => Navigator.maybePop(context),
        child: Tooltip(
          message: MaterialLocalizations.of(context).closeButtonTooltip,
          child: const SizedBox.square(
            dimension: OnCareCalendar.circleClose,
            child: Icon(
              Icons.close_rounded,
              size: OnCareCalendar.circleCloseIcon,
              color: OnCareColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 월간 달력 시트 머리(#1778) — 제목 + 원형 닫기, 그 아래 달 이동 꺾쇠·달 라벨과
/// 오른쪽 끝 동작 버튼(`일정 추가`).
class AppMonthCalendarHeader extends StatelessWidget {
  const AppMonthCalendarHeader({
    super.key,
    required this.title,
    required this.monthLabel,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.onPrevious,
    required this.onNext,
    required this.actionLabel,
    required this.onAction,
    this.onClose,
  });

  final String title;

  /// 연·월 표기(로케일 형식은 호출하는 쪽이 정한다).
  final String monthLabel;
  final String previousTooltip;
  final String nextTooltip;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String actionLabel;
  final VoidCallback? onAction;

  /// 비우면 현재 경로를 닫는다.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: OnCareSpacing.s12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: tokens
                    .text(OnCareTypography.titleLarge)
                    .copyWith(color: OnCareColors.textPrimary),
              ),
            ),
            AppCircleCloseButton(onPressed: onClose),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppIconButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: previousTooltip,
                    onPressed: onPrevious,
                  ),
                  Flexible(
                    child: Text(
                      monthLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .text(OnCareTypography.titleMedium)
                          .copyWith(
                            // 옛 달 라벨은 제목보다 가벼운 500 이었다.
                            fontWeight: FontWeight.w500,
                            color: OnCareColors.textPrimary,
                          ),
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: nextTooltip,
                    onPressed: onNext,
                  ),
                ],
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            AppButton(label: actionLabel, onPressed: onAction),
          ],
        ),
      ],
    );
  }
}

/// 월간 달력 요일 머리 띠(#1778) — 옅은 브랜드(accent) 바탕에 요일 글자.
class AppMonthWeekdayHeader extends StatelessWidget {
  const AppMonthWeekdayHeader({super.key, required this.labels});

  /// 격자의 첫 요일부터 7개.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    // 상수 생성자에서는 목록 길이를 볼 수 없어 여기서 확인한다.
    assert(labels.length == 7, '요일 띠는 7개 문구를 받는다.');
    final OnCareTokens tokens = context.oncare;
    return Row(
      children: <Widget>[
        for (final String w in labels)
          Expanded(
            child: Container(
              color: tokens.brand.surfaceAccent,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                vertical: OnCareCalendar.weekdayBandVerticalPadding,
              ),
              child: Text(
                w,
                maxLines: 1,
                style: tokens
                    .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
          ),
      ],
    );
  }
}

/// 월간 달력 격자(#1778) — `2db5b04` 시점의 일정 달력 모양.
///
/// 칸 사이 경계선, 오늘 칸 옅은 브랜드 바탕, 왼쪽 위 굵은 날짜 숫자, 그 아래
/// [dayBuilder] 가 그리는 일정 칩. 높이가 정해진 자리에 두면 주 줄이 남은 높이를
/// 나눠 갖고, 한 줄이 [OnCareCalendar.monthMinRowHeight] 보다 낮아지면 줄이는
/// 대신 격자만 스크롤한다(#669). 높이가 정해지지 않은 자리(목록 안)에서는 최소
/// 높이로 모든 줄을 그린다.
class AppMonthGrid extends StatelessWidget {
  const AppMonthGrid({
    super.key,
    required this.month,
    required this.weekdayLabels,
    required this.onSelected,
    this.selected,
    this.today,
    this.dayBuilder,
    this.dayKey,
    this.firstWeekday = DateTime.monday,
    this.showWeekdayHeader = true,
  }) : assert(weekdayLabels.length == 7);

  /// 보여 줄 달(일은 무시).
  final DateTime month;

  /// [firstWeekday] 부터 7개.
  final List<String> weekdayLabels;
  final ValueChanged<DateTime> onSelected;

  /// 고른 날. 오늘 칸과 같은 옅은 바탕으로 그린다.
  final DateTime? selected;
  final DateTime? today;

  /// 날짜 숫자 아래 칸을 채우는 내용(보통 일정 칩 세로 묶음). 칸을 넘치는 만큼은
  /// 잘리고, 날짜 숫자는 언제나 남는다.
  final Widget? Function(BuildContext context, DateTime day)? dayBuilder;

  /// 날짜 칸(누르는 영역)에 붙일 키.
  final Key? Function(DateTime day)? dayKey;
  final int firstWeekday;

  /// 격자 위에 요일 띠를 함께 그릴지. 불러오는 동안에도 띠를 남기려면 끄고
  /// [AppMonthWeekdayHeader] 를 바깥에 둔다.
  final bool showWeekdayHeader;

  @override
  Widget build(BuildContext context) {
    final DateTime first = DateTime(month.year, month.month);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int leading = (first.weekday - firstWeekday) % 7;
    // 앞은 1일의 요일까지 비우고, 뒤도 마지막 주가 7칸이 되도록 채운다 — 채우지
    // 않으면 마지막 주의 경계선이 중간에서 끊긴다.
    final int weeks = ((leading + daysInMonth) / 7).ceil();
    final Widget? header = showWeekdayHeader
        ? AppMonthWeekdayHeader(labels: weekdayLabels)
        : null;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (!constraints.hasBoundedHeight) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ?header,
              _weeks(
                context,
                weeks,
                leading,
                daysInMonth,
                OnCareCalendar.monthMinRowHeight,
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ?header,
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints inner) {
                  // 칸 높이를 남은 세로 공간에서 정한다. 가로폭에서 고정 비율로
                  // 잡으면 6주짜리 달의 마지막 주가 잘린다(#669).
                  final double rowHeight = math.max(
                    OnCareCalendar.monthMinRowHeight,
                    inner.maxHeight / weeks,
                  );
                  return SingleChildScrollView(
                    // 최소 높이에 걸려 다 담기지 않을 때만 스크롤이 생긴다.
                    physics: const ClampingScrollPhysics(),
                    child: _weeks(
                      context,
                      weeks,
                      leading,
                      daysInMonth,
                      rowHeight,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _weeks(
    BuildContext context,
    int weeks,
    int leading,
    int daysInMonth,
    double rowHeight,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int week = 0; week < weeks; week++)
          SizedBox(
            height: rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int col = 0; col < 7; col++)
                  Expanded(
                    child: _cell(
                      context,
                      week * 7 + col - leading + 1,
                      daysInMonth,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static const Border _cellBorder = Border(
    right: BorderSide(color: OnCareColors.lineSubtle),
    bottom: BorderSide(color: OnCareColors.lineSubtle),
  );

  Widget _cell(BuildContext context, int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) {
      return const DecoratedBox(decoration: BoxDecoration(border: _cellBorder));
    }
    final OnCareTokens tokens = context.oncare;
    final DateTime date = DateTime(month.year, month.month, day);
    final bool isToday = today != null && _sameDay(date, today!);
    final bool isSelected = selected != null && _sameDay(date, selected!);
    final Widget? extra = dayBuilder?.call(context, date);
    return InkWell(
      key: dayKey?.call(date),
      onTap: () => onSelected(date),
      child: Container(
        decoration: BoxDecoration(
          color: isToday || isSelected
              ? tokens.brand.primary.withValues(
                  alpha: OnCareCalendar.todayCellAlpha,
                )
              : null,
          border: _cellBorder,
        ),
        padding: const EdgeInsets.all(OnCareSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$day',
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    color: isToday
                        ? tokens.brand.primary
                        : OnCareColors.textPrimary,
                  ),
            ),
            const SizedBox(height: OnCareSpacing.s2),
            // 칸 높이는 남은 공간에서 정해지므로 일정이 여럿인 날은 칩이 칸을
            // 넘길 수 있다. 넘치는 만큼은 ClipRect 가 잘라내고, OverflowBox 가
            // 무한 높이를 줘 오버플로 경고 없이 그린다. 칸마다 스크롤 뷰를 두면
            // 한 달에 35~42개가 생겨 자르기만 하는 값으로는 비싸다.
            Expanded(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxHeight: double.infinity,
                  child: extra ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 월간 달력 칸 안 일정 칩(#1778) — 카테고리 색을 옅게 깐 작은 네모에 `시각 제목`.
///
/// [color] 는 카테고리의 원래(진한) 색이다. 칩 바탕은 이 색을 흰 바탕에 옅게
/// 얹은 파스텔이고 글자는 본문 색이다.
class AppCalendarEventChip extends StatelessWidget {
  const AppCalendarEventChip({
    super.key,
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: OnCareSpacing.s2),
      padding: OnCareCalendar.eventChipPadding,
      decoration: BoxDecoration(
        color: OnCareColors.onWhite(color, OnCareCalendar.eventTintAlpha),
        borderRadius: OnCareRadius.xsAll,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.oncare
            .text(OnCareCalendar.eventChip)
            .copyWith(color: OnCareColors.textPrimary),
      ),
    );
  }
}

/// 월간 달력 범례(#1778) — 칩과 같은 파스텔 네모 견본 + 이름.
class AppCalendarLegend extends StatelessWidget {
  const AppCalendarLegend({super.key, required this.entries});

  /// (카테고리 원래 색, 이름) 목록. 견본 색은 [AppCalendarEventChip] 과 같게 옅힌다.
  final List<(Color, String)> entries;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = context.oncare
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textTertiary);
    return Wrap(
      spacing: OnCareSpacing.s12,
      runSpacing: OnCareSpacing.s4,
      children: <Widget>[
        for (final (Color color, String label) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: OnCareCalendar.legendSwatch,
                height: OnCareCalendar.legendSwatch,
                decoration: BoxDecoration(
                  color: OnCareColors.onWhite(
                    color,
                    OnCareCalendar.eventTintAlpha,
                  ),
                  borderRadius: const BorderRadius.all(
                    OnCareCalendar.legendSwatchRadius,
                  ),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Text(label, style: style),
            ],
          ),
      ],
    );
  }
}

/// 높이가 고정된 달력 시트 틀(#1778) — 화면 높이의 85%, 좌우 16.
///
/// [header] 를 위에 차례로 쌓고 [body] 가 남은 높이를 모두 갖는다(격자가 주 줄을
/// 늘린다). 아래는 시스템 내비게이션 바 인셋만큼 더 띄운다 — 인셋이 있는 기기에서
/// 마지막 주가 바 뒤로 들어가지 않는다(#669).
class AppCalendarSheetFrame extends StatelessWidget {
  const AppCalendarSheetFrame({
    super.key,
    required this.header,
    required this.body,
  });

  final List<Widget> header;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: OnCareCalendar.monthSheetHeightFactor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ...header,
            Expanded(child: body),
            SizedBox(
              height:
                  OnCareSpacing.s12 + MediaQuery.viewPaddingOf(context).bottom,
            ),
          ],
        ),
      ),
    );
  }
}

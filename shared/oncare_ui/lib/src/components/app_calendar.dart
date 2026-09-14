import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 이전/다음 기간 이동(#1697) — tonal 꺾쇠 버튼 두 개와 가운데 기간 라벨.
///
/// 회원 `_Arrow`, 트레이너 `_ChevronButton`·`_Chevron`, 대시보드 꺾쇠를 대체한다.
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

/// 주간 날짜 줄 — 요일 `caption` 600 + 날짜. 선택 = 브랜드 채움, 오늘 = 브랜드 글자.
///
/// [previousTooltip]·[nextTooltip] 을 둘 다 주면 줄 **양옆**에 이전/다음 주
/// 꺾쇠 버튼을 날짜 칸과 같은 높이 가운데에 그린다(회원앱 주간 달력).
/// 비우면 날짜 칸만 그린다 — 이동은 바깥의 [AppPeriodNav] 가 맡는다.
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

  /// 기록이 있는 날 — 날짜 아래 점.
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

  bool _selectable(DateTime day) {
    final DateTime? last = lastSelectableDay;
    if (last == null) return true;
    return !DateTime(
      day.year,
      day.month,
      day.day,
    ).isAfter(DateTime(last.year, last.month, last.day));
  }

  static bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final Widget strip = _days(context);
    if (previousTooltip == null || nextTooltip == null) return strip;
    return Row(
      children: <Widget>[
        _WeekStripArrow(
          icon: Icons.chevron_left_rounded,
          tooltip: previousTooltip!,
          onPressed: onPrevious,
        ),
        Expanded(child: strip),
        _WeekStripArrow(
          icon: Icons.chevron_right_rounded,
          tooltip: nextTooltip!,
          onPressed: onNext,
        ),
      ],
    );
  }

  Widget _days(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      children: <Widget>[
        for (int i = 0; i < days.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              enabled: _selectable(days[i]),
              selected: _same(days[i], selected),
              child: InkWell(
                borderRadius: OnCareRadius.mdAll,
                onTap: _selectable(days[i]) ? () => onSelected(days[i]) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: OnCareSpacing.s4,
                  ),
                  child: Column(
                    children: <Widget>[
                      // 영어 요일(Mon)은 한글 한 글자보다 넓다 — 말줄임 대신
                      // 통째로 줄여 무슨 요일인지 남긴다.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          weekdayLabels[i],
                          maxLines: 1,
                          style: tokens
                              .text(
                                OnCareTypography.strong(
                                  OnCareTypography.caption,
                                ),
                              )
                              .copyWith(
                                color: today != null && _same(days[i], today!)
                                    ? tokens.brand.primary
                                    : OnCareColors.textTertiary,
                              ),
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      Container(
                        width: tokens.density.chip,
                        height: tokens.density.chip,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _same(days[i], selected)
                              ? tokens.brand.primary
                              : Colors.transparent,
                          borderRadius: OnCareRadius.mdAll,
                        ),
                        child: Text(
                          '${days[i].day}',
                          style:
                              OnCareTypography.numeric(
                                tokens.text(OnCareTypography.label),
                              ).copyWith(
                                color: _same(days[i], selected)
                                    ? OnCareColors.textOnFill
                                    : today != null && _same(days[i], today!)
                                    ? tokens.brand.primary
                                    : OnCareColors.textPrimary,
                              ),
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      SizedBox(
                        height: OnCareSize.dot / 2,
                        child: markedDays.any((d) => _same(d, days[i]))
                            ? Container(
                                width: OnCareSize.dot / 2,
                                decoration: BoxDecoration(
                                  color: tokens.brand.primary,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// [AppWeekStrip] 양옆의 작은 원형 꺾쇠 — 옅은 브랜드 채움, 비활성은 흐리게.
class _WeekStripArrow extends StatelessWidget {
  const _WeekStripArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Opacity(
      opacity: onPressed == null ? OnCareAlpha.strong : 1,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: tokens.brand.surface,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: OnCareSize.avatarMedium,
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
    final bool isSelected =
        selected != null && AppWeekStrip._same(date, selected!);
    final bool isToday = today != null && AppWeekStrip._same(date, today!);
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

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/motion.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 고르기 칩(#1695, #1690 확정) — 성별·목표·필터.
///
/// 선택 = 옅은 브랜드 채움 + 브랜드 테두리 + 브랜드 글자. 체크 표시는 없다.
/// 높이는 밀도를 따른다(36/32), 반경 12.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;

  /// `null` 이면 비활성이다.
  final ValueChanged<bool>? onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool enabled = onSelected != null;
    final Color foreground = !enabled
        ? OnCareColors.textDisabled
        : selected
        ? tokens.brand.primary
        : OnCareColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? tokens.brand.surface : OnCareColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: OnCareRadius.mdAll,
          side: BorderSide(
            color: selected ? tokens.brand.border : OnCareColors.lineStrong,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => onSelected!(!selected) : null,
          child: Container(
            height: tokens.density.chip,
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: OnCareSize.iconSmall, color: foreground),
                  const SizedBox(width: OnCareSpacing.s4),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(OnCareTypography.label)
                        .copyWith(color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 세그먼트 토글 한 칸.
@immutable
class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 세그먼트 토글(#1690 확정) — 오늘/주/월 같은 보기 전환.
///
/// 입력 채움 알약 트랙 위에서 선택 칸만 브랜드로 꽉 채우고 흰 글자로 쓴다.
class AppSegmentedToggle<T> extends StatelessWidget {
  const AppSegmentedToggle({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expand = false,
  });

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// 부모 폭을 칸마다 똑같이 나눠 채울지.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final double height = tokens.density.chip;
    return Container(
      height: height,
      padding: const EdgeInsets.all(OnCareSpacing.s2),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceInput,
        borderRadius: OnCareRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          for (final AppSegment<T> segment in segments)
            _wrap(
              Semantics(
                button: true,
                selected: segment.value == selected,
                inMutuallyExclusiveGroup: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(segment.value),
                  child: AnimatedContainer(
                    duration: OnCareMotion.normal,
                    curve: OnCareMotion.curve,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: OnCareSpacing.s12,
                    ),
                    decoration: BoxDecoration(
                      color: segment.value == selected
                          ? tokens.brand.primary
                          : Colors.transparent,
                      borderRadius: OnCareRadius.mdAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (segment.icon != null) ...<Widget>[
                          Icon(
                            segment.icon,
                            size: OnCareSize.iconSmall,
                            color: segment.value == selected
                                ? OnCareColors.textOnFill
                                : OnCareColors.textSecondary,
                          ),
                          const SizedBox(width: OnCareSpacing.s4),
                        ],
                        Flexible(
                          child: Text(
                            segment.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens
                                .text(OnCareTypography.label)
                                .copyWith(
                                  color: segment.value == selected
                                      ? OnCareColors.textOnFill
                                      : OnCareColors.textSecondary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrap(Widget child) => expand ? Expanded(child: child) : child;
}

/// 태그 톤.
enum AppTagTone { neutral, brand, success, caution, danger }

/// 태그(#1695) — 알약·높이 24·`caption` 600·톤별 8% 채움 + 톤 글자.
class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    this.tone = AppTagTone.neutral,
    this.icon,
  });

  final String label;
  final AppTagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color accent = switch (tone) {
      AppTagTone.neutral => OnCareColors.textSecondary,
      AppTagTone.brand => tokens.brand.primary,
      AppTagTone.success => OnCareColors.success,
      AppTagTone.caution => OnCareColors.caution,
      AppTagTone.danger => OnCareColors.danger,
    };
    final Color fill = switch (tone) {
      AppTagTone.neutral => OnCareColors.surfaceInput,
      AppTagTone.brand => tokens.brand.surface,
      _ => OnCareColors.onWhite(accent, OnCareAlpha.subtle),
    };
    return Container(
      height: OnCareSize.tagHeight,
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: OnCareRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: OnCareSize.iconSmall, color: accent),
            const SizedBox(width: OnCareSpacing.s4),
          ],
          Text(
            label,
            maxLines: 1,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}

/// 카운트 배지 — 빨간 원, 최소 20, 99 를 넘으면 "99+".
class AppCountBadge extends StatelessWidget {
  const AppCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(
        minWidth: OnCareSize.countBadgeMin,
        minHeight: OnCareSize.countBadgeMin,
      ),
      padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s4),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: OnCareColors.danger,
        borderRadius: OnCareRadius.pillAll,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: context.oncare
            .text(OnCareTypography.strong(OnCareTypography.caption))
            .copyWith(color: OnCareColors.textOnFill, height: 1),
      ),
    );
  }
}

/// 상태 점 — 지름 8. 새 알림은 빨강.
class AppStatusDot extends StatelessWidget {
  const AppStatusDot({super.key, this.color = OnCareColors.danger});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: OnCareSize.dot,
      height: OnCareSize.dot,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 숫자 스테퍼 — 빼기·더하기 버튼(tonal)과 가운데 값. 두 앱의 스테퍼를 대체한다.
class AppNumberStepper extends StatelessWidget {
  const AppNumberStepper({
    super.key,
    required this.value,
    required this.onChanged,
    required this.decreaseTooltip,
    required this.increaseTooltip,
    this.min = 0,
    this.max = 999,
    this.step = 1,
    this.unit,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final String decreaseTooltip;
  final String increaseTooltip;
  final int min;
  final int max;
  final int step;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool enabled = onChanged != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppIconButton(
          icon: Icons.remove_rounded,
          tooltip: decreaseTooltip,
          variant: AppIconButtonVariant.tonal,
          onPressed: enabled && value - step >= min
              ? () => onChanged!(value - step)
              : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 64),
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '$value',
                  style: OnCareTypography.numeric(
                    tokens.text(OnCareTypography.titleMedium),
                  ).copyWith(color: OnCareColors.textPrimary),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: tokens
                        .text(OnCareTypography.bodySmall)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        AppIconButton(
          icon: Icons.add_rounded,
          tooltip: increaseTooltip,
          variant: AppIconButtonVariant.tonal,
          onPressed: enabled && value + step <= max
              ? () => onChanged!(value + step)
              : null,
        ),
      ],
    );
  }
}

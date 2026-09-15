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
              // 칸 폭이 정해진 칩(한 줄을 N 등분)에서도 라벨이 가운데에 선다.
              // 내용만큼의 칩은 폭이 곧 내용이라 모양이 같다.
              mainAxisAlignment: MainAxisAlignment.center,
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

/// 세그먼트 토글(#1690) — 오늘/이번 주/전체·식단/운동 같은 보기 전환.
///
/// 공용 토글로 옮기기 전 두 앱의 알약 토글 모양이다(#1777).
/// - 트랙: 알약, 안쪽 여백 3, 브랜드별 옅은 회색([OnCareBrand.segmentTrack]).
/// - 선택 칸: 알약, 브랜드 채움, 흰 굵은 글자.
/// - 선택 안 된 칸: 배경 없음, 브랜드별 회색 굵은 글자([OnCareBrand.segmentLabel]).
/// - 높이는 고정하지 않고 글자와 여백으로 정해진다. 그래서 밀도(칩 높이)와 무관하게
///   두 앱이 같은 크기로 선다.
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
    // 글자를 키운 화면에서는 칸 폭 합이 커져 토글 전체가 그만큼 줄어드므로 좌우
    // 여백을 좁힌다(#1058 · #1182). 앱은 배율을 상한에서 묶으므로 상한을 **넘는**
    // 경우만 좁힌다 — 이전 토글과 같은 기준이다.
    final double horizontalPadding =
        MediaQuery.textScalerOf(context).scale(1) >
            OnCareTypography.maxTextScale
        ? OnCareSize.segmentPaddingHorizontalCompact
        : OnCareSize.segmentPaddingHorizontal;
    return Container(
      padding: const EdgeInsets.all(OnCareSize.segmentTrackInset),
      decoration: BoxDecoration(
        color: tokens.brand.segmentTrack,
        borderRadius: OnCareRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          for (final AppSegment<T> segment in segments)
            _wrap(
              _segment(
                tokens,
                segment,
                selected: segment.value == selected,
                horizontalPadding: horizontalPadding,
              ),
            ),
        ],
      ),
    );
  }

  Widget _segment(
    OnCareTokens tokens,
    AppSegment<T> segment, {
    required bool selected,
    required double horizontalPadding,
  }) {
    final Color foreground = selected
        ? OnCareColors.textOnFill
        : tokens.brand.segmentLabel;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(segment.value),
        child: AnimatedContainer(
          duration: OnCareMotion.normal,
          curve: OnCareMotion.curve,
          // `alignment` 를 주지 않는다 — 주면 칸이 부모 높이만큼 늘어나 글자에
          // 맞춘 높이가 깨진다. 가운데 정렬은 안쪽 Row 가 맡는다.
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: OnCareSize.segmentPaddingVertical,
          ),
          decoration: BoxDecoration(
            color: selected ? tokens.brand.primary : Colors.transparent,
            borderRadius: OnCareRadius.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            // 폭을 나눠 받는 칸(`expand`)에서도 아이콘·라벨이 가운데에 선다.
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (segment.icon != null) ...<Widget>[
                Icon(
                  segment.icon,
                  size: OnCareSize.iconSmall,
                  color: foreground,
                ),
                const SizedBox(width: OnCareSpacing.s4),
              ],
              // 폭을 나눠 받는 칸(`expand`)에서만 줄임표가 생긴다. 내용만큼의
              // 토글은 부모가 폭을 묶지 않아 라벨이 온전하다(#1182).
              Flexible(
                child: Text(
                  segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.segment)
                      .copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
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
    // 한 자리 수는 좌우 여백 없이 원 안에 둬야 글자 폭 때문에 알약이 되지 않는다.
    final bool singleDigit = count < 10;
    return Container(
      constraints: const BoxConstraints(
        minWidth: OnCareSize.countBadgeMin,
        minHeight: OnCareSize.countBadgeMin,
      ),
      padding: singleDigit
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: OnCareSpacing.s4),
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

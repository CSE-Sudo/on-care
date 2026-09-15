import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';

/// 아이콘 버튼 종류(#1690 §8).
enum AppIconButtonVariant {
  /// 배경 없음.
  plain,

  /// 옅은 브랜드 채움 — 헤더 버튼·이전/다음 이동.
  tonal,

  /// 브랜드 채움 — 전송 버튼.
  filled,
}

/// 두 앱의 아이콘 버튼(#1692). 원형 버튼은 없다 — 배경이 있으면 반경 12 다.
///
/// 한 변은 밀도를 따른다(모바일 44, 웹 36). 아이콘 하나뿐이라 [tooltip] 이
/// 접근성 이름이 되므로 필수다.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.variant = AppIconButtonVariant.plain,
    this.color,
  });

  final IconData icon;
  final String tooltip;

  /// `null` 이면 비활성이다.
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;

  /// [AppIconButtonVariant.plain] 의 아이콘 색. 비우면 본문 색이다.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return _SquareIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      dimension: tokens.density.iconButton,
      iconSize: tokens.density.iconButtonIcon,
      background: switch (variant) {
        AppIconButtonVariant.plain => Colors.transparent,
        AppIconButtonVariant.tonal => tokens.brand.surface,
        AppIconButtonVariant.filled => tokens.brand.primary,
      },
      foreground: switch (variant) {
        AppIconButtonVariant.plain => color ?? OnCareColors.textPrimary,
        AppIconButtonVariant.tonal => tokens.brand.primary,
        AppIconButtonVariant.filled => OnCareColors.textOnFill,
      },
    );
  }
}

/// 뒤로가기 — 아이콘 묶음의 [OnCareIconSet.back](기본 `chevron_left_rounded`),
/// 아이콘 24·터치 44·배경 없음(#1690 확정, #1803).
///
/// 앱바·시트·다이얼로그·채팅 헤더가 모두 이 위젯을 쓴다. [onPressed] 를 비우면
/// 현재 경로를 닫는다.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _SquareIconButton(
      icon: AppIcon.setOf(context).back,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      dimension: OnCareSize.backCloseTouch,
      iconSize: OnCareSize.backCloseIcon,
      background: Colors.transparent,
      foreground: OnCareColors.textPrimary,
    );
  }
}

/// 닫기 — 아이콘 묶음의 [OnCareIconSet.close](기본 `close_rounded`), 아이콘 24·터치
/// 44·배경 없음(#1690 확정, #1803).
class AppCloseButton extends StatelessWidget {
  const AppCloseButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _SquareIconButton(
      icon: AppIcon.setOf(context).close,
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      dimension: OnCareSize.backCloseTouch,
      iconSize: OnCareSize.backCloseIcon,
      background: Colors.transparent,
      foreground: OnCareColors.textPrimary,
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.dimension,
    required this.iconSize,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double dimension;
  final double iconSize;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final bool filled = background != Colors.transparent;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: AppIcon(icon),
      style: ButtonStyle(
        fixedSize: WidgetStatePropertyAll<Size>(Size.square(dimension)),
        minimumSize: WidgetStatePropertyAll<Size>(Size.square(dimension)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.zero,
        ),
        iconSize: WidgetStatePropertyAll<double>(iconSize),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: OnCareRadius.mdAll),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled) && filled) {
            return OnCareColors.surfaceInput;
          }
          return background;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return OnCareColors.textDisabled;
          }
          return foreground;
        }),
        overlayColor: WidgetStatePropertyAll<Color>(
          (filled ? OnCareColors.textOnFill : foreground).withValues(
            alpha: OnCareAlpha.medium,
          ),
        ),
      ),
    );
  }
}

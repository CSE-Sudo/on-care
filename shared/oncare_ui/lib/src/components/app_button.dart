import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/density.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 버튼 종류(#1690 §8 확정).
enum AppButtonVariant {
  /// 브랜드 채움 — 화면·창의 주요 동작.
  primary,

  /// 흰 바탕 + 테두리 — 취소·보조 동작.
  secondary,

  /// 브랜드 글자 — 링크·가벼운 동작.
  text,

  /// 빨간 채움 — 확인창에서 위험 동작을 확정한다.
  destructive,

  /// 빨간 글자 — 화면 안에서 위험 동작 확인창을 연다.
  destructiveText,
}

/// 두 앱의 모든 글자 버튼(#1692).
///
/// 높이는 밀도를 따른다(모바일 52/44/32, 웹 44/36/28). 반경 12, 라벨 16/15/13
/// 굵기 600 은 두 앱이 같다. 그라디언트 버튼은 없다.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = OnCareButtonSize.medium,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
  });

  final String label;

  /// `null` 이면 비활성이다.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final OnCareButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  /// 처리 중이면 라벨 자리에 스피너를 두고 탭을 막는다. 모양은 활성 그대로다.
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final double height = tokens.density.buttonHeight(size);
    final (Color background, Color foreground, BorderSide? side) = switch (
      variant
    ) {
      AppButtonVariant.primary => (
        tokens.brand.primary,
        OnCareColors.textOnFill,
        null,
      ),
      AppButtonVariant.secondary => (
        OnCareColors.surfaceCard,
        OnCareColors.textPrimary,
        const BorderSide(color: OnCareColors.lineStrong),
      ),
      AppButtonVariant.text => (
        Colors.transparent,
        tokens.brand.primary,
        null,
      ),
      AppButtonVariant.destructive => (
        OnCareColors.danger,
        OnCareColors.textOnFill,
        null,
      ),
      AppButtonVariant.destructiveText => (
        Colors.transparent,
        OnCareColors.danger,
        null,
      ),
    };
    final bool filled = background != Colors.transparent;
    final TextStyle labelStyle = tokens.text(switch (size) {
      OnCareButtonSize.large => OnCareTypography.buttonLarge,
      OnCareButtonSize.medium => OnCareTypography.buttonMedium,
      OnCareButtonSize.small => OnCareTypography.buttonSmall,
    });
    final double iconSize = size == OnCareButtonSize.small
        ? OnCareSize.iconSmall
        : OnCareSize.iconMedium;
    final double horizontal = switch (size) {
      OnCareButtonSize.large => OnCareSpacing.s20,
      OnCareButtonSize.medium => OnCareSpacing.s16,
      OnCareButtonSize.small => OnCareSpacing.s12,
    };

    Color resolveForeground(Set<WidgetState> states) {
      if (states.contains(WidgetState.disabled)) {
        return OnCareColors.textDisabled;
      }
      return foreground;
    }

    final ButtonStyle style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(Size(height, height)),
      maximumSize: WidgetStatePropertyAll<Size>(Size(double.infinity, height)),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: horizontal),
      ),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: OnCareRadius.mdAll),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle>(labelStyle),
      elevation: const WidgetStatePropertyAll<double>(0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled) && filled) {
          return OnCareColors.surfaceInput;
        }
        return background;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(resolveForeground),
      // 아이콘도 글자와 같은 색이다. 비워 두면 테마의 글자 버튼 아이콘 색(브랜드)이
      // 적용돼 브랜드 채움 위에서 아이콘이 보이지 않는다.
      iconColor: WidgetStateProperty.resolveWith(resolveForeground),
      overlayColor: WidgetStatePropertyAll<Color>(
        (filled ? OnCareColors.textOnFill : foreground).withValues(
          alpha: OnCareAlpha.medium,
        ),
      ),
      side: side == null
          ? null
          : WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return const BorderSide(color: OnCareColors.lineSubtle);
              }
              return side;
            }),
    );

    final Widget content = loading
        ? SizedBox.square(
            dimension: OnCareSize.inlineSpinner,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foreground,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leadingIcon != null) ...<Widget>[
                AppIcon(leadingIcon, size: iconSize),
                const SizedBox(width: OnCareSpacing.s8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailingIcon != null) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s4),
                AppIcon(trailingIcon, size: iconSize),
              ],
            ],
          );

    Widget button = TextButton(
      style: style,
      onPressed: onPressed,
      child: content,
    );
    if (loading) {
      button = Semantics(
        label: label,
        child: AbsorbPointer(child: button),
      );
    }
    return fullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// 확인창·시트·폼 하단의 두 버튼 — [취소] 왼쪽, [확인] 오른쪽, 폭 반반(#1690 확정).
class AppButtonPair extends StatelessWidget {
  const AppButtonPair({
    super.key,
    required this.cancelLabel,
    required this.onCancel,
    required this.confirmLabel,
    required this.onConfirm,
    this.destructive = false,
    this.size = OnCareButtonSize.medium,
    this.confirmLoading = false,
    this.cancelKey,
    this.confirmKey,
  });

  final String cancelLabel;
  final VoidCallback? onCancel;
  final String confirmLabel;
  final VoidCallback? onConfirm;

  /// 확정이 위험 동작이면 빨간 채움으로 그린다.
  final bool destructive;
  final OnCareButtonSize size;
  final bool confirmLoading;

  /// 두 버튼에 붙일 키. 같은 라벨이 화면에 여럿일 때 테스트·자동화가 두 버튼을
  /// 따로 지목한다.
  final Key? cancelKey;
  final Key? confirmKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: AppButton(
            key: cancelKey,
            label: cancelLabel,
            onPressed: onCancel,
            variant: AppButtonVariant.secondary,
            size: size,
            fullWidth: true,
          ),
        ),
        const SizedBox(width: OnCareSpacing.buttonGap),
        Expanded(
          child: AppButton(
            key: confirmKey,
            label: confirmLabel,
            onPressed: onConfirm,
            variant: destructive
                ? AppButtonVariant.destructive
                : AppButtonVariant.primary,
            size: size,
            loading: confirmLoading,
            fullWidth: true,
          ),
        ),
      ],
    );
  }
}

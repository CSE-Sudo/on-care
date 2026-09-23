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

  /// 흰 바탕 + 브랜드 테두리·글자 — 화면 머리에 놓이는 보조 동작. (#1975)
  ///
  /// [primary] 와 [secondary] 사이다. 브랜드 색을 띠어 무엇을 하는 자리인지
  /// 보이되, 채우지 않아 그 화면의 본문보다 앞서지 않는다. AI 코치 머리의
  /// `기록` 이 채움이던 동안에는 대화보다 먼저 눈에 들었다.
  brandOutline,

  /// 투명 바탕 + 진한 브랜드(`strong`) 테두리·글자 — 놓인 바탕에 녹는 보조 동작.
  /// (#2180, #2184)
  ///
  /// 바탕을 칠하지 않아 페이지 배경 위에서는 페이지 색, 흰 카드 위에서는 흰색이
  /// 된다. [secondary] 의 흰 채움은 회색 페이지 위에서 버튼만 떠 보였고, 흰 카드
  /// 안의 `거절` 은 빨간 글자만 있어 옆 `승인` 과 모양이 달랐다.
  strongOutline,

  /// 진한 브랜드(`strong`) 채움 + 흰 글자 — 옅은 브랜드 바탕 위의 바로가기. (#2202)
  ///
  /// [primary] 의 메인 색 채움은 옅은 남색 안내 카드(트레이너 웹 활동 피드백)
  /// 위에서 바탕과 가까워 묻힌다. 한 단계 진한 색으로 채워야 바탕과 갈린다.
  strong,

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
    this.leadingGlyph,
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

  /// 글꼴 하나로 그릴 수 없는 마크를 앞자리에 대신 그린다(예: [AppAiChatGlyph]).
  /// 주면 [leadingIcon] 대신 이것이 그려진다.
  final Widget? leadingGlyph;
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
      AppButtonVariant.brandOutline => (
        OnCareColors.surfaceCard,
        tokens.brand.primary,
        BorderSide(color: tokens.brand.primary),
      ),
      AppButtonVariant.strongOutline => (
        Colors.transparent,
        tokens.brand.strong,
        BorderSide(color: tokens.brand.strong),
      ),
      AppButtonVariant.strong => (
        tokens.brand.strong,
        OnCareColors.textOnFill,
        null,
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
              if (leadingGlyph != null) ...<Widget>[
                SizedBox.square(dimension: iconSize, child: leadingGlyph),
                const SizedBox(width: OnCareSpacing.s8),
              ] else if (leadingIcon != null) ...<Widget>[
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

    // 처리 중에는 실제 핸들러를 넘기지 않고 빈 동작을 넘긴다(#2057).
    // - null 을 넘기면 비활성 모양(채움은 옅은 회색)이 되어 흰 스피너가 묻힌다.
    //   호출부가 중복 탭을 막으려고 `busy ? null : save` 로 넘기는 일이 흔하다.
    // - 실제 핸들러를 넘기면 아래 AbsorbPointer 가 포인터만 막고, 초점이 간
    //   버튼의 키보드 Enter·Space 는 그대로 통과해 한 번 더 제출된다.
    Widget button = TextButton(
      style: style,
      onPressed: loading ? _ignorePress : onPressed,
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

/// 처리 중인 [AppButton] 이 활성 모양을 유지하면서 아무것도 하지 않도록 넘기는 동작.
void _ignorePress() {}

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

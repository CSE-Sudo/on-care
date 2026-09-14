import 'package:flutter/material.dart';

import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/brand.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/density.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/layout.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 두 앱의 `ThemeData` 를 한 곳에서 만든다(#1691).
///
/// Material 위젯이 테마를 받지 못해 M3 기본값(알약 40px 버튼, 반경 28
/// 다이얼로그, 22px 다이얼로그 제목, 밑줄 입력창, 체크 표시 칩 …)으로 그려지는
/// 일이 없도록, 앱이 쓰는 하위 테마를 전부 규격값으로 채운다. 화면에 남아 있는
/// Material 위젯도 컴포넌트로 옮기기 전부터 같은 모양으로 보인다.
///
/// 라이트 테마만 있다 — 제품 디자인이 라이트 전용이다(#1604).
class OnCareTheme {
  OnCareTheme._();

  /// [brand] 와 [density] 로 테마를 만든다.
  ///
  /// [legacyTextScale] 은 앱이 아직 전역 글자 배율을 얹고 있을 때 그 값을 넘긴다.
  /// 테마 글자 크기가 그만큼 나뉘어 **보이는 크기 = 역할 크기** 가 유지된다
  /// ([OnCareTypography.compensate]). 전역 배율을 걷는 정리 이슈(#1707)에서 뺀다.
  static ThemeData light({
    required OnCareBrand brand,
    required OnCareDensity density,
    double legacyTextScale = 1.0,
  }) {
    TextStyle t(TextStyle style) =>
        OnCareTypography.compensate(style, legacyTextScale);

    final ColorScheme scheme = ColorScheme(
      brightness: Brightness.light,
      primary: brand.primary,
      onPrimary: OnCareColors.textOnFill,
      primaryContainer: brand.surface,
      onPrimaryContainer: brand.strong,
      secondary: brand.strong,
      onSecondary: OnCareColors.textOnFill,
      secondaryContainer: brand.surface,
      onSecondaryContainer: brand.strong,
      tertiary: brand.strong,
      onTertiary: OnCareColors.textOnFill,
      error: OnCareColors.danger,
      onError: OnCareColors.textOnFill,
      errorContainer: OnCareColors.onWhite(
        OnCareColors.danger,
        OnCareAlpha.subtle,
      ),
      onErrorContainer: OnCareColors.danger,
      surface: OnCareColors.surfaceCard,
      onSurface: OnCareColors.textPrimary,
      surfaceContainerLowest: OnCareColors.surfaceCard,
      surfaceContainerLow: OnCareColors.surfaceCard,
      surfaceContainer: OnCareColors.surfaceInput,
      surfaceContainerHigh: brand.surface,
      surfaceContainerHighest: OnCareColors.surfaceInput,
      onSurfaceVariant: OnCareColors.textSecondary,
      outline: OnCareColors.lineStrong,
      outlineVariant: OnCareColors.lineSubtle,
      shadow: const Color(0xFF000000),
      scrim: OnCareColors.scrim,
      inverseSurface: OnCareColors.overlayInk,
      onInverseSurface: OnCareColors.textOnFill,
      inversePrimary: OnCareColors.overlayAction,
      surfaceTint: Colors.transparent,
    );

    const OutlinedBorder controlShape = RoundedRectangleBorder(
      borderRadius: OnCareRadius.mdAll,
    );

    ButtonStyle baseButton({
      required Color background,
      required Color foreground,
      BorderSide? side,
    }) {
      return ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(density.buttonMedium, density.buttonMedium),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: OnCareSpacing.s16),
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(controlShape),
        textStyle: WidgetStatePropertyAll<TextStyle>(
          t(OnCareTypography.buttonMedium),
        ),
        iconSize: const WidgetStatePropertyAll<double>(OnCareSize.iconMedium),
        elevation: const WidgetStatePropertyAll<double>(0),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return background == Colors.transparent
                ? Colors.transparent
                : OnCareColors.surfaceInput;
          }
          return background;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return OnCareColors.textDisabled;
          }
          return foreground;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return OnCareColors.textDisabled;
          }
          return foreground;
        }),
        overlayColor: WidgetStatePropertyAll<Color>(
          foreground.withValues(alpha: OnCareAlpha.subtle),
        ),
        side: side == null
            ? null
            : WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return const BorderSide(color: OnCareColors.lineSubtle);
                }
                return side;
              }),
        tapTargetSize: density.isWeb
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded,
      );
    }

    final ButtonStyle primaryButton = baseButton(
      background: brand.primary,
      foreground: OnCareColors.textOnFill,
    );
    final ButtonStyle secondaryButton = baseButton(
      background: OnCareColors.surfaceCard,
      foreground: OnCareColors.textPrimary,
      side: const BorderSide(color: OnCareColors.lineStrong),
    );
    final ButtonStyle textButton = baseButton(
      background: Colors.transparent,
      foreground: brand.primary,
    ).copyWith(
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
      ),
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: OnCareRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    const MenuStyle menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll<Color>(OnCareColors.surfaceCard),
      surfaceTintColor: WidgetStatePropertyAll<Color>(Colors.transparent),
      elevation: WidgetStatePropertyAll<double>(
        OnCareShadows.overlayElevation,
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: OnCareRadius.mdAll,
          side: BorderSide(color: OnCareColors.lineStrong),
        ),
      ),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
      ),
    );

    final EdgeInsets dialogInset = density.isWeb
        ? const EdgeInsets.fromLTRB(
            OnCareSpacing.s24,
            OnCareLayout.dialogTopClearance,
            OnCareSpacing.s24,
            OnCareSpacing.s24,
          )
        : const EdgeInsets.symmetric(
            horizontal: OnCareSpacing.s20,
            vertical: OnCareSpacing.s24,
          );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: OnCareTypography.fontFamily,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: density.isWeb
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
    );

    return base.copyWith(
      scaffoldBackgroundColor: OnCareColors.surfacePage,
      canvasColor: OnCareColors.surfaceCard,
      dividerColor: OnCareColors.lineSubtle,
      textTheme: OnCareTypography.textTheme(
        color: OnCareColors.textPrimary,
        legacyTextScale: legacyTextScale,
      ),
      iconTheme: const IconThemeData(
        color: OnCareColors.textPrimary,
        size: OnCareSize.iconLarge,
      ),
      extensions: <ThemeExtension<dynamic>>[
        OnCareTokens(brand: brand, density: density),
      ],

      // --- 버튼 ---
      filledButtonTheme: FilledButtonThemeData(style: primaryButton),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryButton),
      textButtonTheme: TextButtonThemeData(style: textButton),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll<Size>(
            Size.square(density.iconButton),
          ),
          iconSize: WidgetStatePropertyAll<double>(density.iconButtonIcon),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(controlShape),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return OnCareColors.textDisabled;
            }
            return OnCareColors.textPrimary;
          }),
          overlayColor: WidgetStatePropertyAll<Color>(
            brand.primary.withValues(alpha: OnCareAlpha.subtle),
          ),
          tapTargetSize: density.isWeb
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand.primary,
        foregroundColor: OnCareColors.textOnFill,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: controlShape,
        extendedTextStyle: t(OnCareTypography.buttonMedium),
      ),

      // --- 입력 ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: OnCareColors.surfaceInput,
        isDense: true,
        constraints: BoxConstraints(minHeight: density.inputMedium),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s12,
          vertical: OnCareSpacing.s8,
        ),
        hintStyle: t(
          OnCareTypography.body,
        ).copyWith(color: OnCareColors.textTertiary),
        labelStyle: t(
          OnCareTypography.label,
        ).copyWith(color: OnCareColors.textSecondary),
        floatingLabelStyle: t(
          OnCareTypography.label,
        ).copyWith(color: brand.primary),
        helperStyle: t(
          OnCareTypography.caption,
        ).copyWith(color: OnCareColors.textTertiary),
        errorStyle: t(
          OnCareTypography.caption,
        ).copyWith(color: OnCareColors.danger),
        prefixIconColor: OnCareColors.textTertiary,
        suffixIconColor: OnCareColors.textTertiary,
        border: inputBorder(OnCareColors.lineStrong),
        enabledBorder: inputBorder(OnCareColors.lineStrong),
        disabledBorder: inputBorder(OnCareColors.lineSubtle),
        focusedBorder: inputBorder(brand.primary, OnCareSize.focusBorder),
        errorBorder: inputBorder(OnCareColors.danger),
        focusedErrorBorder: inputBorder(
          OnCareColors.danger,
          OnCareSize.focusBorder,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: menuStyle,
        textStyle: t(OnCareTypography.body),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: OnCareColors.surfaceCard,
        selectedColor: brand.surface,
        disabledColor: OnCareColors.surfaceInput,
        surfaceTintColor: Colors.transparent,
        side: const BorderSide(color: OnCareColors.lineStrong),
        shape: controlShape,
        showCheckmark: false,
        labelStyle: t(
          OnCareTypography.label,
        ).copyWith(color: OnCareColors.textPrimary),
        secondaryLabelStyle: t(
          OnCareTypography.label,
        ).copyWith(color: brand.primary),
        padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
        iconTheme: const IconThemeData(size: OnCareSize.iconSmall),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll<Color>(
          OnCareColors.surfaceCard,
        ),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brand.primary;
          return OnCareColors.lineStrong;
        }),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brand.primary;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll<Color>(
          OnCareColors.textOnFill,
        ),
        side: const BorderSide(color: OnCareColors.lineStrong, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: OnCareRadius.xsAll),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return brand.primary;
          return OnCareColors.lineStrong;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: brand.primary,
        inactiveTrackColor: OnCareColors.surfaceInput,
        thumbColor: brand.primary,
      ),

      // --- 창 ---
      dialogTheme: DialogThemeData(
        backgroundColor: OnCareColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: OnCareShadows.overlayElevation,
        shape: const RoundedRectangleBorder(borderRadius: OnCareRadius.xlAll),
        titleTextStyle: t(
          OnCareTypography.titleMedium,
        ).copyWith(color: OnCareColors.textPrimary),
        contentTextStyle: t(
          OnCareTypography.body,
        ).copyWith(color: OnCareColors.textSecondary),
        insetPadding: dialogInset,
        actionsPadding: const EdgeInsets.fromLTRB(
          OnCareSpacing.s24,
          0,
          OnCareSpacing.s24,
          OnCareSpacing.s24,
        ),
        barrierColor: OnCareColors.scrim,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: OnCareColors.surfaceCard,
        modalBackgroundColor: OnCareColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: OnCareColors.scrim,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: OnCareRadius.sheetTop,
        ),
        dragHandleColor: OnCareColors.lineStrong,
        dragHandleSize: const Size(
          OnCareSize.sheetHandleWidth,
          OnCareSize.sheetHandleHeight,
        ),
        // Material 3 는 모달 시트를 640dp 에서 막는다. 페이지와 같은 폭까지
        // 넓어지도록 경로 단의 상한을 콘텐츠 최대 폭으로 올린다.
        constraints: BoxConstraints(
          maxWidth: density.isWeb
              ? OnCareLayout.dialogMedium
              : OnCareLayout.mobileContentMaxWidth,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: OnCareColors.overlayInk,
        contentTextStyle: t(
          OnCareTypography.bodySmall,
        ).copyWith(color: OnCareColors.textOnFill),
        actionTextColor: OnCareColors.overlayAction,
        closeIconColor: OnCareColors.textOnFill,
        elevation: OnCareShadows.overlayElevation,
        insetPadding: const EdgeInsets.fromLTRB(
          OnCareSpacing.s16,
          OnCareSpacing.s4,
          OnCareSpacing.s16,
          OnCareSpacing.s12,
        ),
        shape: const RoundedRectangleBorder(borderRadius: OnCareRadius.lgAll),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: OnCareColors.overlayInk,
          borderRadius: OnCareRadius.smAll,
        ),
        textStyle: t(
          OnCareTypography.caption,
        ).copyWith(color: OnCareColors.textOnFill),
        padding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s8,
          vertical: OnCareSpacing.s4,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: OnCareColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: OnCareShadows.overlayElevation,
        shape: const RoundedRectangleBorder(
          borderRadius: OnCareRadius.mdAll,
          side: BorderSide(color: OnCareColors.lineStrong),
        ),
        textStyle: t(
          OnCareTypography.bodySmall,
        ).copyWith(color: OnCareColors.textPrimary),
        menuPadding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
      ),
      menuTheme: const MenuThemeData(style: menuStyle),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll<Size>(Size(0, density.menuItem)),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(
            t(OnCareTypography.bodySmall),
          ),
          foregroundColor: const WidgetStatePropertyAll<Color>(
            OnCareColors.textPrimary,
          ),
          iconSize: const WidgetStatePropertyAll<double>(OnCareSize.iconMedium),
          overlayColor: WidgetStatePropertyAll<Color>(brand.surface),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: OnCareColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: OnCareRadius.xlAll),
        headerBackgroundColor: OnCareColors.surfaceCard,
        headerForegroundColor: OnCareColors.textPrimary,
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return OnCareColors.textOnFill;
          }
          return brand.primary;
        }),
        todayBorder: BorderSide(color: brand.primary),
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: OnCareColors.surfaceCard,
        dialBackgroundColor: OnCareColors.surfaceInput,
        shape: RoundedRectangleBorder(borderRadius: OnCareRadius.xlAll),
      ),

      // --- 표면·목록 ---
      cardTheme: const CardThemeData(
        color: OnCareColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: OnCareRadius.xlAll,
          side: BorderSide(color: OnCareColors.lineSubtle),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: OnCareColors.lineSubtle,
        thickness: OnCareSize.hairline,
        space: OnCareSize.hairline,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: OnCareSpacing.s16,
        ),
        minVerticalPadding: OnCareSpacing.s12,
        minTileHeight: density.listRowMin,
        shape: controlShape,
        titleTextStyle: t(
          OnCareTypography.bodyLarge,
        ).copyWith(color: OnCareColors.textPrimary),
        subtitleTextStyle: t(
          OnCareTypography.bodySmall,
        ).copyWith(color: OnCareColors.textSecondary),
        iconColor: OnCareColors.textSecondary,
        selectedColor: brand.primary,
        selectedTileColor: brand.surface,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand.primary,
        linearTrackColor: OnCareColors.surfaceInput,
        circularTrackColor: Colors.transparent,
        linearMinHeight: OnCareSize.progressBar,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: OnCareColors.danger,
        textColor: OnCareColors.textOnFill,
        smallSize: OnCareSize.dot,
        largeSize: OnCareSize.countBadgeMin,
        textStyle: t(OnCareTypography.strong(OnCareTypography.caption)),
      ),

      // --- 내비게이션 ---
      appBarTheme: AppBarTheme(
        backgroundColor: OnCareColors.surfaceCard,
        foregroundColor: OnCareColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: !density.isWeb,
        titleTextStyle: t(
          OnCareTypography.titleMedium,
        ).copyWith(color: OnCareColors.textPrimary),
        iconTheme: const IconThemeData(
          color: OnCareColors.textPrimary,
          size: OnCareSize.backCloseIcon,
        ),
        actionsIconTheme: const IconThemeData(
          color: OnCareColors.textPrimary,
          size: OnCareSize.iconLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: OnCareColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final TextStyle style = t(
            OnCareTypography.strong(OnCareTypography.caption),
          );
          return states.contains(WidgetState.selected)
              ? style.copyWith(color: brand.primary)
              : style.copyWith(color: OnCareColors.textTertiary);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            size: OnCareSize.iconLarge,
            color: states.contains(WidgetState.selected)
                ? brand.primary
                : OnCareColors.textTertiary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: OnCareColors.surfaceCard,
        indicatorColor: brand.surface,
        selectedIconTheme: IconThemeData(
          color: brand.primary,
          size: OnCareSize.iconLarge,
        ),
        unselectedIconTheme: const IconThemeData(
          color: OnCareColors.textSecondary,
          size: OnCareSize.iconLarge,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: OnCareColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        width: OnCareLayout.sidebarWidth,
        shape: RoundedRectangleBorder(),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(6),
        radius: OnCareRadius.pill,
        thumbColor: WidgetStatePropertyAll<Color>(
          OnCareColors.textTertiary.withValues(alpha: OnCareAlpha.strong),
        ),
      ),
    );
  }
}

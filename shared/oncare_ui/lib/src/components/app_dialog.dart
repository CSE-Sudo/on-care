import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_button.dart';
import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/layout.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 웹 다이얼로그 폭(#1690 확정). 모바일에서는 크기와 무관하게 최대 400 이다.
enum AppDialogSize {
  /// 400 — 확인·삭제 확인.
  small,

  /// 560 — 입력 폼.
  medium,

  /// 800 — 상세·미리보기·상담함.
  large,
}

/// 두 앱의 다이얼로그 틀(#1693).
///
/// 반경 20, 흰 바탕, 안쪽 24, 최대 높이 화면 85%. 넘치면 본문만 스크롤한다.
/// 헤더는 `titleMedium` 제목과 닫기 X, 하단은 보통 [AppButtonPair] 다.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.title,
    required this.child,
    this.footer,
    this.size = AppDialogSize.small,
    this.showClose = true,
    this.bodyPadding,
  });

  final String? title;
  final Widget child;
  final Widget? footer;
  final AppDialogSize size;

  /// 헤더에 닫기 X 를 둘지. 확인창처럼 하단 버튼으로만 닫는 창은 끈다.
  final bool showClose;

  /// 본문 안쪽. 미리보기처럼 가장자리까지 채울 때만 바꾼다.
  final EdgeInsetsGeometry? bodyPadding;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Size screen = MediaQuery.sizeOf(context);
    final double maxWidth = tokens.density.isWeb
        ? switch (size) {
            AppDialogSize.small => OnCareLayout.dialogSmall,
            AppDialogSize.medium => OnCareLayout.dialogMedium,
            AppDialogSize.large => OnCareLayout.dialogLarge,
          }
        : OnCareLayout.mobileDialogMaxWidth;
    final bool hasHeader = title != null || showClose;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minWidth: tokens.density.isWeb ? maxWidth : 0,
          maxHeight: screen.height * OnCareLayout.dialogMaxHeightFactor,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (hasHeader)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  OnCareSpacing.dialogPadding,
                  showClose ? OnCareSpacing.s12 : OnCareSpacing.dialogPadding,
                  showClose ? OnCareSpacing.s12 : OnCareSpacing.dialogPadding,
                  0,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: title == null
                          ? const SizedBox.shrink()
                          : Text(
                              title!,
                              style: tokens
                                  .text(OnCareTypography.titleMedium)
                                  .copyWith(color: OnCareColors.textPrimary),
                            ),
                    ),
                    if (showClose) const AppCloseButton(),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding:
                    bodyPadding ??
                    EdgeInsets.fromLTRB(
                      OnCareSpacing.dialogPadding,
                      hasHeader ? OnCareSpacing.s12 : OnCareSpacing.dialogPadding,
                      OnCareSpacing.dialogPadding,
                      footer == null ? OnCareSpacing.dialogPadding : 0,
                    ),
                child: DefaultTextStyle.merge(
                  style: tokens
                      .text(OnCareTypography.body)
                      .copyWith(color: OnCareColors.textSecondary),
                  child: child,
                ),
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.all(OnCareSpacing.dialogPadding),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// [AppDialog] 를 띄운다. 배경 막 색·반경은 테마가 정한다.
///
/// [dismissible] 을 끄면 바깥을 눌러도, 뒤로가기를 눌러도 닫히지 않는다 — 창 안의
/// 버튼으로 답해야만 닫히는 창이다. 창 안 버튼이 부르는 `Navigator.pop` 은 그대로
/// 닫는다. [barrierDismissible] 은 바깥 누르기만 막는다.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible && barrierDismissible,
    builder: dismissible
        ? builder
        : (BuildContext dialogContext) =>
              PopScope<T>(canPop: false, child: builder(dialogContext)),
  );
}

/// 확인창 — 제목·설명·반반 버튼. 확정하면 `true` 다(#1690 확정).
///
/// [destructive] 면 확정 버튼이 빨간 채움이다. 제목 없는 확인창은 만들지 않는다.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final bool? result = await showAppDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppDialog(
      title: title,
      showClose: false,
      footer: AppButtonPair(
        cancelLabel:
            cancelLabel ??
            MaterialLocalizations.of(dialogContext).cancelButtonLabel,
        onCancel: () => Navigator.pop(dialogContext, false),
        confirmLabel: confirmLabel,
        onConfirm: () => Navigator.pop(dialogContext, true),
        destructive: destructive,
      ),
      child: message == null ? const SizedBox.shrink() : Text(message),
    ),
  );
  return result ?? false;
}

/// 바텀시트 틀 — 모바일 입력·선택 전용(#1690 확정). 웹에서는 [AppDialog] 를 쓴다.
///
/// 위 모서리 20, 핸들 36×4, 최대 높이 90%, 안쪽 20. 헤더는 `titleMedium` 제목과
/// 닫기 X, 하단 버튼은 키보드 위에 붙는다.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.footer,
    this.showClose = true,
  });

  final String? title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final MediaQueryData media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: media.size.height * OnCareLayout.sheetMaxHeightFactor,
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            Center(
              child: Container(
                width: OnCareLayout.sheetHandleWidth,
                height: OnCareLayout.sheetHandleHeight,
                decoration: const BoxDecoration(
                  color: OnCareColors.lineStrong,
                  borderRadius: OnCareRadius.pillAll,
                ),
              ),
            ),
            if (title != null || showClose)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  OnCareSpacing.sheetPadding,
                  OnCareSpacing.s8,
                  OnCareSpacing.s8,
                  0,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (title != null)
                            Text(
                              title!,
                              style: tokens
                                  .text(OnCareTypography.titleMedium)
                                  .copyWith(color: OnCareColors.textPrimary),
                            ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: tokens
                                  .text(OnCareTypography.bodySmall)
                                  .copyWith(color: OnCareColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    if (showClose) const AppCloseButton(),
                  ],
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(OnCareSpacing.sheetPadding),
                child: child,
              ),
            ),
            if (footer != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OnCareSpacing.sheetPadding,
                    0,
                    OnCareSpacing.sheetPadding,
                    OnCareSpacing.sheetPadding,
                  ),
                  child: footer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// [AppSheet] 를 띄운다.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    builder: builder,
  );
}

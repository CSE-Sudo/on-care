import 'dart:async';

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/icons.dart';
import 'package:oncare_ui/src/tokens/layout.dart';
import 'package:oncare_ui/src/tokens/motion.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 토스트 종류. 바탕색은 종류와 무관하게 하나고 아이콘만 다르다.
enum AppToastType { success, error, info }

OverlayEntry? _current;

/// 화면 위쪽에 잠깐 떴다 사라지는 알림(#1693). 두 앱이 같은 모양이다.
///
/// 루트 오버레이에 그려 다이얼로그·시트 위에서도 보인다. 새 토스트가 뜨면 앞의
/// 것은 바로 닫힌다. 실패는 [OnCareMotion.toastErrorVisible], 동작 버튼이 있으면
/// [OnCareMotion.toastActionVisible] 만큼 머문다.
/// 토스트 손잡이 — 화면이 닫힌 **뒤에** 도착하는 결과도 띄울 수 있게 루트 오버레이와
/// 토큰을 미리 잡아 둔다. 시트를 닫고 저장 응답을 기다리는 흐름에서 쓴다.
class AppToastHost {
  const AppToastHost._(this._overlay, this._tokens);

  /// 지금 화면에서 손잡이를 잡는다.
  factory AppToastHost.of(BuildContext context) =>
      AppToastHost._(Overlay.of(context, rootOverlay: true), context.oncare);

  final OverlayState _overlay;
  final OnCareTokens _tokens;

  /// 토스트를 띄운다.
  void show(
    String message, {
    AppToastType type = AppToastType.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) => _insertToast(_overlay, _tokens, message, type, actionLabel, onAction);
}

/// 화면 위쪽에 잠깐 떴다 사라지는 알림(#1693). 두 앱이 같은 모양이다.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastType type = AppToastType.info,
  String? actionLabel,
  VoidCallback? onAction,
}) => AppToastHost.of(
  context,
).show(message, type: type, actionLabel: actionLabel, onAction: onAction);

void _insertToast(
  OverlayState overlay,
  OnCareTokens tokens,
  String message,
  AppToastType type,
  String? actionLabel,
  VoidCallback? onAction,
) {
  _current?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext _) => _ToastView(
      tokens: tokens,
      message: message,
      type: type,
      actionLabel: actionLabel,
      onAction: onAction,
      visibleFor: actionLabel != null
          ? OnCareMotion.toastActionVisible
          : type == AppToastType.error
          ? OnCareMotion.toastErrorVisible
          : OnCareMotion.toastVisible,
      onDismissed: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.tokens,
    required this.message,
    required this.type,
    required this.actionLabel,
    required this.onAction,
    required this.visibleFor,
    required this.onDismissed,
  });

  final OnCareTokens tokens;
  final String message;
  final AppToastType type;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration visibleFor;
  final VoidCallback onDismissed;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OnCareMotion.toastEnter,
    reverseDuration: OnCareMotion.toastExit,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.visibleFor, _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = widget.tokens;
    final OnCareIconSet icons = AppIcon.setOf(context);
    final (IconData icon, Color iconColor) = switch (widget.type) {
      AppToastType.success => (icons.success, OnCareColors.overlaySuccess),
      AppToastType.error => (icons.error, OnCareColors.overlayError),
      AppToastType.info => (icons.info, OnCareColors.overlayAction),
    };
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: OnCareMotion.curve,
      reverseCurve: OnCareMotion.exitCurve,
    );
    return Positioned(
      top: MediaQuery.paddingOf(context).top + OnCareSpacing.s12,
      left: OnCareSpacing.s16,
      right: OnCareSpacing.s16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.3),
                end: Offset.zero,
              ).animate(curved),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OnCareLayout.toastMaxWidth,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: OnCareSpacing.s16,
                      vertical: OnCareSpacing.s12,
                    ),
                    decoration: const BoxDecoration(
                      color: OnCareColors.overlayInk,
                      borderRadius: OnCareRadius.lgAll,
                      boxShadow: OnCareShadows.overlay,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          AppIcon(
                            icon,
                            size: OnCareSize.iconMedium,
                            color: iconColor,
                          ),
                          const SizedBox(width: OnCareSpacing.s8),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: tokens
                                  .text(OnCareTypography.bodySmall)
                                  .copyWith(color: OnCareColors.textOnFill),
                            ),
                          ),
                          if (widget.actionLabel != null) ...<Widget>[
                            const SizedBox(width: OnCareSpacing.s12),
                            GestureDetector(
                              onTap: () {
                                widget.onAction?.call();
                                _dismiss();
                              },
                              child: Text(
                                widget.actionLabel!,
                                style: tokens
                                    .text(OnCareTypography.label)
                                    .copyWith(
                                      color: OnCareColors.overlayAction,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

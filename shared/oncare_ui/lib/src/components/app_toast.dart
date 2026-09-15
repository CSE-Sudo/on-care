import 'dart:async';

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
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
  ///
  /// [rewardLabel] 을 주면 메시지 옆에 ★ 과 그 글자(`+50P`)를 붙이고 한 번
  /// 반짝인다(#1786). 받은 것이 없으면 넘기지 않는다 — 빈 표시는 그리지 않는다.
  void show(
    String message, {
    AppToastType type = AppToastType.info,
    String? actionLabel,
    VoidCallback? onAction,
    String? rewardLabel,
  }) => _insertToast(
    _overlay,
    _tokens,
    message,
    type,
    actionLabel,
    onAction,
    rewardLabel,
  );
}

/// 화면 위쪽에 잠깐 떴다 사라지는 알림(#1693). 두 앱이 같은 모양이다.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastType type = AppToastType.info,
  String? actionLabel,
  VoidCallback? onAction,
  String? rewardLabel,
}) => AppToastHost.of(context).show(
  message,
  type: type,
  actionLabel: actionLabel,
  onAction: onAction,
  rewardLabel: rewardLabel,
);

void _insertToast(
  OverlayState overlay,
  OnCareTokens tokens,
  String message,
  AppToastType type,
  String? actionLabel,
  VoidCallback? onAction,
  String? rewardLabel,
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
      rewardLabel: rewardLabel,
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
    required this.rewardLabel,
    required this.visibleFor,
    required this.onDismissed,
  });

  final OnCareTokens tokens;
  final String message;
  final AppToastType type;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? rewardLabel;
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
    final (IconData icon, Color iconColor) = switch (widget.type) {
      AppToastType.success => (
        Icons.check_circle_rounded,
        OnCareColors.overlaySuccess,
      ),
      AppToastType.error => (Icons.error_rounded, OnCareColors.overlayError),
      AppToastType.info => (Icons.info_rounded, OnCareColors.overlayAction),
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
                          Icon(
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
                          if (widget.rewardLabel != null) ...<Widget>[
                            const SizedBox(width: OnCareSpacing.s8),
                            _RewardBadge(
                              tokens: tokens,
                              label: widget.rewardLabel!,
                            ),
                          ],
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

/// 토스트의 포인트 적립 표시 — ★ 과 받은 포인트(`+50P`). (#1786)
///
/// 토스트가 내려앉은 뒤 한 번 톡 튀고, 그 위로 반짝임이 한 번 지나간다. 기기의
/// 움직임 줄이기가 켜져 있으면 움직이지 않고 표시만 둔다.
class _RewardBadge extends StatefulWidget {
  const _RewardBadge({required this.tokens, required this.label});

  final OnCareTokens tokens;
  final String label;

  @override
  State<_RewardBadge> createState() => _RewardBadgeState();
}

class _RewardBadgeState extends State<_RewardBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sparkle = AnimationController(
    vsync: this,
    duration: OnCareMotion.rewardSparkle,
  );

  /// 앞 30% 에 커졌다가 다음 30% 에 돌아오고, 나머지는 반짝임만 지나간다.
  late final Animation<double> _scale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: OnCareMotion.rewardPopScale,
          ).chain(CurveTween(curve: OnCareMotion.curve)),
          weight: 30,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: OnCareMotion.rewardPopScale,
            end: 1,
          ).chain(CurveTween(curve: OnCareMotion.curve)),
          weight: 30,
        ),
        TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 40),
      ]).animate(_sparkle);

  Timer? _start;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (MediaQuery.disableAnimationsOf(context)) return;
    // 토스트가 미끄러져 내려오는 동안 튀면 눈에 들어오지 않는다.
    _start = Timer(OnCareMotion.toastEnter, () {
      if (mounted) _sparkle.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _sparkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget badge = Container(
      key: const ValueKey<String>('appToastReward'),
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s8,
        vertical: OnCareSpacing.s2,
      ),
      decoration: const BoxDecoration(
        color: OnCareColors.overlayReward,
        borderRadius: OnCareRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.star_rounded,
            size: OnCareSize.iconSmall,
            color: OnCareColors.overlayInk,
          ),
          const SizedBox(width: OnCareSpacing.s2),
          Text(
            widget.label,
            style: OnCareTypography.numeric(
              widget.tokens.text(OnCareTypography.label),
            ).copyWith(color: OnCareColors.overlayInk),
          ),
        ],
      ),
    );
    return ScaleTransition(
      scale: _scale,
      child: AnimatedBuilder(
        animation: _sparkle,
        child: badge,
        builder: (BuildContext context, Widget? child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          // 반짝임 띠가 왼쪽 밖에서 오른쪽 밖으로 한 번 지나간다. 멈춰 있을 때는
          // 띠가 표시 밖에 있어 보이지 않는다.
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: const <Color>[
              Colors.transparent,
              OnCareColors.rewardShine,
              Colors.transparent,
            ],
            stops: const <double>[0.35, 0.5, 0.65],
            transform: _SweepTransform(-1 + 2 * _sparkle.value),
          ).createShader(bounds),
          child: child,
        ),
      ),
    );
  }
}

/// 그라데이션을 폭의 [fraction] 만큼 옆으로 민다.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.fraction);

  final double fraction;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, 0, 0);
}

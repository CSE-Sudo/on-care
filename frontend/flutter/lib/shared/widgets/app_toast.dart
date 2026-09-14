import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 토스트가 전하는 소식의 종류.
///
/// 아이콘과 머무는 시간만 달라진다 — 바탕색까지 갈라 놓으면 성공 토스트와
/// 실패 토스트가 같은 앱의 같은 부품으로 보이지 않는다.
enum AppToastKind { info, success, error }

/// 화면 위쪽에 잠깐 뜨는 알림을 띄운다. (#1259)
///
/// 앱의 모든 "저장했어요 / 실패했어요" 는 이 함수 하나를 거친다.
///
/// **`SnackBar` 이 아니라 루트 오버레이에 얹는다.** 스낵바는 `Scaffold` 안에
/// 그려지므로 모달 시트나 대화상자가 열려 있으면 그 뒤에 가려 보이지 않는다.
/// 그런데 이 앱은 저장도 검증도 대부분 시트 안에서 한다 — "운동 시간을 입력해
/// 주세요" 처럼 **가장 봐야 하는 알림이 안 보이는** 자리가 그것이다. 루트
/// 오버레이는 모든 라우트 위에 그려져 이 문제가 없다.
///
/// 자리를 위쪽으로 잡은 것도 같은 까닭이다. 아래쪽은 하단 내비게이션과 `+`
/// 버튼, 시트의 저장 버튼, 키보드가 모두 몰려 있어 무엇을 덮어도 손해가 크다.
///
/// 화면을 닫은 **뒤에** 결과가 도착하는 자리(시트를 pop 하고 저장 응답을
/// 기다리는 흐름)에서는 [AppToastHost.of] 로 손잡이를 미리 잡아 둔다 —
/// 사라진 화면의 `BuildContext` 로는 오버레이를 찾을 수 없다.
///
/// 생김새·시간은 공용 토스트(`oncare_ui` 의 `showAppToast`)와 같은 토큰을 쓴다
/// (#1699). 이 사본은 정리 이슈(#1707)에서 공용 토스트로 합친다.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastKind kind = AppToastKind.info,
  Duration? duration,
}) {
  AppToastHost.of(context).show(message, kind: kind, duration: duration);
}

/// 토스트를 띄우는 손잡이. 화면이 사라진 뒤에도 쓸 수 있도록 오버레이를 미리
/// 잡아 둔다.
class AppToastHost {
  const AppToastHost._(this._overlay);

  final OverlayState _overlay;

  /// 지금 떠 있는 토스트. 한 번에 하나만 둔다 — 사용자가 빠르게 두 번 저장하면
  /// 뒤늦게 뜨는 첫 토스트는 이미 지난 소식이다.
  static _AppToastHandle? _visible;

  static AppToastHost of(BuildContext context) =>
      AppToastHost._(Overlay.of(context, rootOverlay: true));

  void show(
    String message, {
    AppToastKind kind = AppToastKind.info,
    Duration? duration,
  }) {
    _visible?.dismiss();
    late final _AppToastHandle handle;
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) => _AppToast(
        message: message,
        kind: kind,
        duration:
            duration ??
            (kind == AppToastKind.error
                ? OnCareMotion.toastErrorVisible
                : OnCareMotion.toastVisible),
        onDismissed: () => handle.dismiss(),
      ),
    );
    handle = _AppToastHandle(entry);
    _visible = handle;
    _overlay.insert(entry);
  }
}

class _AppToastHandle {
  _AppToastHandle(this._entry);

  final OverlayEntry _entry;
  bool _removed = false;

  void dismiss() {
    if (_removed) return;
    _removed = true;
    if (AppToastHost._visible == this) AppToastHost._visible = null;
    // 오버레이가 이미 사라진 뒤(앱 종료·테스트 정리)라면 걷을 것도 없다.
    if (_entry.mounted) _entry.remove();
  }
}

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final AppToastKind kind;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OnCareMotion.toastEnter,
    reverseDuration: OnCareMotion.toastExit,
  );
  Timer? _dwell;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _dwell = Timer(widget.duration, _hide);
  }

  @override
  void dispose() {
    _dwell?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _hide() {
    _dwell?.cancel();
    if (!mounted) {
      widget.onDismissed();
      return;
    }
    _controller.reverse().whenComplete(widget.onDismissed);
  }

  @override
  Widget build(BuildContext context) {
    final CurvedAnimation curve = CurvedAnimation(
      parent: _controller,
      curve: OnCareMotion.curve,
      reverseCurve: OnCareMotion.exitCurve,
    );
    return Positioned(
      top: MediaQuery.paddingOf(context).top + OnCareSpacing.s12,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.6),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s16,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OnCareLayout.toastMaxWidth,
                ),
                child: _pill(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: GestureDetector(
        // 먼저 읽고 치울 수 있게 한다 — 눌러도, 위로 밀어도 사라진다.
        onTap: _hide,
        onVerticalDragEnd: (DragEndDetails details) {
          if ((details.primaryVelocity ?? 0) < 0) _hide();
        },
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: OnCareColors.overlayInk,
            borderRadius: OnCareRadius.lgAll,
            boxShadow: OnCareShadows.overlay,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OnCareSpacing.s16,
                vertical: OnCareSpacing.s12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    _icon(widget.kind),
                    size: OnCareSize.iconMedium,
                    color: _iconColor(widget.kind),
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  Expanded(
                    child: Text(
                      widget.message,
                      // 토스트는 앱 어디서나 뜨므로 테마 글자(`bodySmall`)를
                      // 그대로 읽는다 — 테마가 전역 배율을 이미 상쇄해 두었다.
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: OnCareColors.textOnFill,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _icon(AppToastKind kind) {
  switch (kind) {
    case AppToastKind.success:
      return Icons.check_circle_rounded;
    case AppToastKind.error:
      return Icons.error_rounded;
    case AppToastKind.info:
      return Icons.info_rounded;
  }
}

Color _iconColor(AppToastKind kind) {
  switch (kind) {
    case AppToastKind.success:
      return OnCareColors.overlaySuccess;
    case AppToastKind.error:
      return OnCareColors.overlayError;
    case AppToastKind.info:
      return OnCareColors.overlayAction;
  }
}

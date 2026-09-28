import 'package:flutter/material.dart';

import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';

/// 팝오버 상자 — 흰색·반경 12·진한 테두리·떠 있는 그림자(#2469).
///
/// [AppPopover] 가 띄우는 상자이고, 같은 목록을 창 안에 그대로 놓을 때도
/// 이것을 쓴다(통합 검색 결과).
class AppPopoverSurface extends StatelessWidget {
  const AppPopoverSurface({
    super.key,
    required this.child,
    this.width,
    this.maxHeight,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;

  /// 없으면 내용 폭이다.
  final double? width;

  /// 넘치면 내용이 스스로 스크롤한다.
  final double? maxHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: maxHeight == null
          ? null
          : BoxConstraints(maxHeight: maxHeight!),
      padding: padding,
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.fromBorderSide(
          BorderSide(color: OnCareColors.lineStrong),
        ),
        boxShadow: OnCareShadows.overlay,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// 팝오버 — [anchor] 바로 아래(4)에 왼쪽 끝을 맞춰 [panel] 을 띄운다(#2469).
///
/// 열고 닫기는 [controller] 로 부르는 쪽이 정한다. 앵커와 상자 **바깥**을
/// 누르면 [onTapOutside] 가 불린다 — 앵커를 눌러 여닫는 토글이 바깥 누름으로
/// 한 번 더 뒤집히지 않도록 둘을 한 탭 영역으로 묶는다.
class AppPopover extends StatefulWidget {
  const AppPopover({
    super.key,
    required this.controller,
    required this.anchor,
    required this.panel,
    this.onTapOutside,
    this.panelKey,
    this.width,
    this.maxHeight,
    this.padding = EdgeInsets.zero,
  });

  final OverlayPortalController controller;
  final Widget anchor;
  final WidgetBuilder panel;
  final VoidCallback? onTapOutside;

  /// 상자의 Key.
  final Key? panelKey;
  final double? width;
  final double? maxHeight;
  final EdgeInsetsGeometry padding;

  @override
  State<AppPopover> createState() => _AppPopoverState();
}

class _AppPopoverState extends State<AppPopover> {
  final LayerLink _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: widget.controller,
        overlayChildBuilder: (BuildContext context) =>
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              offset: const Offset(0, OnCareSpacing.s4),
              child: Align(
                alignment: Alignment.topLeft,
                child: TapRegion(
                  groupId: this,
                  child: AppPopoverSurface(
                    key: widget.panelKey,
                    width: widget.width,
                    maxHeight: widget.maxHeight,
                    padding: widget.padding,
                    child: widget.panel(context),
                  ),
                ),
              ),
            ),
        child: TapRegion(
          groupId: this,
          onTapOutside: widget.onTapOutside == null
              ? null
              : (_) => widget.onTapOutside!(),
          child: widget.anchor,
        ),
      ),
    );
  }
}

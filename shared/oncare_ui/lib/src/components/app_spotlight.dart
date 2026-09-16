import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 설명 말풍선이 구멍의 어느 쪽에 붙었는가.
enum AppSpotlightPlacement {
  /// 구멍 아래 — 말풍선 꼬리는 위를 가리킨다.
  below,

  /// 구멍 위 — 꼬리는 아래를 가리킨다.
  above,

  /// 짚을 자리가 없거나 위아래 모두 좁을 때. 꼬리 없이 화면 가운데.
  center,
}

/// 스포트라이트 안내 — 화면을 어둡게 덮고 **한 곳만 밝게 뚫어** 설명한다. (#1857)
///
/// 처음 쓰는 화면에서 "여기를 보세요" 를 말하는 가장 짧은 방법이다. 설명 글만
/// 띄우면 어느 버튼 이야기인지 알 수 없고, 화살표만 그리면 그 아래 화면이 그대로
/// 눌려 안내 도중 다른 곳으로 가 버린다. 그래서 덮개는 **탭을 모두 삼킨다** —
/// 넘어가는 길은 이 위젯이 그리는 버튼뿐이다.
///
/// 짜임새는 셋이다: 구멍에 꼬리를 대고 붙는 작은 말풍선([caption]), 화면 위쪽의
/// [topBar](무엇을 보고 있는지와 건너뛰기), 아래쪽의 [bottomBar](이전·다음).
/// 말풍선이 크면 정작 짚은 자리를 가리므로 한두 줄로 짧게 쓴다.
///
/// [hole] 이 없으면(짚을 것을 아직 못 찾았으면) 구멍 없이 덮기만 하고 말풍선은
/// 가운데로 간다. 안내가 사라지거나 엉뚱한 곳이 뚫리는 것보다 낫다.
class AppSpotlight extends StatelessWidget {
  const AppSpotlight({
    super.key,
    required this.hole,
    required this.caption,
    this.topBar,
    this.bottomBar,
    this.holeRadius = OnCareRadius.lg,
    this.holePadding = OnCareSpacing.s8,
  });

  /// 밝게 보일 자리(이 위젯 좌표계). 없으면 구멍 없이 덮는다.
  final Rect? hole;

  /// 말풍선 안에 들어갈 설명. 한두 줄이 알맞다.
  final Widget caption;

  /// 화면 위쪽 줄 — 지금이 안내라는 표시와 건너뛰기.
  final Widget? topBar;

  /// 화면 아래쪽 줄 — 이전·다음.
  final Widget? bottomBar;

  /// 구멍 모서리. 짚는 요소의 모양을 따른다.
  final Radius holeRadius;

  /// 구멍을 요소보다 조금 넓게 뚫어, 밝은 자리에 요소가 꽉 끼지 않게 한다.
  final double holePadding;

  /// 구멍과 말풍선 사이.
  static const double captionGap = OnCareSpacing.s8;

  /// 말풍선·위아래 줄이 화면 가장자리에 붙지 않게 두는 여백.
  static const double edgeMargin = OnCareSpacing.s16;

  /// 위아래 어느 쪽에 붙일지 정할 때 잡는 말풍선 높이.
  ///
  /// 실제 높이는 배치가 끝나야 알 수 있는데, 꼬리 방향은 그리기 **전에** 정해야
  /// 한다. 한두 줄짜리 말풍선의 넉넉한 어림값을 쓴다.
  static const double _assumedCaptionHeight = 132;

  @override
  Widget build(BuildContext context) {
    final Rect? target = hole?.inflate(holePadding);
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size size = constraints.biggest;
          final AppSpotlightPlacement placement = placementFor(target, size);
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  // 덮개 아래는 눌리지 않는다 — 안내 도중 화면이 바뀌면 방금
                  // 짚은 자리가 사라진다.
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(
                    painter: _SpotlightPainter(
                      hole: target,
                      radius: holeRadius,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: _CaptionLayout(
                    hole: target,
                    placement: placement,
                    gap: captionGap,
                    margin: edgeMargin,
                  ),
                  child: AppSpotlightCallout(
                    placement: placement,
                    tailAlignment: _tailAlignment(target, size),
                    child: caption,
                  ),
                ),
              ),
              if (topBar != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(edgeMargin),
                      child: topBar,
                    ),
                  ),
                ),
              if (bottomBar != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(edgeMargin),
                      child: bottomBar,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 구멍 아래에 말풍선이 들어가면 아래, 아니면 위, 둘 다 좁으면 가운데.
  @visibleForTesting
  static AppSpotlightPlacement placementFor(Rect? hole, Size size) {
    if (hole == null) return AppSpotlightPlacement.center;
    final double below = hole.bottom + captionGap + _assumedCaptionHeight;
    if (below + edgeMargin <= size.height) return AppSpotlightPlacement.below;
    final double above = hole.top - captionGap - _assumedCaptionHeight;
    if (above >= edgeMargin) return AppSpotlightPlacement.above;
    return AppSpotlightPlacement.center;
  }

  /// 꼬리가 말풍선 폭의 어디에서 나올지(0~1). 구멍 한가운데를 가리키되, 말풍선
  /// 모서리를 넘지 않는다.
  static double _tailAlignment(Rect? hole, Size size) {
    if (hole == null) return 0.5;
    final double width = math.max(1, size.width - edgeMargin * 2);
    return ((hole.center.dx - edgeMargin) / width).clamp(0.1, 0.9);
  }
}

/// 꼬리가 달린 흰 말풍선 — 꼬리는 [placement] 가 가리키는 쪽에 붙는다.
class AppSpotlightCallout extends StatelessWidget {
  const AppSpotlightCallout({
    super.key,
    required this.child,
    required this.placement,
    this.tailAlignment = 0.5,
  });

  final Widget child;
  final AppSpotlightPlacement placement;

  /// 꼬리가 나올 가로 위치(0=왼쪽 끝, 1=오른쪽 끝).
  final double tailAlignment;

  static const double tailWidth = OnCareSpacing.s16;
  static const double tailHeight = OnCareSpacing.s8;

  @override
  Widget build(BuildContext context) {
    final Widget bubble = DecoratedBox(
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.lgAll,
        boxShadow: OnCareShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(OnCareSpacing.s12),
        child: child,
      ),
    );
    if (placement == AppSpotlightPlacement.center) return bubble;

    final bool tailUp = placement == AppSpotlightPlacement.below;
    final Widget tail = SizedBox(
      height: tailHeight,
      child: CustomPaint(
        painter: _TailPainter(pointingUp: tailUp, alignment: tailAlignment),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[if (tailUp) tail, bubble, if (!tailUp) tail],
    );
  }
}

/// 덮개 위의 글자 버튼 — 어두운 바탕이라 흰 글씨다(`건너뛰기`·`이전`·`다음`).
class AppSpotlightAction extends StatelessWidget {
  const AppSpotlightAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextStyle style = tokens
        .text(OnCareTypography.strong(OnCareTypography.label))
        .copyWith(color: OnCareColors.textOnFill);
    // 진한 알약을 깔아 둔다. 글씨만 희게 두면 **밝게 뚫린 자리와 겹칠 때** 그
    // 위에서 사라진다 — 알림 벨(위)이나 MY 탭(아래)을 짚을 때가 그렇다. 덮개는
    // 화면이 비치도록 옅게 두므로, 버튼 바탕은 덮개와 따로 둔다.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: OnCareColors.spotlightActionFill,
        borderRadius: OnCareRadius.pillAll,
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: OnCareRadius.pillAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OnCareSpacing.s8,
            vertical: OnCareSpacing.s8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leadingIcon != null) ...<Widget>[
                AppIcon(
                  leadingIcon!,
                  size: OnCareSize.iconSmall,
                  color: OnCareColors.textOnFill,
                ),
                const SizedBox(width: OnCareSpacing.s4),
              ],
              Text(label, style: style),
              if (trailingIcon != null) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s4),
                AppIcon(
                  trailingIcon!,
                  size: OnCareSize.iconSmall,
                  color: OnCareColors.textOnFill,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 화면 전체를 덮고 [hole] 만 도려낸다.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole, required this.radius});

  final Rect? hole;
  final Radius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = OnCareColors.spotlightScrim;
    final Rect? cut = hole;
    if (cut == null) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    // 구멍 **둘레를 네 조각으로** 덮는다. 화면 경로에서 구멍 경로를 빼는 방법
    // (`Path.combine`)은 웹 렌더러에서 그대로 통하지 않아, 덮개만 칠해지고
    // 구멍이 뚫리지 않았다. 사각형 넷과 모서리 네 조각은 어디서나 같게 그려진다.
    canvas
      ..drawRect(Rect.fromLTRB(0, 0, size.width, cut.top), paint)
      ..drawRect(Rect.fromLTRB(0, cut.bottom, size.width, size.height), paint)
      ..drawRect(Rect.fromLTRB(0, cut.top, cut.left, cut.bottom), paint)
      ..drawRect(
        Rect.fromLTRB(cut.right, cut.top, size.width, cut.bottom),
        paint,
      );

    // 각진 구멍의 귀퉁이를 둥글게 깎는다 — 짚는 카드·버튼의 모서리를 따른다.
    final double r = math.min(radius.x, math.min(cut.width, cut.height) / 2);
    if (r <= 0) return;
    canvas
      ..drawPath(_corner(cut.topLeft, r, dx: 1, dy: 1), paint)
      ..drawPath(_corner(cut.topRight, r, dx: -1, dy: 1), paint)
      ..drawPath(_corner(cut.bottomRight, r, dx: -1, dy: -1), paint)
      ..drawPath(_corner(cut.bottomLeft, r, dx: 1, dy: -1), paint);
  }

  /// 구멍 귀퉁이 하나를 덮는 조각 — 직각에서 원호만큼을 남긴 부분.
  static Path _corner(
    Offset corner,
    double r, {
    required int dx,
    required int dy,
  }) {
    final Offset alongX = corner + Offset(r * dx, 0);
    final Offset alongY = corner + Offset(0, r * dy);
    return Path()
      ..moveTo(corner.dx, corner.dy)
      ..lineTo(alongX.dx, alongX.dy)
      ..arcToPoint(alongY, radius: Radius.circular(r), clockwise: dx * dy < 0)
      ..close();
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.radius != radius;
}

/// 말풍선 꼬리 — 짚는 자리 쪽을 가리키는 작은 삼각형.
class _TailPainter extends CustomPainter {
  const _TailPainter({required this.pointingUp, required this.alignment});

  final bool pointingUp;
  final double alignment;

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width * alignment;
    const double half = AppSpotlightCallout.tailWidth / 2;
    final double left = center - half;
    final double right = center + half;
    final Path path = Path();
    if (pointingUp) {
      path
        ..moveTo(center, 0)
        ..lineTo(right, size.height)
        ..lineTo(left, size.height);
    } else {
      path
        ..moveTo(center, size.height)
        ..lineTo(right, 0)
        ..lineTo(left, 0);
    }
    canvas.drawPath(path..close(), Paint()..color = OnCareColors.surfaceCard);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) =>
      oldDelegate.pointingUp != pointingUp ||
      oldDelegate.alignment != alignment;
}

/// 말풍선을 구멍의 [placement] 쪽에 붙인다.
class _CaptionLayout extends SingleChildLayoutDelegate {
  const _CaptionLayout({
    required this.hole,
    required this.placement,
    required this.gap,
    required this.margin,
  });

  final Rect? hole;
  final AppSpotlightPlacement placement;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final double width = math.max(0, constraints.maxWidth - margin * 2);
    final double maxHeight = math.max(0, constraints.maxHeight - margin * 2);
    // 폭은 고정이다 — 꼬리가 가리키는 자리와 글 폭이 화면마다 달라지지 않는다.
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double left = math.max(0, (size.width - childSize.width) / 2);
    final double centered = math.max(0, (size.height - childSize.height) / 2);
    final Rect? target = hole;
    if (target == null) return Offset(left, centered);

    final double top = switch (placement) {
      AppSpotlightPlacement.below => target.bottom + gap,
      AppSpotlightPlacement.above => target.top - gap - childSize.height,
      AppSpotlightPlacement.center => centered,
    };
    final double lowest = math.max(
      margin,
      size.height - childSize.height - margin,
    );
    return Offset(left, top.clamp(math.min(margin, lowest), lowest));
  }

  @override
  bool shouldRelayout(_CaptionLayout oldDelegate) =>
      oldDelegate.hole != hole ||
      oldDelegate.placement != placement ||
      oldDelegate.gap != gap ||
      oldDelegate.margin != margin;
}

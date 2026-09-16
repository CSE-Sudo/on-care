import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';

/// 스포트라이트 안내 — 화면을 어둡게 덮고 **한 곳만 밝게 뚫어** 설명한다. (#1857)
///
/// 처음 쓰는 화면에서 "여기를 보세요" 를 말하는 가장 짧은 방법이다. 설명 글만
/// 띄우면 어느 버튼 이야기인지 알 수 없고, 화살표만 그리면 그 아래 화면이 그대로
/// 눌려 안내 도중에 다른 곳으로 가 버린다. 그래서 덮개는 **탭을 모두 삼킨다** —
/// 다음으로 넘어가는 길은 설명 카드의 버튼뿐이다.
///
/// [hole] 이 없으면(짚을 것을 아직 못 찾았으면) 구멍 없이 덮기만 한다. 안내가
/// 사라지거나 엉뚱한 곳이 뚫리는 것보다 낫다.
class AppSpotlight extends StatelessWidget {
  const AppSpotlight({
    super.key,
    required this.hole,
    required this.caption,
    this.holeRadius = OnCareRadius.lg,
    this.holePadding = OnCareSpacing.s8,
  });

  /// 밝게 보일 자리(이 위젯 좌표계). 없으면 구멍 없이 덮는다.
  final Rect? hole;

  /// 구멍 옆에 놓일 설명. 위/아래 어디에 둘지는 이 위젯이 정한다.
  final Widget caption;

  /// 구멍 모서리. 짚는 요소의 모양을 따른다.
  final Radius holeRadius;

  /// 구멍을 요소보다 조금 넓게 뚫어, 밝은 자리에 요소가 꽉 끼지 않게 한다.
  final double holePadding;

  /// 구멍과 설명 카드 사이.
  static const double captionGap = OnCareSpacing.s12;

  /// 설명 카드가 화면 가장자리에 붙지 않게 두는 여백.
  static const double edgeMargin = OnCareSpacing.s16;

  @override
  Widget build(BuildContext context) {
    final Rect? target = hole?.inflate(holePadding);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              // 덮개 아래는 눌리지 않는다 — 안내 도중 화면이 바뀌면 방금 짚은
              // 자리가 사라진다.
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(
                painter: _SpotlightPainter(hole: target, radius: holeRadius),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _CaptionLayout(
                hole: target,
                gap: captionGap,
                margin: edgeMargin,
              ),
              child: caption,
            ),
          ),
        ],
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
    final Path screen = Path()..addRect(Offset.zero & size);
    final Rect? cut = hole;
    if (cut == null) {
      canvas.drawPath(screen, paint);
      return;
    }
    final Path lit = Path()..addRRect(RRect.fromRectAndRadius(cut, radius));
    canvas.drawPath(Path.combine(PathOperation.difference, screen, lit), paint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.radius != radius;
}

/// 설명 카드를 구멍 **아래**에 두되, 자리가 모자라면 위로 올린다.
///
/// 짚는 것이 하단 내비처럼 화면 끝에 있으면 아래에 둘 자리가 없고, 머리의
/// 버튼이면 위에 둘 자리가 없다. 둘 다 안 되면 화면 가운데에 둔다 — 카드가
/// 화면 밖으로 나가 글이 잘리는 일만은 없게 한다.
class _CaptionLayout extends SingleChildLayoutDelegate {
  const _CaptionLayout({
    required this.hole,
    required this.gap,
    required this.margin,
  });

  final Rect? hole;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final double maxWidth = math.max(0, constraints.maxWidth - margin * 2);
    final double maxHeight = math.max(0, constraints.maxHeight - margin * 2);
    return BoxConstraints.loose(Size(maxWidth, maxHeight));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double left = math.max(0, (size.width - childSize.width) / 2);
    final double centered = math.max(0, (size.height - childSize.height) / 2);
    final Rect? target = hole;
    if (target == null) return Offset(left, centered);

    final double below = target.bottom + gap;
    final double above = target.top - gap - childSize.height;
    final double top;
    if (below + childSize.height + margin <= size.height) {
      top = below;
    } else if (above >= margin) {
      top = above;
    } else {
      top = centered;
    }
    final double lowest = math.max(
      margin,
      size.height - childSize.height - margin,
    );
    return Offset(left, top.clamp(math.min(margin, lowest), lowest));
  }

  @override
  bool shouldRelayout(_CaptionLayout oldDelegate) =>
      oldDelegate.hole != hole ||
      oldDelegate.gap != gap ||
      oldDelegate.margin != margin;
}

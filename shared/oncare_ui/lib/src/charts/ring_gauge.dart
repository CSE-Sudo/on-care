import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/icons.dart';

/// 링 게이지의 모양(#2469).
enum AppRingGaugeStyle {
  /// 회색(입력 채움) 트랙 위에 한 바퀴까지만 채운다 — 식단 칼로리 달성률.
  /// 넘긴 양은 링이 그리지 않고, 숫자가 말한다.
  plain,

  /// 값 색을 옅게 깐 트랙, 목표를 넘기면 한 바퀴를 넘어 이어 돈다. 끝(캡)
  /// 아래 그림자와 흰 `>` 로 어디서 멈췄는지 짚는다 — 운동 소모·목표 링.
  lap,
}

/// 원호 끝 그림자 두 겹 — 넓고 흐린 것 / 좁고 진한 것(회원 앱 #1161 과 같은 값).
const double _kCapShadowOuterSpread = 4;
const double _kCapShadowOuterBlur = 12;
const double _kCapShadowOuterAlpha = 0.75;
const double _kCapShadowInnerSpread = 1;
const double _kCapShadowInnerBlur = 5;
const double _kCapShadowInnerAlpha = 0.65;

/// 링 게이지 하나 — 받은 칸을 꽉 채우는 원, 선 두께 [stroke](#2469).
///
/// 가운데에 [child] 를 얹는다(달성률 글자 등). 여러 겹 링은 이 위젯을 지름을
/// 줄여 가며 겹쳐 쌓는다.
class AppRingGauge extends StatelessWidget {
  const AppRingGauge({
    super.key,
    required this.value,
    required this.color,
    required this.stroke,
    this.style = AppRingGaugeStyle.plain,
    this.startIcon,
    this.child,
  });

  /// 목표 대비 비율. [AppRingGaugeStyle.plain] 은 0~1 로 잘라 그린다.
  final double value;

  /// 채운 호의 색.
  final Color color;

  /// 링 두께.
  final double stroke;
  final AppRingGaugeStyle style;

  /// [AppRingGaugeStyle.lap] 의 12시 흰 기호 — 이 링이 무엇인지 말한다.
  final IconData? startIcon;

  /// 가운데 내용.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingGaugePainter(
        value: value,
        color: color,
        stroke: stroke,
        style: style,
        startIcon: startIcon,
        iconSet: AppIcon.setOf(context),
      ),
      child: child == null
          ? const SizedBox.expand()
          : SizedBox.expand(child: child),
    );
  }
}

class _RingGaugePainter extends CustomPainter {
  const _RingGaugePainter({
    required this.value,
    required this.color,
    required this.stroke,
    required this.style,
    required this.startIcon,
    required this.iconSet,
  });

  final double value;
  final Color color;
  final double stroke;
  final AppRingGaugeStyle style;
  final IconData? startIcon;
  final OnCareIconSet iconSet;

  @override
  void paint(Canvas canvas, Size size) {
    paintAppRing(
      canvas,
      size.center(Offset.zero),
      (size.shortestSide - stroke) / 2,
      stroke,
      value,
      color,
      style: style,
      startIcon: startIcon,
      iconSet: iconSet,
    );
  }

  @override
  bool shouldRepaint(_RingGaugePainter old) =>
      old.value != value ||
      old.color != color ||
      old.stroke != stroke ||
      old.style != style ||
      old.startIcon != startIcon ||
      old.iconSet != iconSet;
}

/// 한 바퀴를 넘긴 원호가 **다시 도는 몫**(0 이상 1 미만).
///
/// 넘친 몫을 1 에서 자르면 두 바퀴를 넘긴 순간(209%, 300% …) 끝이 12시로
/// 되돌아가, 그 자리에 고정으로 얹는 기호 아래 캡 표시가 숨는다. 자르지 말고
/// **바퀴마다 감아 돌린다**(#1178). 209% 면 두 번째 바퀴의 9% 지점이다.
double ringOverflowTurn(double ratio) {
  if (!ratio.isFinite) return 0;
  return ratio - ratio.floorToDouble();
}

/// 부동소수점 오차를 감안한 허용 오차(회원 앱 #1462).
const double _kRingMultipleEpsilon = 1e-6;

/// [filled] 가 목표의 정확한 양의 정수 배(1, 2, 3 …)에 아주 가까운가.
///
/// 이 자리에서는 원호 끝이 12시 기호와 겹친다 — 캡 그림자와 끝 `>` 를 또
/// 그리면 검은 얼룩과 기호 중복으로 보인다(회원 앱 #1462). 0 은 배수가 아니다.
bool isAtRingMultiple(double filled) {
  if (!filled.isFinite || filled < 1 - _kRingMultipleEpsilon) return false;
  final double nearest = filled.roundToDouble();
  return nearest >= 1 && (filled - nearest).abs() <= _kRingMultipleEpsilon;
}

/// 링 하나를 캔버스에 그리는 붓 — [AppRingGauge] 가 쓴다. 12시에서 시계 방향.
void paintAppRing(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  double ratio,
  Color color, {
  AppRingGaugeStyle style = AppRingGaugeStyle.plain,
  IconData? startIcon,
  OnCareIconSet iconSet = OnCareIconSet.material,
}) {
  final Rect rect = Rect.fromCircle(center: center, radius: radius);
  final bool lap = style == AppRingGaugeStyle.lap;
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      // 흰 카드 위 트랙 — 불투명 값이라 한 바퀴 넘긴 원호 아래로 비치지 않는다.
      ..color = lap
          ? OnCareColors.onWhite(color, OnCareAlpha.medium)
          : OnCareColors.surfaceInput,
  );
  final Paint arc = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round
    ..color = color;
  if (!lap) {
    final double sweep = ratio.isFinite ? ratio.clamp(0.0, 1.0) : 0;
    if (sweep > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * sweep, false, arc);
    }
    return;
  }
  double capAngle = -math.pi / 2;
  // 정확한 목표 배수(100%, 200% …)에서는 캡 그림자와 끝 `>` 를 그리지 않는다
  // (회원 앱 #1462) — 끝이 12시 기호와 겹쳐 검은 얼룩과 기호 둘로 보인다.
  final bool atMultiple = isAtRingMultiple(ratio);
  if (ratio >= 1 - _kRingMultipleEpsilon) {
    // 한 바퀴는 **끝이 없는 원**으로. 2π 원호에 둥근 끝을 주면 시작과 끝의
    // 캡이 같은 자리에 겹쳐 혹처럼 튀어나온다.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color,
    );
    final double over = atMultiple ? 0 : ringOverflowTurn(ratio);
    capAngle = -math.pi / 2 + math.pi * 2 * over;
    if (!atMultiple) {
      _paintCapShadow(canvas, center, radius, stroke, capAngle);
      if (over > 0) {
        canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * over, false, arc);
      }
    }
  } else if (ratio > 0) {
    capAngle = -math.pi / 2 + math.pi * 2 * ratio;
    _paintCapShadow(canvas, center, radius, stroke, capAngle);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * ratio, false, arc);
  }
  if (ratio > 0 && !atMultiple) {
    _paintCapChevron(canvas, center, radius, stroke, capAngle);
  }
  // 기호는 12시에 고정한다 — 링이 한 바퀴를 넘겨 겹쳐도 가려지지 않게 맨 위에.
  if (startIcon != null) {
    _paintStartIcon(canvas, center, radius, stroke, startIcon, iconSet);
  }
}

/// 원호의 **끝(캡)** 아래에 깔 그림자. 넓고 흐린 것 위에 좁고 진한 것을 겹쳐
/// 찍어, 끝이 아래 트랙(또는 한 바퀴 돈 같은 색 원)에 묻히지 않게 한다.
///
/// 그리기 전에 캔버스를 **그 링의 두께**로 자른다 — 흐린 가장자리가 링 밖으로
/// 번지지 않게.
void _paintCapShadow(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  double capAngle,
) {
  final Path ring = Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Rect.fromCircle(center: center, radius: radius + stroke / 2))
    ..addOval(Rect.fromCircle(center: center, radius: radius - stroke / 2));
  final Offset cap =
      center + Offset(math.cos(capAngle), math.sin(capAngle)) * radius;
  canvas
    ..save()
    ..clipPath(ring)
    ..drawCircle(
      cap,
      stroke / 2 + _kCapShadowOuterSpread,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          OnCareColors.overlayInk,
          _kCapShadowOuterAlpha,
        )!
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          _kCapShadowOuterBlur,
        ),
    )
    ..drawCircle(
      cap,
      stroke / 2 + _kCapShadowInnerSpread,
      Paint()
        ..color = Color.lerp(
          Colors.transparent,
          OnCareColors.overlayInk,
          _kCapShadowInnerAlpha,
        )!
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          _kCapShadowInnerBlur,
        ),
    )
    ..restore();
}

/// 원호의 **끝**에 얹는 얇고 작은 흰 `>`. 링이 너무 얇으면 그리지 않는다.
void _paintCapChevron(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  double angle,
) {
  final double arm = stroke * 0.16;
  if (arm < 1.4) return;
  final Offset at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
  canvas
    ..save()
    ..translate(at.dx, at.dy)
    // 접선 방향으로 눕힌다 — 시계 방향으로 도는 원호에서는 각도 + 90도다.
    ..rotate(angle + math.pi / 2)
    ..drawPath(
      Path()
        ..moveTo(-arm * 0.55, -arm)
        ..lineTo(arm * 0.55, 0)
        ..lineTo(-arm * 0.55, arm),
      Paint()
        ..color = OnCareColors.textOnFill
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(stroke * 0.07, 1)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    )
    ..restore();
}

/// 링 12시에 흰 기호를 얹는다. 링 두께 안에 들어가도록 두께에 맞춰 줄인다.
///
/// 캔버스에 직접 찍는 글자라 테마를 타지 않는다 — 아이콘 묶음의 채움·굵기를
/// [AppIcon.glyphPainter] 로 실어 준다(회원 앱 #1866, #2466).
void _paintStartIcon(
  Canvas canvas,
  Offset center,
  double radius,
  double stroke,
  IconData icon,
  OnCareIconSet iconSet,
) {
  final double glyph = stroke * 0.78;
  if (glyph < 6) return;
  final TextPainter tp = AppIcon.glyphPainter(
    iconSet,
    icon,
    size: glyph,
    color: OnCareColors.textOnFill,
  );
  final Offset at = center + const Offset(0, -1) * radius;
  tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
}

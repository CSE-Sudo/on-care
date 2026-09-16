import 'package:flutter/material.dart';

import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/icons.dart';

/// 아이콘 한 개(#1803). 컴포넌트와 화면은 [Icon] 대신 이것을 쓴다.
///
/// 테마의 [OnCareIconSet] 이 정한 채움·굵기·등급을 싣고, 광학 크기는 실제로
/// 그려지는 크기에 맞춘다. 기본 묶음([OnCareIconSet.material])은 변형이 없어
/// [Icon] 과 똑같이 그린다 — 트레이너웹 모양이 달라지지 않는다.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final IconData? icon;

  /// 비우면 둘러싼 [IconTheme] 의 크기다(버튼·내비가 정한다).
  final double? size;
  final Color? color;
  final String? semanticLabel;

  /// 현재 테마의 아이콘 묶음. 테마에 토큰이 없으면 기본 묶음이다 — 아이콘은
  /// 브랜드 색과 달리 기본값으로 그려도 어느 앱인지 틀리지 않는다.
  static OnCareIconSet setOf(BuildContext context) =>
      Theme.of(context).extension<OnCareTokens>()?.icons ??
      OnCareIconSet.material;

  /// [icon] 을 묶음의 글꼴 변형을 실은 [Icon] 으로 만든다. `Icon` 타입만 받는
  /// Material 인자(시각 선택기의 모드 전환 등)에 쓴다.
  static Icon resolve(
    BuildContext context,
    IconData? icon, {
    double? size,
    Color? color,
    String? semanticLabel,
  }) {
    final OnCareIconSet set = setOf(context);
    return Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      fill: set.fill,
      weight: set.weightOf(icon),
      grade: set.grade,
      opticalSize: set.opticalSizeFor(size ?? IconTheme.of(context).size),
    );
  }

  /// 캔버스에 **글자로 직접 찍는** 아이콘 하나. [Icon] 을 얹을 수 없는 그림
  /// (도넛·링 위 …)에서 쓴다.
  ///
  /// 캔버스에 직접 그리는 것은 테마를 타지 않으므로, 묶음이 정한 채움·굵기·
  /// 등급·광학 크기를 손으로 붙여 준다 — 붙이지 않으면 같은 아이콘이 화면
  /// 다른 곳에서는 채워지고 그림 위에서만 빈 외곽선으로 나온다(#1866).
  static TextPainter glyphPainter(
    OnCareIconSet set,
    IconData icon, {
    required double size,
    required Color color,
  }) => TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
        fontVariations: set.fontVariationsFor(icon, size),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  Widget build(BuildContext context) => AppIcon.resolve(
    context,
    icon,
    size: size,
    color: color,
    semanticLabel: semanticLabel,
  );
}

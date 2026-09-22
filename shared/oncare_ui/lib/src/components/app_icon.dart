import 'package:flutter/material.dart';

import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
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
    this.outlined = false,
  });

  final IconData? icon;

  /// 비우면 둘러싼 [IconTheme] 의 크기다(버튼·내비가 정한다).
  final double? size;
  final Color? color;
  final String? semanticLabel;

  /// 테두리형이 필요한 보조 동작. 기본값은 앱의 아이콘 테마를 따른다.
  final bool outlined;

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
    bool outlined = false,
  }) {
    final OnCareIconSet set = setOf(context);
    return Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      fill: outlined ? 0 : set.fill,
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
    outlined: outlined,
  );
}

/// AI 챗봇 입구의 마크 — 꽉 찬 말풍선 안에 크기가 다른 별들이 대각선으로
/// 박혀 있다. (#1900)
///
/// 이런 글리프가 아이콘 글꼴에 없어 둘을 겹쳐 만든다. 말풍선만으로는 사람과
/// 하는 대화와 구별되지 않고, 별만으로는 "AI 가 만든 값" 표시로 읽혀 눌러 볼
/// 자리로 보이지 않는다 — 둘이 함께여야 "여기서 AI 와 이야기한다" 가 된다.
///
/// 별은 말풍선 **밖으로 새지 않게** 안쪽 크기로 줄이고, 아래 꼬리만큼 위로
/// 올려 말주머니 한가운데에 놓는다. 색은 뒤에 깔린 바탕색([holeColor])이라
/// 말풍선을 뚫은 것처럼 보인다.
class AppAiChatGlyph extends StatelessWidget {
  const AppAiChatGlyph({
    required this.bubble,
    super.key,
    this.size,
    this.color,
    this.holeColor,
  });

  /// 꽉 찬 말풍선 글리프(앱의 아이콘 등록부에서 온다).
  final IconData bubble;

  /// 비우면 둘러싼 [IconTheme] 의 크기다(버튼이 정한다).
  final double? size;

  /// 말풍선 색. 비우면 [IconTheme] 의 색이다.
  final Color? color;

  /// 별이 뚫고 보이는 바탕색. 비우면 카드 흰색이다.
  final Color? holeColor;

  @override
  Widget build(BuildContext context) {
    final IconThemeData theme = IconTheme.of(context);
    final double dimension = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 채운 말풍선이라야 별이 뚫린 것으로 보인다. 테두리만 있으면 별과
          // 선이 뒤엉켜 무엇인지 읽히지 않는다.
          Icon(
            bubble,
            fill: 1,
            size: dimension,
            color: color ?? theme.color,
          ),
          // 별은 그려서 넣는다. 반짝이 글리프는 별이 셋이라 말주머니 안에서
          // 뭉쳐 보였다 — 크기가 다른 둘만 대각선으로 놓는다.
          CustomPaint(
            size: Size.square(dimension),
            painter: _AiSparkPainter(
              color: holeColor ?? OnCareColors.surfaceCard,
            ),
          ),
        ],
      ),
    );
  }
}

/// 말풍선 안의 별 둘 — 큰 것 위, 작은 것이 왼쪽 아래로 비스듬히. (#1900)
class _AiSparkPainter extends CustomPainter {
  const _AiSparkPainter({required this.color});

  final Color color;

  /// 말주머니의 한가운데(꼬리를 뺀 자리). 글리프 높이 대비.
  static const Offset _pouchCenter = Offset(0.5, 0.44);

  /// 큰 별·작은 별의 중심과 반지름(말주머니 중심 기준, 글리프 크기 대비).
  static const (Offset, double) _big = (Offset(0.06, -0.06), 0.165);
  static const (Offset, double) _small = (Offset(-0.12, 0.10), 0.1);

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    final Offset pouch = Offset(
      _pouchCenter.dx * side,
      _pouchCenter.dy * side,
    );
    final Paint paint = Paint()..color = color;
    for (final (Offset at, double radius) in <(Offset, double)>[_big, _small]) {
      canvas.drawPath(
        _spark(pouch + at * side, radius * side),
        paint,
      );
    }
  }

  /// 네 갈래 별 하나. 꼭짓점에서 허리로 잘록하게 들어오는 곡선이라 `반짝임`
  /// 으로 읽힌다 — 마름모로 그리면 그냥 다이아몬드가 된다.
  static Path _spark(Offset c, double r) {
    final double waist = r * 0.26;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + waist, c.dy - waist, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + waist, c.dy + waist, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - waist, c.dy + waist, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - waist, c.dy - waist, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(_AiSparkPainter oldDelegate) => oldDelegate.color != color;
}

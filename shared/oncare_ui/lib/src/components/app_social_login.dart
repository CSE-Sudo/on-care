import 'package:flutter/material.dart';

import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 원형 소셜 로그인 버튼이 여는 계정 종류(#1783).
enum AppSocialProvider {
  /// 카카오 — 노란 원 + 검은 말풍선 속 노란 `TALK`.
  kakao,

  /// 구글 — 빨간 원 + 흰 `G`.
  google,
}

/// 로그인 화면의 원형 소셜 로그인 버튼(#1783).
///
/// 두 앱이 같은 모양을 쓴다. 로고는 이미지 파일 없이 코드로 그리고, 한 변은
/// 밀도와 무관하게 [OnCareSize.socialLoginButton] 이다.
///
/// 그림만 있는 버튼이라 [label] 이 화면 읽기 이름이자 툴팁이다.
class AppSocialLoginButton extends StatelessWidget {
  const AppSocialLoginButton({
    super.key,
    required this.provider,
    required this.label,
    required this.onPressed,
  });

  final AppSocialProvider provider;

  /// 화면 읽기 이름·툴팁 — 예: `카카오로 시작하기`.
  final String label;

  /// `null` 이면 비활성이다. 계정 회사 표식이라 색은 그대로 두고 탭만 막는다.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (
      Color background,
      Color ink,
      CustomPainter symbol,
    ) = switch (provider) {
      AppSocialProvider.kakao => (
        OnCareColors.kakaoYellow,
        OnCareColors.kakaoSymbol,
        const _KakaoSymbolPainter(),
      ),
      AppSocialProvider.google => (
        OnCareColors.googleRed,
        OnCareColors.textOnFill,
        const _GoogleSymbolPainter(),
      ),
    };
    final bool enabled = onPressed != null;
    return Tooltip(
      message: label,
      // 이름은 아래 Semantics 가 말한다. 툴팁까지 읽히면 같은 말을 두 번 한다.
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            // 눌림은 심볼 색을 옅게 얹는다 — 노랑 위 흰 잉크는 보이지 않는다.
            overlayColor: WidgetStateProperty.resolveWith<Color?>((
              Set<WidgetState> states,
            ) {
              if (states.contains(WidgetState.pressed)) {
                return ink.withValues(alpha: OnCareAlpha.medium);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return ink.withValues(alpha: OnCareAlpha.subtle);
              }
              return null;
            }),
            child: SizedBox.square(
              dimension: OnCareSize.socialLoginButton,
              child: CustomPaint(painter: symbol),
            ),
          ),
        ),
      ),
    );
  }
}

/// 원형 소셜 로그인 버튼 줄(#1783) — 가운데 정렬, 버튼 사이 [OnCareSpacing.s24].
class AppSocialLoginRow extends StatelessWidget {
  const AppSocialLoginRow({super.key, required this.children});

  /// 보통 [AppSocialLoginButton] 들.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: OnCareSpacing.s24,
      children: children,
    );
  }
}

/// 카카오 심볼 — 아래 왼쪽으로 꼬리가 난 검은 말풍선과 그 안의 노란 `TALK`.
///
/// 비율은 원 지름에 대한 값이다.
class _KakaoSymbolPainter extends CustomPainter {
  const _KakaoSymbolPainter();

  static const double _bubbleWidth = 0.62;
  static const double _bubbleHeight = 0.46;

  /// 꼬리 몫만큼 말풍선을 가운데보다 올린다.
  static const double _bubbleLift = 0.04;
  static const double _labelFont = 0.16;

  /// `TALK` 가 말풍선 폭에서 차지할 수 있는 최대 몫.
  static const double _labelMaxWidth = 0.78;

  @override
  void paint(Canvas canvas, Size size) {
    final double d = size.shortestSide;
    final Rect body = Rect.fromCenter(
      center: size.center(Offset.zero).translate(0, -d * _bubbleLift),
      width: d * _bubbleWidth,
      height: d * _bubbleHeight,
    );
    final Paint fill = Paint()..color = OnCareColors.kakaoSymbol;
    canvas.drawOval(body, fill);
    // 꼬리는 따로 채운다 — 한 Path 에 넣으면 감긴 방향에 따라 겹친 곳이 비어 보인다.
    final double cx = body.center.dx;
    canvas.drawPath(
      Path()
        ..moveTo(cx - d * 0.16, body.bottom - d * 0.06)
        ..lineTo(cx - d * 0.20, body.bottom + d * 0.09)
        ..lineTo(cx - d * 0.02, body.bottom - d * 0.02)
        ..close(),
      fill,
    );
    _paintGlyph(
      canvas,
      'TALK',
      center: body.center,
      fontSize: d * _labelFont,
      maxWidth: body.width * _labelMaxWidth,
      color: OnCareColors.kakaoYellow,
    );
  }

  @override
  bool shouldRepaint(covariant _KakaoSymbolPainter oldDelegate) => false;
}

/// 구글 심볼 — 원 가운데 흰 `G`.
class _GoogleSymbolPainter extends CustomPainter {
  const _GoogleSymbolPainter();

  static const double _glyphFont = 0.5;
  static const double _glyphMaxWidth = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final double d = size.shortestSide;
    _paintGlyph(
      canvas,
      'G',
      center: size.center(Offset.zero),
      fontSize: d * _glyphFont,
      maxWidth: d * _glyphMaxWidth,
      color: OnCareColors.textOnFill,
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleSymbolPainter oldDelegate) => false;
}

/// 로고 속 글자를 [center] 에 굵게 그린다.
///
/// 그림의 일부라 기기 글자 배율을 따르지 않는다(`TextPainter` 기본값). 대체 서체가
/// 더 넓게 그려도 [maxWidth] 를 넘지 않게 줄여서 그린다.
void _paintGlyph(
  Canvas canvas,
  String text, {
  required Offset center,
  required double fontSize,
  required double maxWidth,
  required Color color,
}) {
  TextPainter layout(double size) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: OnCareTypography.fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1,
        leadingDistribution: TextLeadingDistribution.even,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  TextPainter painter = layout(fontSize);
  if (painter.width > maxWidth) {
    final double fitted = fontSize * maxWidth / painter.width;
    painter.dispose();
    painter = layout(fitted);
  }
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  painter.dispose();
}

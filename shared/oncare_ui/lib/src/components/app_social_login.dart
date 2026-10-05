import 'package:flutter/material.dart';

import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';

/// 원형 소셜 로그인 버튼이 여는 계정 종류(#1783).
enum AppSocialProvider {
  /// 카카오 — 노란 원 + 검은 말풍선 심볼(카카오 로그인 디자인 가이드).
  kakao,

  /// 구글 — 흰 원 + 회색 테두리 + 네 색 `G` 로고(Google Identity 브랜딩 가이드).
  google,

  /// 네이버 — 그린 원 + 흰 `N` 심볼(네이버 로그인 버튼 가이드).
  naver,

  /// 애플 — 검은 원 + 흰 애플 로고(Sign in with Apple 로고 전용 버튼).
  apple,
}

/// 로그인 화면의 원형 소셜 로그인 버튼(#1783).
///
/// 두 앱이 같은 모양을 쓴다. 계정 회사 표식은 각 회사 가이드의 공식 모양·색을
/// 이미지 파일 없이 코드로 그리고, 한 변은 밀도와 무관하게
/// [OnCareSize.socialLoginButton] 이다.
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
      BorderSide side,
      Color ink,
      CustomPainter logo,
    ) = switch (provider) {
      AppSocialProvider.kakao => (
        OnCareColors.kakaoYellow,
        BorderSide.none,
        OnCareColors.kakaoSymbol,
        const _KakaoSymbolPainter(),
      ),
      AppSocialProvider.google => (
        OnCareColors.googleButtonFill,
        // 가이드의 1px 안쪽 선 — BorderSide 기본 두께·정렬 그대로다.
        const BorderSide(color: OnCareColors.googleButtonStroke),
        OnCareColors.textPrimary,
        const _GoogleLogoPainter(),
      ),
      AppSocialProvider.naver => (
        OnCareColors.naverGreen,
        BorderSide.none,
        OnCareColors.naverSymbol,
        const _NaverSymbolPainter(),
      ),
      AppSocialProvider.apple => (
        OnCareColors.appleButtonFill,
        BorderSide.none,
        OnCareColors.appleLogo,
        const _AppleLogoPainter(),
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
          shape: CircleBorder(side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            // 눌림은 심볼 색을 옅게 얹는다 — 노랑·흰 바탕은 어두운 잉크, 그린·검은
            // 바탕은 흰 잉크라 어느 바탕에서도 보인다.
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
              child: CustomPaint(painter: logo),
            ),
          ),
        ),
      ),
    );
  }
}

/// 원형 소셜 로그인 버튼 줄(#1783) — 가운데 정렬, 버튼 사이 [OnCareSpacing.s24].
///
/// 버튼 네 개(카카오·구글·네이버·애플)는 간격까지 폭 280 이 든다. 로그인 틀(폭 320
/// 화면에서 안쪽 280)에는 그대로 들어간다. 본인 확인 창처럼 더 좁은 자리에서는
/// 줄을 바꾸지 않고 **간격만 똑같이 줄여** 한 줄을 지킨다 — 줄을 바꾸면 3개+1개로
/// 갈라지고, 높이가 정해진 창에서는 넷째 버튼이 스크롤 아래로 숨었다.
class AppSocialLoginRow extends StatelessWidget {
  const AppSocialLoginRow({super.key, required this.children});

  /// 보통 [AppSocialLoginButton] 들.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // 간격 자리는 유연하다 — 남는 폭을 똑같이 나눠 받되 24 를 넘지 않는다.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const Flexible(child: SizedBox(width: OnCareSpacing.s24)),
          children[i],
        ],
      ],
    );
  }
}

/// 원본 좌표계 [viewBox] 한 변짜리 로고를 원 가운데에 지름 × [ratio] 크기로 그린다.
void _paintCentered(
  Canvas canvas,
  Size size, {
  required double ratio,
  required double viewBox,
  required void Function(Canvas canvas) draw,
}) {
  final double side = size.shortestSide * ratio;
  canvas
    ..save()
    ..translate((size.width - side) / 2, (size.height - side) / 2)
    ..scale(side / viewBox);
  draw(canvas);
  canvas.restore();
}

/// 카카오 말풍선 심볼 — 카카오 로그인 디자인 가이드의 심볼(18×18 좌표계).
///
/// 글자 없이 검은 말풍선 하나다.
class _KakaoSymbolPainter extends CustomPainter {
  const _KakaoSymbolPainter();

  /// 원 지름에 대한 심볼 한 변.
  static const double _ratio = 0.46;
  static const double _viewBox = 18;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCentered(
      canvas,
      size,
      ratio: _ratio,
      viewBox: _viewBox,
      draw: (Canvas canvas) => canvas.drawPath(
        Path()
          ..moveTo(9, 0.6)
          ..cubicTo(4.02917, 0.6, 0, 3.71296, 0, 7.55229)
          ..cubicTo(0, 9.94003, 1.55847, 12.0452, 3.93152, 13.2969)
          ..lineTo(2.93303, 16.9446)
          ..cubicTo(2.84481, 17.2669, 3.21341, 17.5239, 3.49646, 17.3371)
          ..lineTo(7.87334, 14.4483)
          ..cubicTo(8.2427, 14.4839, 8.61808, 14.5046, 9, 14.5046)
          ..cubicTo(13.9705, 14.5046, 17.9999, 11.3917, 17.9999, 7.55229)
          ..cubicTo(17.9999, 3.71296, 13.9705, 0.6, 9, 0.6)
          ..close(),
        Paint()..color = OnCareColors.kakaoSymbol,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _KakaoSymbolPainter oldDelegate) => false;
}

/// 구글 `G` 로고 — Google Identity 브랜딩 가이드의 네 색 로고(48×48 좌표계).
///
/// 조각 순서는 빨강(위) · 파랑(오른쪽 가로획) · 노랑(왼쪽) · 초록(아래)이다.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  /// 원 지름에 대한 로고 한 변. 가이드의 아이콘 버튼(40 안에 20)과 같은 비율이다.
  static const double _ratio = 0.5;
  static const double _viewBox = 48;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCentered(
      canvas,
      size,
      ratio: _ratio,
      viewBox: _viewBox,
      draw: (Canvas canvas) {
        canvas
          ..drawPath(
            Path()
              ..moveTo(24, 9.5)
              ..relativeCubicTo(3.54, 0, 6.71, 1.22, 9.21, 3.6)
              ..relativeLineTo(6.85, -6.85)
              ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
              ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
              ..relativeLineTo(7.98, 6.19)
              ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
              ..close(),
            Paint()..color = OnCareColors.googleRed,
          )
          ..drawPath(
            Path()
              ..moveTo(46.98, 24.55)
              ..relativeCubicTo(0, -1.57, -0.15, -3.09, -0.38, -4.55)
              ..lineTo(24, 20)
              ..relativeLineTo(0, 9.02)
              ..relativeLineTo(12.94, 0)
              ..relativeCubicTo(-0.58, 2.96, -2.26, 5.48, -4.78, 7.18)
              ..relativeLineTo(7.73, 6)
              ..relativeCubicTo(4.51, -4.18, 7.09, -10.36, 7.09, -17.65)
              ..close(),
            Paint()..color = OnCareColors.googleBlue,
          )
          ..drawPath(
            Path()
              ..moveTo(10.53, 28.59)
              ..relativeCubicTo(-0.48, -1.45, -0.76, -2.99, -0.76, -4.59)
              ..relativeCubicTo(0, -1.6, 0.27, -3.14, 0.76, -4.59)
              ..relativeLineTo(-7.98, -6.19)
              ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
              ..relativeCubicTo(0, 3.88, 0.92, 7.54, 2.56, 10.78)
              ..relativeLineTo(7.97, -6.19)
              ..close(),
            Paint()..color = OnCareColors.googleYellow,
          )
          ..drawPath(
            Path()
              ..moveTo(24, 48)
              ..relativeCubicTo(6.48, 0, 11.93, -2.13, 15.89, -5.81)
              ..relativeLineTo(-7.73, -6)
              ..relativeCubicTo(-2.15, 1.45, -4.92, 2.3, -8.16, 2.3)
              ..relativeCubicTo(-6.26, 0, -11.57, -4.22, -13.47, -9.91)
              ..relativeLineTo(-7.98, 6.19)
              ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
              ..close(),
            Paint()..color = OnCareColors.googleGreen,
          );
      },
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleLogoPainter oldDelegate) => false;
}

/// 네이버 `N` 심볼 — 네이버 로그인 버튼의 흰 `N`(24×24 좌표계).
///
/// 모양은 Simple Icons 의 Naver 아이콘(CC0) 경로를 그대로 옮겼다.
class _NaverSymbolPainter extends CustomPainter {
  const _NaverSymbolPainter();

  /// 원 지름에 대한 심볼 한 변. 정사각형을 꽉 채우는 글자라 다른 로고보다 작게 둔다.
  static const double _ratio = 0.34;
  static const double _viewBox = 24;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCentered(
      canvas,
      size,
      ratio: _ratio,
      viewBox: _viewBox,
      draw: (Canvas canvas) => canvas.drawPath(
        Path()
          ..moveTo(16.273, 12.845)
          ..lineTo(7.376, 0)
          ..lineTo(0, 0)
          ..lineTo(0, 24)
          ..lineTo(7.726, 24)
          ..lineTo(7.726, 11.156)
          ..lineTo(16.624, 24)
          ..lineTo(24, 24)
          ..lineTo(24, 0)
          ..lineTo(16.273, 0)
          ..close(),
        Paint()..color = OnCareColors.naverSymbol,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _NaverSymbolPainter oldDelegate) => false;
}

/// 애플 로고 — Sign in with Apple 로고 전용 버튼의 흰 사과(24×24 좌표계).
///
/// 모양은 Simple Icons 의 Apple 아이콘(CC0) 경로를 옮겼다. 몸통과 잎 두 조각이다.
class _AppleLogoPainter extends CustomPainter {
  const _AppleLogoPainter();

  /// 원 지름에 대한 로고 한 변.
  static const double _ratio = 0.44;
  static const double _viewBox = 24;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCentered(
      canvas,
      size,
      ratio: _ratio,
      viewBox: _viewBox,
      draw: (Canvas canvas) => canvas.drawPath(
        Path()
          // 몸통
          ..moveTo(12.152, 6.896)
          ..cubicTo(11.204, 6.896, 9.737, 5.818, 8.192, 5.856)
          ..cubicTo(6.152, 5.883, 4.282, 7.039, 3.231, 8.87)
          ..cubicTo(1.114, 12.545, 2.685, 17.973, 4.75, 20.96)
          ..cubicTo(5.763, 22.414, 6.958, 24.05, 8.542, 23.999)
          ..cubicTo(10.062, 23.934, 10.632, 23.012, 12.477, 23.012)
          ..cubicTo(14.308, 23.012, 14.827, 23.999, 16.437, 23.96)
          ..cubicTo(18.074, 23.934, 19.113, 22.48, 20.113, 21.012)
          ..cubicTo(21.269, 19.324, 21.749, 17.687, 21.775, 17.597)
          ..cubicTo(21.736, 17.584, 18.593, 16.376, 18.555, 12.74)
          ..cubicTo(18.529, 9.7, 21.035, 8.246, 21.152, 8.181)
          ..cubicTo(19.723, 6.091, 17.529, 5.857, 16.762, 5.805)
          ..cubicTo(14.762, 5.649, 13.087, 6.895, 12.152, 6.895)
          ..close()
          // 잎
          ..moveTo(15.53, 3.83)
          ..cubicTo(16.373, 2.818, 16.93, 1.403, 16.775, 0)
          ..cubicTo(15.568, 0.052, 14.113, 0.805, 13.243, 1.818)
          ..cubicTo(12.463, 2.714, 11.789, 4.156, 11.97, 5.532)
          ..cubicTo(13.308, 5.636, 14.685, 4.844, 15.529, 3.831)
          ..close(),
        Paint()..color = OnCareColors.appleLogo,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _AppleLogoPainter oldDelegate) => false;
}

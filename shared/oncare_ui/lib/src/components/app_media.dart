import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/motion.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 아바타 크기.
enum AppAvatarSize {
  small(OnCareSize.avatarSmall),
  medium(OnCareSize.avatarMedium),
  large(OnCareSize.avatarLarge),
  xLarge(OnCareSize.avatarXLarge);

  const AppAvatarSize(this.dimension);
  final double dimension;
}

/// 사람 아바타(#1697) — 옅은 브랜드 채움 + 브랜드 이니셜 600, 사진이 있으면 사진.
///
/// 사람 아바타의 그라디언트는 없다. [online] 이면 오른쪽 아래 상태 점(지름 25%)을 단다.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.image,
    this.size = AppAvatarSize.medium,
    this.online,
  });

  final String name;
  final ImageProvider<Object>? image;
  final AppAvatarSize size;

  /// null 이면 상태 점을 달지 않는다.
  final bool? online;

  String get _initials {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final List<String> parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return (parts.first.characters.first + parts.last.characters.first)
          .toUpperCase();
    }
    return trimmed.characters
        .take(trimmed.runes.every((r) => r < 128) ? 2 : 1)
        .toString()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final double d = size.dimension;
    final Widget circle = Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.brand.surface,
        shape: BoxShape.circle,
        image: image == null
            ? null
            : DecorationImage(image: image!, fit: BoxFit.cover),
      ),
      child: image != null
          ? null
          : Text(
              _initials,
              style: tokens
                  .text(
                    size.index <= AppAvatarSize.medium.index
                        ? OnCareTypography.strong(OnCareTypography.caption)
                        : OnCareTypography.label,
                  )
                  .copyWith(color: tokens.brand.primary, height: 1),
            ),
    );
    return Semantics(
      label: name,
      image: true,
      child: online == null
          ? circle
          : Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                circle,
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: d * 0.25,
                    height: d * 0.25,
                    decoration: BoxDecoration(
                      color: online!
                          ? OnCareColors.success
                          : OnCareColors.textDisabled,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: OnCareColors.surfaceCard,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 마스코트 오니 — 브랜드 그라디언트 원 + 흰 얼굴. 마스코트만 그라디언트 예외다.
class OniAvatar extends StatelessWidget {
  const OniAvatar({super.key, this.size = OnCareSize.avatarLarge});

  final double size;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[tokens.brand.primary, tokens.brand.strong],
        ),
      ),
      child: Center(
        child: CustomPaint(
          size: Size.square(size * 0.58),
          painter: const _OniFacePainter(OnCareColors.textOnFill),
        ),
      ),
    );
  }
}

class _OniFacePainter extends CustomPainter {
  const _OniFacePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 24.0;
    final Paint fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(7.6 * s, 8.7 * s), 1.5 * s, fill);
    canvas.drawCircle(Offset(16.4 * s, 8.7 * s), 1.5 * s, fill);
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * s
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(
      Path()
        ..moveTo(7.2 * s, 15 * s)
        ..quadraticBezierTo(12 * s, 19.2 * s, 16.8 * s, 15 * s),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _OniFacePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 이미지 틀 — 반경 12(기본) 또는 20, 자리 표시는 입력 채움 + 아이콘.
class AppImageFrame extends StatelessWidget {
  const AppImageFrame({
    super.key,
    this.image,
    this.width,
    this.height,
    this.large = false,
    this.placeholderIcon,
    this.child,
  });

  final ImageProvider<Object>? image;
  final double? width;
  final double? height;

  /// 카드급 큰 이미지(지도 등)면 반경 20.
  final bool large;

  /// 비우면 아이콘 묶음의 이미지 아이콘이다.
  final IconData? placeholderIcon;

  /// 지도처럼 이미지 대신 위젯을 담을 때.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: large ? OnCareRadius.xlAll : OnCareRadius.mdAll,
      child: Container(
        width: width,
        height: height,
        color: OnCareColors.surfaceInput,
        child:
            child ??
            (image == null
                ? Center(
                    child: AppIcon(
                      placeholderIcon ?? AppIcon.setOf(context).image,
                      size: OnCareSize.iconLarge,
                      color: OnCareColors.textTertiary,
                    ),
                  )
                : Image(image: image!, fit: BoxFit.cover)),
      ),
    );
  }
}

/// 진행 막대 — 높이 8, 알약, 트랙 입력 채움, 채움 기본 브랜드색.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value, this.color});

  /// 0~1. 넘치면 1 로 그린다.
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color fill = color ?? context.oncare.brand.primary;
    return ClipRRect(
      borderRadius: OnCareRadius.pillAll,
      child: SizedBox(
        height: OnCareSize.progressBar,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: value.clamp(0.0, 1.0)),
          duration: OnCareMotion.meterFill,
          curve: OnCareMotion.curve,
          builder: (BuildContext context, double t, Widget? _) =>
              LinearProgressIndicator(
                value: t,
                minHeight: OnCareSize.progressBar,
                color: fill,
                backgroundColor: OnCareColors.surfaceInput,
              ),
        ),
      ),
    );
  }
}

/// 단계 표시 — N칸 막대(4px) + 현재 단계 `caption` 라벨.
class AppStepIndicator extends StatelessWidget {
  const AppStepIndicator({
    super.key,
    required this.count,
    required this.current,
    this.label,
    this.onStepTap,
  });

  final int count;

  /// 0 부터.
  final int current;
  final String? label;
  final ValueChanged<int>? onStepTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < count; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: OnCareSpacing.s4),
              Expanded(
                child: GestureDetector(
                  onTap: onStepTap == null ? null : () => onStepTap!(i),
                  child: Container(
                    height: OnCareSize.stepBar,
                    decoration: BoxDecoration(
                      color: i <= current
                          ? tokens.brand.primary
                          : OnCareColors.surfaceInput,
                      borderRadius: OnCareRadius.pillAll,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (label != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            label!,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

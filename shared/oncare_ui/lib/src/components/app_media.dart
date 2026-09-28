import 'dart:math' as math;

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
///
/// 카드 밖 페이지 배경 위에 놓일 때는 [height]·[trackColor] 로 두께와 빈 구간
/// 색을 바꾼다. 기본 트랙(입력 채움)은 페이지 배경과 거의 같은 색이다.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = OnCareSize.progressBar,
    this.trackColor = OnCareColors.surfaceInput,
  });

  /// 0~1. 넘치면 1 로 그린다.
  final double value;
  final Color? color;

  /// 막대 두께.
  final double height;

  /// 채워지지 않은 구간 색.
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final Color fill = color ?? context.oncare.brand.primary;
    return ClipRRect(
      borderRadius: OnCareRadius.pillAll,
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: value.clamp(0.0, 1.0)),
          duration: OnCareMotion.meterFill,
          curve: OnCareMotion.curve,
          builder: (BuildContext context, double t, Widget? _) =>
              LinearProgressIndicator(
                value: t,
                minHeight: height,
                color: fill,
                backgroundColor: trackColor,
              ),
        ),
      ),
    );
  }
}

/// 단계 표시.
///
/// - 기본: N칸 막대(4px) + 현재 단계 `caption` 라벨 — 회원앱 온보딩.
/// - [AppStepIndicator.numbered]: 번호 원 `① → ② → ③` + 단계마다 이름 —
///   트레이너웹 AI 추천안 만들기·주간 리포트 작성(#2232, #2469).
class AppStepIndicator extends StatelessWidget {
  const AppStepIndicator({
    super.key,
    required int count,
    required this.current,
    this.label,
    this.onStepTap,
  }) : _count = count,
       labels = null,
       maxReached = null,
       semanticsLabel = null,
       keyPrefix = 'step',
       skipped = const <int>{},
       skippedLabel = '',
       gap = numberedGap;

  /// 번호형 — 지나온 단계([maxReached] 까지)만 눌러 되돌아갈 수 있다.
  const AppStepIndicator.numbered({
    super.key,
    required List<String> this.labels,
    required this.current,
    required int this.maxReached,
    required ValueChanged<int> this.onStepTap,
    required String this.semanticsLabel,
    this.keyPrefix = 'step',
    this.skipped = const <int>{},
    this.skippedLabel = '',
    this.gap = numberedGap,
  }) : _count = null,
       label = null;

  final int? _count;

  /// 칸 수.
  int get count => labels?.length ?? _count!;

  /// 0 부터.
  final int current;
  final String? label;
  final ValueChanged<int>? onStepTap;

  /// 번호형의 단계 이름. 로케일을 따르므로 호출자가 만들어 넘긴다. 칸 수는
  /// 받은 만큼이다(#2223).
  final List<String>? labels;

  /// 번호형에서 지금까지 가 본 가장 먼 단계.
  final int? maxReached;

  /// 번호형에서 스크린 리더가 읽을 묶음 이름.
  final String? semanticsLabel;

  /// 번호형 단계 위젯 키의 앞자리 — `'$keyPrefix-$index'`.
  final String keyPrefix;

  /// 이번 흐름에서 밟지 않는 칸. 자리를 지우지 않고 흐리게 남겨
  /// [skippedLabel] 을 붙인다 — 칸이 사라지면 흐름이 짧아진 것처럼 보인다.
  final Set<int> skipped;

  /// 건너뛴 칸 아래에 붙는 말.
  final String skippedLabel;

  /// 번호 원 사이 간격.
  final double gap;

  /// 번호형 기본 원 사이 간격.
  static const double numberedGap = OnCareSpacing.s48 + OnCareSpacing.s32;

  /// 번호 원의 지름.
  static const double _circle = OnCareSize.avatarMedium;

  @override
  Widget build(BuildContext context) {
    return labels == null ? _bars(context) : _numbered(context);
  }

  Widget _bars(BuildContext context) {
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

  bool _open(int index) => index <= maxReached! && !skipped.contains(index);

  Widget _numbered(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final List<String> names = labels!;
    // 칸 폭이 곧 원 중심 사이의 거리다. 화면 폭을 n등분하면 창이 넓어질수록
    // 원들이 좌우 끝으로 멀어진다 — 폭과 무관하게 같은 간격으로 모여
    // 가운데에 선다(#2219).
    final double fullStep = _circle + gap;
    return Semantics(
      // 이름만 달면 스크린리더에 닿지 않는다 — 아래 단계들이 저마다 노드를
      // 만들어 얹을 자리가 없다. 묶음 노드를 만들어 이름을 그 위에 단다.
      container: true,
      explicitChildNodes: true,
      label: semanticsLabel,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 칸을 다 늘어놓을 폭이 없으면(아주 좁은 창) 그만큼 좁힌다.
          final double available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : fullStep * names.length;
          final double stepWidth = math.min(fullStep, available / names.length);
          return Center(
            child: SizedBox(
              width: stepWidth * names.length,
              child: Stack(
                children: <Widget>[
                  // 첫 원의 가운데에서 마지막 원의 가운데까지만 잇는 가는 선.
                  Positioned(
                    top: (_circle - OnCareSize.hairline) / 2,
                    left: stepWidth / 2,
                    right: stepWidth / 2,
                    child: const ColoredBox(
                      color: OnCareColors.lineSubtle,
                      child: SizedBox(height: OnCareSize.hairline),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int index = 0; index < names.length; index++)
                        SizedBox(
                          width: stepWidth,
                          child: _numberedStep(
                            context,
                            tokens,
                            names[index],
                            index,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _numberedStep(
    BuildContext context,
    OnCareTokens tokens,
    String name,
    int index,
  ) {
    final bool isCurrent = index == current;
    final bool isSkipped = skipped.contains(index);
    return InkWell(
      key: ValueKey<String>('$keyPrefix-$index'),
      borderRadius: OnCareRadius.smAll,
      onTap: _open(index) ? () => onStepTap!(index) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: _circle,
            height: _circle,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? tokens.brand.primary
                  : OnCareColors.surfaceInput,
              border: isCurrent
                  ? null
                  : Border.all(
                      color: isSkipped
                          ? OnCareColors.lineSubtle
                          : OnCareColors.lineStrong,
                    ),
            ),
            // 건너뛴 칸은 번호 대신 가로줄 — 밟지 않았을 뿐 자리는 그대로다.
            child: isSkipped
                ? AppIcon(
                    AppIcon.setOf(context).remove,
                    size: OnCareSize.iconSmall,
                    color: OnCareColors.textTertiary,
                  )
                : Text(
                    '${index + 1}',
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.label))
                        .copyWith(
                          color: isCurrent
                              ? OnCareColors.textOnFill
                              : OnCareColors.textSecondary,
                        ),
                  ),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: tokens
                .text(
                  isCurrent
                      ? OnCareTypography.strong(OnCareTypography.caption)
                      : OnCareTypography.caption,
                )
                .copyWith(
                  color: isCurrent
                      ? OnCareColors.textPrimary
                      : OnCareColors.textTertiary,
                ),
          ),
          if (isSkipped)
            Text(
              skippedLabel,
              key: ValueKey<String>('$keyPrefix-skipped-$index'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textTertiary),
            ),
        ],
      ),
    );
  }
}

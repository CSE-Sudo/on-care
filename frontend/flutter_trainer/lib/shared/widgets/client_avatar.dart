import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이니셜 글씨 크기 : 지름.
const double _kInitialFactor = 0.34;

/// The navy gradient circle + initial used for a client everywhere they
/// appear (list card, detail header, chat bubbles). Optionally shows an
/// active-status dot.
class ClientAvatar extends StatelessWidget {
  /// Creates an avatar showing [label]'s initial.
  const ClientAvatar({
    super.key,
    required this.label,
    this.size = 44,
    this.showStatus = false,
    this.active = false,
  });

  /// Single-char label (e.g. 김).
  final String label;

  /// Diameter in logical pixels.
  final double size;

  /// Whether to render the bottom-right active/inactive dot.
  final bool showStatus;

  /// Active (green) vs inactive (grey) — only used when [showStatus].
  final bool active;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            OnCareBrand.trainer.primary,
            OnCareBrand.trainer.strong,
          ],
        ),
      ),
      child: Text(
        label,
        // 이니셜은 지름에 비례한다 — 굵기·서체는 역할에서, 크기만 지름에서.
        style: OnCareTypography.titleSmall.copyWith(
          color: OnCareColors.textOnFill,
          fontSize: size * _kInitialFactor,
        ),
      ),
    );

    if (!showStatus) return circle;

    final dot = size * 0.27;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          circle,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? OnCareColors.success
                    : OnCareColors.textDisabled,
                border: Border.all(color: OnCareColors.surfaceCard, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

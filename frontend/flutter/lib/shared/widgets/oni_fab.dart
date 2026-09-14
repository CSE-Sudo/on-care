import 'package:flutter/material.dart';

import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// The floating "Oni" assistant button shown on every main tab. Taps open the
/// coaching sheet. A red badge shows the number of pending suggestions.
/// Mirrors the Figma FAB.
///
/// [badgeCount] 기본값은 0 이다. 예전에는 2 로 두고 부르는 쪽이 값을 넘기지 않아,
/// 제안 수와 무관하게 늘 '2' 가 떠 있었다 — 다 읽어도 사라지지 않았다(#788).
/// 셀 수 없을 때는 배지를 아예 그리지 않는 편이 상수보다 정직하다.
class OniFab extends StatelessWidget {
  const OniFab({super.key, required this.onTap, this.badgeCount = 0});

  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    // 온이 얼굴은 `CustomPaint` 라 안에 읽을 글자가 없다 — 무엇을 여는
    // 버튼인지 라벨로 말한다(#972).
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).a11yOpenCoaching,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.square(
          dimension: OnCareSize.avatarXLarge,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              // 떠 있는 요소라 떠 있는 그림자 한 가지만 쓴다(#1690).
              const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: OnCareShadows.overlay,
                ),
                child: OniAvatar(size: OnCareSize.avatarXLarge),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -OnCareSpacing.s4,
                  right: -OnCareSpacing.s4,
                  child: AppCountBadge(count: badgeCount),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

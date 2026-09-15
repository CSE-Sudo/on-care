import 'package:flutter/painting.dart';

import 'package:oncare_ui/src/tokens/colors.dart';

/// 그림자 두 가지(#1690 §6)와 세그먼트 엄지 그림자(#1777). 이 밖의 `BoxShadow` 는
/// 쓰지 않는다.
class OnCareShadows {
  OnCareShadows._();

  /// 카드.
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// 떠 있는 요소 — 메뉴·토스트·다이얼로그·차트 툴팁.
  static const List<BoxShadow> overlay = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// 세그먼트 토글 `thumb` 모양에서 선택 칸(흰 알약) 아래 깔리는 옅은 브랜드
  /// 그림자(#1777). `AppSegmentedToggle` 안에서만 쓴다.
  ///
  /// 이식 전 트레이너웹 식단/운동 스트립의 값(메인 색 15%, 흐림 10, 아래로 2)이다.
  /// 투명도는 단계 밖 값을 두지 않으려 가장 가까운 [OnCareAlpha.medium] 에 맞췄다.
  /// 색이 브랜드를 따르므로 상수가 아니라 함수다.
  static List<BoxShadow> segmentThumb(Color tint) => <BoxShadow>[
    BoxShadow(
      color: tint.withValues(alpha: OnCareAlpha.medium),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  /// Material `elevation` 을 받는 위젯(메뉴·스낵바)에 줄 값.
  static const double overlayElevation = 6;
}

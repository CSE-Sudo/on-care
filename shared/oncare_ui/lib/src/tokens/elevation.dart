import 'package:flutter/painting.dart';

/// 그림자 두 가지(#1690 §6). 이 밖의 `BoxShadow` 는 쓰지 않는다.
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

  /// Material `elevation` 을 받는 위젯(메뉴·스낵바)에 줄 값.
  static const double overlayElevation = 6;
}

import 'package:flutter/material.dart';

import 'package:oncare/design_system/tokens/typography.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원앱 테마. 규격은 두 앱이 함께 쓰는 `oncare_ui` 한 곳에 있다(#1691).
///
/// 앱이 정하는 것은 브랜드(회원 파랑)와 밀도(모바일)뿐이다. 라이트 전용이다(#1604).
class AppTheme {
  AppTheme._();

  /// 전역 글자 배율([AppTypography.textScale])은 모든 화면이 역할 글자로 옮겨 갈
  /// 때까지 남겨 둔다. 테마 글자는 그만큼 나눠 보이는 크기를 규격과 맞춘다(#1707).
  static ThemeData light() => OnCareTheme.light(
    brand: OnCareBrand.member,
    density: OnCareDensity.mobile,
    legacyTextScale: AppTypography.textScale,
  );
}

import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원앱 테마. 규격은 두 앱이 함께 쓰는 `oncare_ui` 한 곳에 있다(#1691).
///
/// 앱이 정하는 것은 브랜드(회원 파랑)·밀도(모바일)·아이콘 묶음(Material Symbols,
/// #1803)이다. 라이트 전용이다(#1604).
class AppTheme {
  AppTheme._();

  static ThemeData light() => OnCareTheme.light(
    brand: OnCareBrand.member,
    density: OnCareDensity.mobile,
    icons: AppIcons.oncare,
  );
}

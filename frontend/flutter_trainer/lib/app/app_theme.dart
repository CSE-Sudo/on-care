import 'package:flutter/material.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너웹 테마. 규격은 두 앱이 함께 쓰는 `oncare_ui` 한 곳에 있다(#1691).
///
/// 앱이 정하는 것은 브랜드(트레이너 남색)·밀도(웹)·아이콘 묶음(회원앱과 같은
/// Material Symbols, #2466)이다.
class AppTheme {
  AppTheme._();

  static ThemeData light() => OnCareTheme.light(
    brand: OnCareBrand.trainer,
    density: OnCareDensity.web,
    icons: AppIcons.oncare,
  );
}

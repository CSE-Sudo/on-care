/// 결과지를 화면 밖에서 굽기 위한 틀 — 두 앱이 같은 한 장을 내게 한다. (#2652)
library;

import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 결과지를 굽는 테마.
///
/// 결과지는 트레이너가 회원에게 보내는 문서다. 회원 앱이 같은 주를 자기 테마로
/// 구우면 색·글자 크기가 달라, 트레이너가 첨부로 보낸 파일과 회원 앱이 연 파일이
/// 서로 다른 문서처럼 보인다. 그래서 어느 앱에서 굽든 **트레이너 웹의 테마**
/// (트레이너 브랜드·웹 밀도)로 고정한다. 결과지는 아이콘을 쓰지 않아 아이콘
/// 묶음은 기본값으로 둔다.
ThemeData reportSheetTheme() => OnCareTheme.light(
  brand: OnCareBrand.trainer,
  density: OnCareDensity.web,
);

/// 화면 밖 트리가 앱 안에서처럼 그려지도록 로케일·글자 배율·테마를 두른다.
///
/// [delegates] 는 부르는 앱의 것이다 — 결과지 문구는 이 패키지가 들고 있지만,
/// `Material` 이 찾는 기본 문구는 앱이 준다.
Widget reportSheetFrame({
  required Locale locale,
  required Iterable<LocalizationsDelegate<dynamic>> delegates,
  required Widget sheet,
}) => Localizations(
  locale: locale,
  delegates: delegates.toList(growable: false),
  child: MediaQuery(
    // 문서는 사용자의 글자 배율과 상관없이 같은 크기로 나가야 한다.
    data: const MediaQueryData(textScaler: TextScaler.noScaling),
    child: Theme(
      data: reportSheetTheme(),
      child: Material(color: OnCareColors.surfaceCard, child: sheet),
    ),
  ),
);

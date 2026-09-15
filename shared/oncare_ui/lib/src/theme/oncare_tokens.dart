import 'package:flutter/material.dart';

import 'package:oncare_ui/src/tokens/brand.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/density.dart';
import 'package:oncare_ui/src/tokens/icons.dart';

/// 테마에 실린 브랜드·밀도·아이콘 묶음. 컴포넌트는 앱 이름으로 분기하지 않고
/// 이것만 읽는다.
@immutable
class OnCareTokens extends ThemeExtension<OnCareTokens> {
  const OnCareTokens({
    required this.brand,
    required this.density,
    this.icons = OnCareIconSet.material,
  });

  final OnCareBrand brand;
  final OnCareDensity density;

  /// 공용 컴포넌트가 그리는 아이콘 묶음(#1803). 트레이너웹은 기본 묶음이다.
  final OnCareIconSet icons;

  /// 화면이 쓰는 역할 글자. 전역 글자 배율이 없어져(#1707) 역할 크기 그대로다 —
  /// 글자를 그리는 곳이 한 통로를 지나도록 남겨 둔다.
  TextStyle text(TextStyle style) => style;

  /// 페이지 배경. 회원앱(모바일)은 흰색, 트레이너웹은 연회색 위에 흰 카드를
  /// 얹는다(#1740).
  Color get pageBackground =>
      density.isWeb ? OnCareColors.surfacePage : OnCareColors.surfaceCard;

  @override
  OnCareTokens copyWith({
    OnCareBrand? brand,
    OnCareDensity? density,
    OnCareIconSet? icons,
  }) => OnCareTokens(
    brand: brand ?? this.brand,
    density: density ?? this.density,
    icons: icons ?? this.icons,
  );

  /// 브랜드·밀도·아이콘 묶음은 연속값이 아니라 중간이 없다.
  @override
  OnCareTokens lerp(covariant OnCareTokens? other, double t) =>
      t < 0.5 || other == null ? this : other;

  @override
  bool operator ==(Object other) =>
      other is OnCareTokens &&
      other.brand == brand &&
      other.density == density &&
      other.icons == icons;

  @override
  int get hashCode => Object.hash(brand, density, icons);
}

extension OnCareTokensContext on BuildContext {
  /// 현재 테마의 브랜드·밀도.
  ///
  /// `OnCareTheme.light` 로 만든 테마 아래에서만 부를 수 있다. 없으면 어느 앱의
  /// 값으로 그려야 할지 알 수 없으므로 조용히 기본값을 쓰지 않고 실패한다.
  OnCareTokens get oncare {
    final OnCareTokens? tokens = Theme.of(this).extension<OnCareTokens>();
    if (tokens == null) {
      throw FlutterError(
        'OnCareTokens 가 테마에 없습니다. MaterialApp.theme 을 '
        'OnCareTheme.light(...) 로 만드세요.',
      );
    }
    return tokens;
  }
}

import 'package:flutter/material.dart';

import 'package:oncare_ui/src/tokens/brand.dart';
import 'package:oncare_ui/src/tokens/density.dart';

/// 테마에 실린 브랜드·밀도. 컴포넌트는 앱 이름으로 분기하지 않고 이것만 읽는다.
@immutable
class OnCareTokens extends ThemeExtension<OnCareTokens> {
  const OnCareTokens({required this.brand, required this.density});

  final OnCareBrand brand;
  final OnCareDensity density;

  /// 화면이 쓰는 역할 글자. 전역 글자 배율이 없어져(#1707) 역할 크기 그대로다 —
  /// 글자를 그리는 곳이 한 통로를 지나도록 남겨 둔다.
  TextStyle text(TextStyle style) => style;

  @override
  OnCareTokens copyWith({OnCareBrand? brand, OnCareDensity? density}) =>
      OnCareTokens(
        brand: brand ?? this.brand,
        density: density ?? this.density,
      );

  /// 브랜드·밀도는 연속값이 아니라 중간이 없다.
  @override
  OnCareTokens lerp(covariant OnCareTokens? other, double t) =>
      t < 0.5 || other == null ? this : other;

  @override
  bool operator ==(Object other) =>
      other is OnCareTokens && other.brand == brand && other.density == density;

  @override
  int get hashCode => Object.hash(brand, density);
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

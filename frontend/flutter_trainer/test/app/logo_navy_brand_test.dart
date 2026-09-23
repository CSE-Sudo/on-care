import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너 **메인 색**은 로고 네이비와 같은 값이어야 한다(#2173, #2207).
///
/// 사이드바는 로고와 `트레이너` 글씨를 나란히 놓는다. 둘이 다른 남색이면 그
/// 자리에서 바로 보이고, 메인 색은 CTA·활성 내비·그래프까지 끌고 다니므로
/// 화면 전체가 로고와 어긋난다. 로고 SVG 를 바꾸거나 토큰만 따로 고치면
/// 같은 역할의 남색이 다시 두 가지가 된다.
void main() {
  test('trainer primary navy matches the navy logo fill', () {
    final String svg = File(
      'assets/images/oncare-logo-navy.svg',
    ).readAsStringSync();
    final Iterable<String> fills = RegExp(r'fill="#([0-9A-Fa-f]{6})"')
        .allMatches(svg)
        .map((m) => m.group(1)!.toUpperCase())
        .where((hex) => hex != 'FFFFFF');
    expect(fills, isNotEmpty);
    for (final String hex in fills) {
      expect(
        Color(int.parse('FF$hex', radix: 16)),
        OnCareBrand.trainer.primary,
      );
    }
  });
}

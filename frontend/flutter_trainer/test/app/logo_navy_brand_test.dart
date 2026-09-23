import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너 진한 네이비는 로고 네이비와 같은 값이어야 한다(#2173).
///
/// 로고 SVG 를 바꾸거나 토큰만 따로 고치면 같은 역할의 남색이 다시 두 가지가 된다.
void main() {
  test('trainer strong navy matches the navy logo fill', () {
    final String svg = File(
      'assets/images/oncare-logo-navy.svg',
    ).readAsStringSync();
    final Iterable<String> fills = RegExp(r'fill="#([0-9A-Fa-f]{6})"')
        .allMatches(svg)
        .map((m) => m.group(1)!.toUpperCase())
        .where((hex) => hex != 'FFFFFF');
    expect(fills, isNotEmpty);
    for (final String hex in fills) {
      expect(Color(int.parse('FF$hex', radix: 16)), OnCareBrand.trainer.strong);
    }
  });
}

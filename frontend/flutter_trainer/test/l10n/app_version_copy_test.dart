/// 버전 문구에 고정 숫자가 없는지(#2264, #3047).
///
/// 버전은 빌드의 `version.json` 에서 읽는다. 문구에는 자리표시만 둔다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final RegExp fixedVersion = RegExp(r'\b\d+\.\d+\.\d+\b');

  for (final String locale in <String>['ko', 'en']) {
    group('app_$locale.arb', () {
      final Map<String, dynamic> arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;

      test('버전 문구는 자리표시를 쓴다', () {
        expect(arb['myAppVersion'], contains('{version}'));
        expect(arb['myAppName'], isNotEmpty);
      });

      test('어느 문구에도 고정 버전 숫자가 없다', () {
        arb.forEach((String key, dynamic value) {
          if (key.startsWith('@') || value is! String) return;
          expect(fixedVersion.hasMatch(value), isFalse, reason: '$key: $value');
        });
      });
    });
  }
}

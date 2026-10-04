/// 버전 문구에 고정 숫자가 없는지(#3047).
///
/// 예전에는 `myAppVersion` 이 `On-Care · 버전 1.0.0` 처럼 숫자를 품고 있어 빌드를
/// 올려도 화면은 그대로였다. 버전은 빌드에서 읽으므로 문구에는 자리표시만 둔다.
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
        expect(arb['updateRequiredVersions'], contains('{current}'));
        expect(arb['updateRequiredVersions'], contains('{min}'));
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

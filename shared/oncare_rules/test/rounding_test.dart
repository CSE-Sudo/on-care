import 'package:oncare_rules/oncare_rules.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final Map<String, Object?> vectors = loadVectors('rounding');

  group('pyRound — Python round 와 같다', () {
    for (final Object? row in vectors['py_round']! as List<Object?>) {
      final List<Object?> pair = row! as List<Object?>;
      final num x = pair[0]! as num;
      final int expected = pair[1]! as int;
      test('$x → $expected', () => expect(pyRound(x), expected));
    }

    test('정확히 절반은 짝수 쪽이다', () {
      expect(pyRound(0.5), 0);
      expect(pyRound(1.5), 2);
      expect(pyRound(2.5), 2);
      expect(pyRound(-2.5), -2);
    });

    test('정수는 그대로다', () {
      expect(pyRound(7), 7);
      expect(pyRound(-7), -7);
    });
  });

  group('minutesFromSeconds — 서버 max(1, round(s / 60)) 와 같다', () {
    for (final Object? row
        in vectors['minutes_from_seconds']! as List<Object?>) {
      final List<Object?> pair = row! as List<Object?>;
      final int seconds = pair[0]! as int;
      final int expected = pair[1]! as int;
      test('$seconds초 → $expected분', () {
        expect(minutesFromSeconds(seconds), expected);
      });
    }

    test('2분 30초는 2분, 4분 30초는 4분이다', () {
      expect(minutesFromSeconds(150), 2);
      expect(minutesFromSeconds(270), 4);
    });

    test('음수는 0분이다', () => expect(minutesFromSeconds(-5), 0));
  });
}

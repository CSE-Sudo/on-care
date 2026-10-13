/// 저장 시도 단위 멱등키 — 같은 본문이면 같은 키, 바뀌면 새 키. (#3095)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/network/retry_request_keys.dart';

void main() {
  int next = 0;
  RetryRequestKeys keys() => RetryRequestKeys('t', newKey: () => '${next++}');

  test('같은 본문은 같은 키, 다른 본문은 새 키', () {
    final RetryRequestKeys k = keys();
    final String a = k.keyFor(<String, Object?>{'n': 1});
    expect(k.keyFor(<String, Object?>{'n': 1}), a);
    final String b = k.keyFor(<String, Object?>{'n': 2});
    expect(b, isNot(a));
    // 고쳤다가 되돌려도 처음 키다 — 그 본문은 이미 서버에 있을 수 있다.
    expect(k.keyFor(<String, Object?>{'n': 1}), a);
  });

  test('성공 뒤(clear) 같은 본문은 새 시도라 새 키', () {
    final RetryRequestKeys k = keys();
    final String a = k.keyFor(<String, Object?>{'n': 1});
    k.clear();
    expect(k.keyFor(<String, Object?>{'n': 1}), isNot(a));
  });

  test('forget 은 그 본문의 키만 버린다', () {
    final RetryRequestKeys k = keys();
    final String a = k.keyFor(<String, Object?>{'n': 1});
    final String b = k.keyFor(<String, Object?>{'n': 2});
    k.forget(<String, Object?>{'n': 1});
    expect(k.keyFor(<String, Object?>{'n': 1}), isNot(a));
    expect(k.keyFor(<String, Object?>{'n': 2}), b);
  });

  test('키는 접두로 시작하고 서버 상한(64자) 안이다', () {
    final String key = RetryRequestKeys('exercise').keyFor(<Object?>[1]);
    expect(key, startsWith('exercise-'));
    expect(key.length, lessThanOrEqualTo(64));
  });

  group('유효 시간(#3363)', () {
    late DateTime now;
    RetryRequestKeys timed() => RetryRequestKeys(
      't',
      newKey: () => '${next++}',
      ttl: const Duration(minutes: 5),
      now: () => now,
    );

    setUp(() => now = DateTime(2026, 9, 17, 10));

    test('유효 시간 안의 같은 본문은 같은 키', () {
      final RetryRequestKeys k = timed();
      final String a = k.keyFor(<String, Object?>{'n': 1});
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(k.keyFor(<String, Object?>{'n': 1}), a);
    });

    test('유효 시간이 지나면 같은 본문도 새 시도라 새 키', () {
      final RetryRequestKeys k = timed();
      final String a = k.keyFor(<String, Object?>{'n': 1});
      now = now.add(const Duration(minutes: 5));
      final String b = k.keyFor(<String, Object?>{'n': 1});
      expect(b, isNot(a));
      // 새 키는 그때부터 다시 유효 시간을 센다.
      now = now.add(const Duration(minutes: 4));
      expect(k.keyFor(<String, Object?>{'n': 1}), b);
    });

    test('다시 쓴다고 유효 시간이 늘지 않는다 — 처음 만든 때부터 센다', () {
      final RetryRequestKeys k = timed();
      final String a = k.keyFor(<String, Object?>{'n': 1});
      now = now.add(const Duration(minutes: 3));
      expect(k.keyFor(<String, Object?>{'n': 1}), a);
      now = now.add(const Duration(minutes: 3));
      expect(k.keyFor(<String, Object?>{'n': 1}), isNot(a));
    });

    test('유효 시간을 주지 않으면 지금처럼 버릴 때까지 같은 키', () {
      final RetryRequestKeys k = RetryRequestKeys(
        't',
        newKey: () => '${next++}',
        now: () => now,
      );
      final String a = k.keyFor(<String, Object?>{'n': 1});
      now = now.add(const Duration(days: 1));
      expect(k.keyFor(<String, Object?>{'n': 1}), a);
    });
  });
}

/// 서비스 기준 시각이 기기 타임존과 무관하게 KST 인지 (#850).
///
/// 백엔드는 같은 것을 `tests/test_clock.py`(#557)로 지킨다. 그쪽은 프로세스
/// 타임존을 UTC 로 바꿔 놓고 확인하지만, Dart 에는 그런 수단이 없다. 대신
/// **UTC 와의 차이**를 본다 — 기기가 어느 타임존이든 UTC+9 여야 한다.
///
/// 두 앱(회원 앱·트레이너 웹)의 시계 테스트에서 순수 계산 부분을 모았다(#2907).
/// 앱 소스에 `DateTime.now()` 가 남지 않았는지 보는 검사는 각 앱의
/// `test/core/utils/clock_test.dart` 에 남는다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_core/clock.dart';

void main() {
  tearDown(() => debugNowKstOverride = null);

  test('nowKst 는 기기 타임존과 무관하게 UTC+9 다', () {
    debugNowKstOverride = null;
    final DateTime before = DateTime.now().toUtc();
    final DateTime kst = nowKst();
    final DateTime after = DateTime.now().toUtc();

    // 로컬로 만든 값이라 그대로 빼면 기기 오프셋이 섞인다. 필드를 UTC 로 다시
    // 읽어 순수한 벽시계 차이를 본다.
    final DateTime asUtc = DateTime.utc(
      kst.year,
      kst.month,
      kst.day,
      kst.hour,
      kst.minute,
      kst.second,
      kst.millisecond,
      kst.microsecond,
    );

    expect(asUtc.difference(before) >= kstOffset, isTrue);
    expect(asUtc.difference(after) <= kstOffset, isTrue);
  });

  test('todayKst 는 0시로 잘린 KST 날짜다', () {
    final DateTime today = todayKst();
    final DateTime now = nowKst();

    expect(today.hour, 0);
    expect(today.minute, 0);
    expect(today.second, 0);
    expect(<int>[today.year, today.month, today.day], <int>[
      now.year,
      now.month,
      now.day,
    ]);
  });

  group('toKst', () {
    test('UTC 23:00 은 다음 날 KST 08:00 이다', () {
      final DateTime k = toKst(DateTime.utc(2026, 8, 16, 23));

      expect(k.isUtc, isFalse);
      expect(<int>[k.year, k.month, k.day, k.hour], <int>[2026, 8, 17, 8]);
    });

    test('UTC 15:00 은 다음 날 KST 00:00 이다 — 경계', () {
      final DateTime k = toKst(DateTime.utc(2026, 8, 16, 15));

      expect(<int>[k.month, k.day, k.hour], <int>[8, 17, 0]);
    });

    test('UTC 14:59 은 같은 날 KST 23:59 다', () {
      final DateTime k = toKst(DateTime.utc(2026, 8, 16, 14, 59));

      expect(<int>[k.month, k.day, k.hour, k.minute], <int>[8, 16, 23, 59]);
    });

    test('월말·연말도 넘긴다', () {
      final DateTime k = toKst(DateTime.utc(2026, 12, 31, 20));

      expect(<int>[k.year, k.month, k.day, k.hour], <int>[2027, 1, 1, 5]);
    });

    test('오프셋이 붙은 문자열은 KST 벽시계로 바뀐다', () {
      final DateTime k = toKst(DateTime.parse('2026-08-16T23:30:00+00:00'));

      expect(<int>[k.month, k.day, k.hour, k.minute], <int>[8, 17, 8, 30]);
    });

    test('+09:00 문자열은 적힌 벽시계 그대로다', () {
      final DateTime k = toKst(DateTime.parse('2026-08-17T07:15:00+09:00'));

      expect(<int>[k.month, k.day, k.hour, k.minute], <int>[8, 17, 7, 15]);
    });

    test('오프셋 없는 문자열은 이미 KST 벽시계라 그대로 둔다', () {
      final DateTime raw = DateTime.parse('2026-08-17T07:15:00');
      final DateTime k = toKst(raw);

      expect(k, raw);
      expect(<int>[k.day, k.hour], <int>[17, 7]);
    });

    test('nowKst 로 만든 값은 두 번 바꾸지 않는다', () {
      final DateTime now = nowKst();

      expect(toKst(now), now);
    });
  });

  // ── KST 벽시계 변환 (#2751) ─────────────────────────────────────────────
  //
  // 서버 시각(UTC 순간)을 `toLocal()` 로 읽으면 기기 시간대에 매인다. CI 는 UTC
  // 라서, 아래 경계가 `toLocal()` 이었다면 전날로 떨어진다.

  group('toKst · kstDateOf', () {
    test('UTC 23:30 은 KST 다음 날 08:30 이다', () {
      final DateTime kst = toKst(DateTime.utc(2026, 9, 14, 23, 30));

      expect(kst.isUtc, isFalse);
      expect(
        <int>[kst.year, kst.month, kst.day, kst.hour, kst.minute],
        <int>[2026, 9, 15, 8, 30],
      );
    });

    test('UTC 15:00 은 KST 다음 날 00:00 — 자정 경계도 다음 날이다', () {
      expect(kstDateOf(DateTime.utc(2026, 9, 14, 15)), DateTime(2026, 9, 15));
      expect(
        kstDateOf(DateTime.utc(2026, 9, 14, 14, 59)),
        DateTime(2026, 9, 14),
      );
    });

    test('달·해가 넘어가는 경계도 KST 로 넘긴다', () {
      expect(kstDateOf(DateTime.utc(2026, 9, 30, 20)), DateTime(2026, 10));
      expect(kstDateOf(DateTime.utc(2026, 12, 31, 16)), DateTime(2027));
    });

    test('초 아래 자리도 그대로 옮긴다', () {
      final DateTime kst = toKst(DateTime.utc(2026, 9, 14, 0, 0, 1, 2, 3));

      expect(
        <int>[kst.second, kst.millisecond, kst.microsecond],
        <int>[1, 2, 3],
      );
    });

    test('로컬 값은 이미 KST 벽시계라 그대로 둔다', () {
      final DateTime local = DateTime(2026, 9, 15, 8, 10);

      expect(toKst(local), local);
      expect(kstDateOf(local), DateTime(2026, 9, 15));
    });

    test('오프셋이 붙은 서버 문자열도 같은 KST 날짜로 읽는다', () {
      final DateTime fromUtc = DateTime.parse('2026-09-14T23:10:00+00:00');
      final DateTime fromKst = DateTime.parse('2026-09-15T08:10:00+09:00');

      expect(toKst(fromUtc), DateTime(2026, 9, 15, 8, 10));
      expect(toKst(fromKst), DateTime(2026, 9, 15, 8, 10));
    });
  });

  group('isSameKstDay', () {
    test('UTC 로는 같은 날이어도 KST 로 갈리면 다른 날이다', () {
      expect(
        isSameKstDay(
          DateTime.utc(2026, 9, 14, 14, 50),
          DateTime.utc(2026, 9, 14, 15, 10),
        ),
        isFalse,
      );
    });

    test('UTC 로는 날이 갈려도 KST 로 같은 날이면 같은 날이다', () {
      expect(
        isSameKstDay(
          DateTime.utc(2026, 9, 14, 15, 10),
          DateTime.utc(2026, 9, 15, 8),
        ),
        isTrue,
      );
    });

    test('서버 시각과 데모(로컬 KST) 시각을 함께 견줄 수 있다', () {
      expect(
        isSameKstDay(
          DateTime.utc(2026, 9, 14, 23, 30),
          DateTime(2026, 9, 15, 9),
        ),
        isTrue,
      );
    });
  });

  test('debugNowKstOverride 가 있으면 그 값을 지금으로 쓴다', () {
    debugNowKstOverride = () => DateTime(2026, 9, 14, 23, 30);

    expect(nowKst(), DateTime(2026, 9, 14, 23, 30));
    expect(todayKst(), DateTime(2026, 9, 14));
  });
}

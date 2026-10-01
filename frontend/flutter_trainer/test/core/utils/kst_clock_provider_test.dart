/// 분 단위 KST 시계와 그 위의 날짜 provider. (#2865)
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/kst_clock_provider.dart';

void main() {
  group('untilNextMinute', () {
    test('분 중간이면 다음 분 경계까지', () {
      expect(
        untilNextMinute(DateTime(2026, 8, 20, 13, 0, 45, 500)),
        const Duration(seconds: 14, milliseconds: 500),
      );
    });

    test('정확히 경계 위면 1분 뒤', () {
      expect(
        untilNextMinute(DateTime(2026, 8, 20, 13)),
        const Duration(minutes: 1),
      );
    });

    test('자정 직전에도 다음 분(자정)까지만 기다린다', () {
      expect(
        untilNextMinute(DateTime(2026, 8, 20, 23, 59, 50)),
        const Duration(seconds: 10),
      );
    });
  });

  group('kstMinuteTicks', () {
    test('구독하자마자 지금을 한 번 낸다', () async {
      final DateTime fixed = DateTime(2026, 8, 20, 13, 0, 30);
      final DateTime first = await kstMinuteTicks(now: () => fixed).first;
      expect(first, fixed);
    });

    test('분 경계를 지나면 다시 낸다', () async {
      // 경계 직전으로 두어 실제 시간으로도 짧게 끝난다.
      DateTime current = DateTime(2026, 8, 20, 13, 0, 59, 980);
      final List<DateTime> ticks = <DateTime>[];
      final StreamSubscription<DateTime> sub = kstMinuteTicks(
        now: () => current,
      ).listen(ticks.add);
      addTearDown(sub.cancel);
      // 첫 값은 구독 직후가 아니라 다음 마이크로태스크에 도착한다.
      await Future<void>.delayed(Duration.zero);

      expect(ticks, hasLength(1));
      current = DateTime(2026, 8, 20, 13, 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(ticks.length, greaterThanOrEqualTo(2));
      expect(ticks[1], DateTime(2026, 8, 20, 13, 1));
    });

    test('구독을 끊으면 더 내지 않는다', () async {
      DateTime current = DateTime(2026, 8, 20, 13, 0, 59, 980);
      final List<DateTime> ticks = <DateTime>[];
      final StreamSubscription<DateTime> sub = kstMinuteTicks(
        now: () => current,
      ).listen(ticks.add);
      await Future<void>.delayed(Duration.zero);
      expect(ticks, hasLength(1));
      await sub.cancel();
      current = DateTime(2026, 8, 20, 13, 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(ticks, hasLength(1));
    });
  });

  group('kstTodayProvider', () {
    late StreamController<DateTime> clock;
    late ProviderContainer container;

    setUp(() {
      clock = StreamController<DateTime>.broadcast();
      container = ProviderContainer(
        overrides: <Override>[
          kstClockProvider.overrideWith((ref) => clock.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(clock.close);
    });

    test('같은 날 안에서는 분이 지나도 알리지 않는다', () async {
      final List<String> seen = <String>[];
      container.listen<String>(
        kstTodayProvider,
        (_, String next) => seen.add(next),
        fireImmediately: true,
      );

      clock.add(DateTime(2026, 8, 20, 23, 58));
      await Future<void>.delayed(Duration.zero);
      clock.add(DateTime(2026, 8, 20, 23, 59));
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, '2026-08-20');
      expect(seen.where((String d) => d == '2026-08-20').length, lessThan(3));
    });

    test('자정을 넘기면 새 날짜를 알린다', () async {
      final List<String> seen = <String>[];
      container.listen<String>(
        kstTodayProvider,
        (_, String next) => seen.add(next),
        fireImmediately: true,
      );

      clock.add(DateTime(2026, 8, 20, 23, 59));
      await Future<void>.delayed(Duration.zero);
      clock.add(DateTime(2026, 8, 21));
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, '2026-08-21');
      expect(container.read(kstNowProvider), DateTime(2026, 8, 21));
    });
  });
}

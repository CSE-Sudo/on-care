/// 날짜(KST)가 바뀐 계기에만 기록 그래프·보호권·주간 챌린지를 비운다. (#2852)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/router/day_change_refresh.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';

void main() {
  late DateTime today;
  late List<ProviderOrFamily> invalidated;

  setUp(() {
    today = DateTime(2026, 8, 20);
    invalidated = <ProviderOrFamily>[];
  });

  DayChangeRefresher refresher() => DayChangeRefresher(today: () => today);

  test('대상은 기록 그래프·보호권·주간 챌린지다', () {
    expect(kDayChangeRefreshTargets, <ProviderOrFamily>[
      activityCalendarProvider,
      myStreakShieldsProvider,
      weeklyChallengeProvider,
    ]);
  });

  test('같은 날 안의 복귀에서는 비우지 않는다', () {
    final DayChangeRefresher r = refresher();

    expect(r.refreshIfDayChanged(invalidated.add), isFalse);
    expect(r.refreshIfDayChanged(invalidated.add), isFalse);

    expect(invalidated, isEmpty);
  });

  test('자정을 넘기면 대상을 한 번 비운다', () {
    final DayChangeRefresher r = refresher();
    today = DateTime(2026, 8, 21);

    expect(r.refreshIfDayChanged(invalidated.add), isTrue);
    expect(invalidated, kDayChangeRefreshTargets);

    // 같은 새 날 안에서 다시 복귀하면 또 비우지 않는다.
    invalidated.clear();
    expect(r.refreshIfDayChanged(invalidated.add), isFalse);
    expect(invalidated, isEmpty);
  });

  test('시각만 다르고 날짜가 같으면 같은 날이다', () {
    // 시계가 0시로 자르지 않은 값을 줘도 날짜로만 비교한다.
    today = DateTime(2026, 8, 20, 0, 5);
    final DayChangeRefresher r = refresher();
    today = DateTime(2026, 8, 20, 23, 55);

    expect(r.refreshIfDayChanged(invalidated.add), isFalse);
  });

  test('여러 날을 건너뛰어도 한 번만 비운다', () {
    final DayChangeRefresher r = refresher();
    today = DateTime(2026, 8, 25);

    expect(r.refreshIfDayChanged(invalidated.add), isTrue);
    expect(invalidated, hasLength(kDayChangeRefreshTargets.length));
  });

  test('달·해가 바뀌는 자정도 날이 바뀐 것이다', () {
    today = DateTime(2026, 12, 31);
    final DayChangeRefresher r = refresher();
    today = DateTime(2027);

    expect(r.refreshIfDayChanged(invalidated.add), isTrue);
  });
}

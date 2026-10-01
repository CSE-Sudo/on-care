/// 앱 복귀·홈 재진입 때 비우는 목록과 프로필 조용한 갱신. (#2842)
///
/// 목록이 셸의 두 자리에 흩어져 있을 때 한쪽에서 빠지는 일이 반복됐다
/// (#1938, #2625). 이 테스트는 목록에 무엇이 들어 있어야 하는지를 못 박는다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/router/member_refresh_targets.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/shared/services/record_span_provider.dart';

/// 서버의 프로필을 흉내 낸다 — [current] 를 바꾸면 다음 조회가 새 값을 받는다.
class _ServerProfile extends Fake implements AccountRepository {
  _ServerProfile(this.current);

  UserProfile current;
  bool fail = false;
  int loads = 0;

  @override
  Future<UserProfile> fetchProfile() async {
    loads++;
    if (fail) throw Exception('offline');
    return current;
  }
}

UserProfile _profile({required int proteinG}) => UserProfile(
  id: 'u1',
  name: '김민수',
  email: 'member@example.test',
  dailyProteinG: proteinG,
);

void main() {
  // KST 오늘을 값으로 넘긴다 — 목록이 시계를 직접 읽지 않는다.
  final DateTime today = DateTime(2026, 8, 20);

  group('kHomeReentryRefreshTargets', () {
    test('홈 요약과 같은 카드의 목표·담당 연결을 함께 비운다', () {
      expect(
        kHomeReentryRefreshTargets,
        containsAll(<ProviderOrFamily>[
          dashboardSummaryProvider,
          dietRecommendationsProvider,
          coachSessionsProvider,
          memberCoachProvider,
        ]),
      );
    });

    test('프로필은 비우지 않는다 — 조용한 갱신으로 바꾼다', () {
      // invalidate 뒤 조회가 실패하면 MY 폼이 오류 안내로 바뀐다.
      expect(kHomeReentryRefreshTargets, isNot(contains(profileProvider)));
    });
  });

  group('memberResumeRefreshTargets', () {
    test('홈 재진입 목록을 모두 포함한다', () {
      expect(
        memberResumeRefreshTargets(today),
        containsAll(kHomeReentryRefreshTargets),
      );
    });

    test('식단 탭 오늘 기록과 그 날짜 칸을 비운다', () {
      final List<ProviderOrFamily> targets = memberResumeRefreshTargets(today);
      expect(targets, contains(dietTodayProvider));
      expect(targets, contains(dietByDateProvider(today)));
    });

    test('앞선 보완(#1938·#2625·#2161)의 대상이 그대로 남아 있다', () {
      expect(
        memberResumeRefreshTargets(today),
        containsAll(<ProviderOrFamily>[
          dietRecommendationsProvider,
          dietPeriodProvider,
          recordSpanProvider,
          exerciseWeekProvider,
          coachRoutinesProvider,
          coachRoutinesOnDayProvider,
          coachSessionsProvider,
        ]),
      );
    });

    test('담당 코치를 비운다', () {
      expect(memberResumeRefreshTargets(today), contains(memberCoachProvider));
    });

    test('같은 대상을 두 번 담지 않는다', () {
      final List<ProviderOrFamily> targets = memberResumeRefreshTargets(today);
      expect(targets.toSet().length, targets.length);
    });

    test('넘긴 날의 칸을 비운다 — 다른 날 칸은 아니다', () {
      final List<ProviderOrFamily> targets = memberResumeRefreshTargets(today);
      expect(
        targets,
        isNot(contains(dietByDateProvider(DateTime(2026, 8, 19)))),
      );
    });
  });

  group('refreshProfileQuietly', () {
    late _ServerProfile server;
    late ProviderContainer container;

    setUp(() {
      server = _ServerProfile(_profile(proteinG: 137));
      container = ProviderContainer(
        overrides: <Override>[
          accountRepositoryProvider.overrideWithValue(server),
        ],
      );
      addTearDown(container.dispose);
    });

    test('서버가 바꾼 목표를 받아 공유한다', () async {
      expect((await container.read(profileProvider.future)).dailyProteinG, 137);

      server.current = _profile(proteinG: 150);
      await refreshProfileQuietly(container.read(profileProvider.notifier));

      final AsyncValue<UserProfile> state = container.read(profileProvider);
      expect(state, isA<AsyncData<UserProfile>>());
      expect(state.value!.dailyProteinG, 150);
    });

    test('실패하면 들고 있던 값을 그대로 두고 오류 상태가 되지 않는다', () async {
      await container.read(profileProvider.future);

      server.fail = true;
      await refreshProfileQuietly(container.read(profileProvider.notifier));

      final AsyncValue<UserProfile> state = container.read(profileProvider);
      expect(state.hasError, isFalse);
      expect(state, isA<AsyncData<UserProfile>>());
      expect(state.value!.dailyProteinG, 137);
    });

    test('실패를 던지지 않는다 — 셸이 기다리지 않고 부른다', () async {
      await container.read(profileProvider.future);
      server.fail = true;

      await expectLater(
        refreshProfileQuietly(container.read(profileProvider.notifier)),
        completes,
      );
    });

    test('첫 조회가 실패한 뒤 다음 갱신이 성공하면 값이 채워진다', () async {
      server.fail = true;
      await expectLater(
        container.read(profileProvider.future),
        throwsA(isA<Exception>()),
      );

      server.fail = false;
      await refreshProfileQuietly(container.read(profileProvider.notifier));

      expect(container.read(profileProvider).value!.dailyProteinG, 137);
    });

    test('갱신마다 서버를 한 번 더 읽는다', () async {
      await container.read(profileProvider.future);
      final int before = server.loads;

      await refreshProfileQuietly(container.read(profileProvider.notifier));

      expect(server.loads, before + 1);
    });
  });
}

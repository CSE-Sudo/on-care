/// 앱 복귀·홈 재진입 때 홈이 같은 시점의 목표·연결을 보여 준다. (#2842)
///
/// 트레이너가 웹에서 회원의 단백질 목표를 바꿔도, 회원 앱은 다시 켜기 전까지
/// 옛 목표를 들고 있었다 — 칼로리 목표(서버 요약)는 새 값인데 같은 카드의 탄단지
/// 목표(프로필)는 옛 값이었다. 셸 전체를 세워 앱 복귀와 홈 재진입에서 프로필과
/// 담당 코치가 다시 읽히는지, 그 사이 목표가 기본값으로 깜빡이지 않는지 본다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../helpers/demo_exercise.dart';
import '../helpers/fake_dashboard_repository.dart';
import '../helpers/fake_diet_repository.dart';
import '../helpers/fake_notification_repository.dart';
import '../helpers/fixed_clock.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

UserProfile _profile({required int proteinG}) => UserProfile(
  id: 'u1',
  name: '김민수',
  email: 'member@example.test',
  dailyProteinG: proteinG,
);

/// 서버의 프로필. [current] 를 바꾸는 것이 "트레이너가 웹에서 목표를 바꿨다" 다.
/// [gate] 를 걸면 다음 조회가 그것이 풀릴 때까지 돌아오지 않는다.
class _ServerProfile extends Fake implements AccountRepository {
  _ServerProfile(this.current);

  UserProfile current;
  bool fail = false;
  Completer<void>? gate;
  int loads = 0;

  @override
  Future<UserProfile> fetchProfile() async {
    loads++;
    final Completer<void>? waiting = gate;
    if (waiting != null) await waiting.future;
    if (fail) throw Exception('offline');
    return current;
  }
}

/// 담당 코치 조회 횟수를 센다. 나머지는 데모 그대로다.
class _CountingCoach extends MockMemberCoachRepository {
  int coachLoads = 0;

  @override
  Future<MemberCoach?> fetchCoach() {
    coachLoads++;
    return super.fetchCoach();
  }
}

/// 식단 오늘 기록 조회 횟수를 센다 — "다른 기기에서 적은 끼니" 가 보이려면
/// 복귀 때 다시 읽어야 한다.
class _CountingDiet extends FakeDietRepository {
  int todayLoads = 0;

  @override
  Future<DietDay> fetchToday() {
    todayLoads++;
    return super.fetchToday();
  }
}

void main() {
  late GoRouter router;
  late _ServerProfile server;
  late _CountingCoach coach;
  late _CountingDiet diet;

  Future<void> pumpShell(
    WidgetTester tester, {
    String location = AppRoutes.dashboard,
  }) async {
    useFixedKstDate();
    final AppDatabase exerciseDb = await seededDemoDatabase(tester);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(location);

    server = _ServerProfile(_profile(proteinG: 137));
    coach = _CountingCoach();
    diet = _CountingDiet();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          accountRepositoryProvider.overrideWithValue(server),
          dietRepositoryProvider.overrideWithValue(diet as DietRepository),
          ...demoExerciseOverrides(exerciseDb),
          dashboardRepositoryProvider.overrideWithValue(
            FakeDashboardRepository(diet) as DashboardRepository,
          ),
          memberCoachRepositoryProvider.overrideWithValue(coach),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  /// 홈 단백질 칸의 목표 표기("/137g").
  Finder proteinGoal(int grams) => find.text('/${grams}g');

  testWidgets('앱 복귀 뒤 홈 단백질 목표가 트레이너가 바꾼 값으로 바뀐다', (tester) async {
    await pumpShell(tester);
    expect(proteinGoal(137), findsOneWidget);

    server.current = _profile(proteinG: 150);
    await resume(tester);
    await tester.pumpAndSettle();

    expect(proteinGoal(150), findsOneWidget);
    expect(proteinGoal(137), findsNothing);
  });

  testWidgets('다시 읽는 동안 기본 목표로 떨어졌다 돌아오지 않는다', (tester) async {
    await pumpShell(tester);
    expect(proteinGoal(137), findsOneWidget);

    server
      ..current = _profile(proteinG: 150)
      ..gate = Completer<void>();
    await resume(tester);
    await tester.pump(const Duration(milliseconds: 50));

    // 응답을 기다리는 동안: 들고 있던 목표 그대로, 기본값(100g)은 없다.
    expect(proteinGoal(137), findsOneWidget);
    expect(proteinGoal(UserProfile.defaultDailyProteinG), findsNothing);

    server.gate!.complete();
    server.gate = null;
    await tester.pumpAndSettle();

    expect(proteinGoal(150), findsOneWidget);
  });

  testWidgets('복귀 때 프로필을 못 읽으면 들고 있던 목표를 그대로 보인다', (tester) async {
    await pumpShell(tester);

    server.fail = true;
    await resume(tester);
    await tester.pumpAndSettle();

    expect(proteinGoal(137), findsOneWidget);
    expect(proteinGoal(UserProfile.defaultDailyProteinG), findsNothing);
  });

  testWidgets('앱 복귀는 프로필·담당 코치·오늘 식단을 다시 읽는다', (tester) async {
    await pumpShell(tester);
    final int profileBefore = server.loads;
    final int coachBefore = coach.coachLoads;
    final int dietBefore = diet.todayLoads;

    await resume(tester);
    await tester.pumpAndSettle();

    expect(server.loads, greaterThan(profileBefore));
    expect(coach.coachLoads, greaterThan(coachBefore));
    expect(diet.todayLoads, greaterThan(dietBefore));
  });

  testWidgets('식단 탭에 있을 때 복귀해도 오늘 기록을 다시 읽는다', (tester) async {
    await pumpShell(tester, location: AppRoutes.diet);
    final int dietBefore = diet.todayLoads;

    await resume(tester);
    await tester.pumpAndSettle();

    expect(diet.todayLoads, greaterThan(dietBefore));
  });

  testWidgets('홈 탭 재진입은 프로필과 담당 코치를 다시 읽는다', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('식단').last);
    await tester.pumpAndSettle();
    final int profileBefore = server.loads;
    final int coachBefore = coach.coachLoads;

    server.current = _profile(proteinG: 162);
    await tester.tap(find.text('홈').last);
    await tester.pumpAndSettle();

    expect(server.loads, greaterThan(profileBefore));
    expect(coach.coachLoads, greaterThan(coachBefore));
    // 칼로리 목표(서버 요약)와 같은 시점의 탄단지 목표다.
    expect(proteinGoal(162), findsOneWidget);
  });

  testWidgets('백그라운드로 가기만 하면 다시 읽지 않는다', (tester) async {
    await pumpShell(tester);
    final int profileBefore = server.loads;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(server.loads, profileBefore);
  });
}

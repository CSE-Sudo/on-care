/// 앱을 켜 둔 채 자정을 넘기고 복귀하면 하단 탭 틀이 MY 기록 그래프를 새 날짜로
/// 다시 읽는다. 같은 날 안의 복귀에서는 다시 읽지 않는다. (#2852)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/main_shell.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../helpers/demo_exercise.dart';
import '../helpers/fake_dashboard_repository.dart';
import '../helpers/fake_diet_repository.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  late DateTime now;
  late int calendarCalls;
  late int shieldCalls;
  late DateTime? lastCalendarDay;

  setUp(() {
    now = DateTime(2026, 8, 20, 23, 50);
    debugNowKstOverride = () => now;
    addTearDown(() => debugNowKstOverride = null);
    calendarCalls = 0;
    shieldCalls = 0;
    lastCalendarDay = null;
  });

  Future<void> pumpShell(WidgetTester tester) async {
    final AppDatabase exerciseDb = await seededDemoDatabase(tester);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.dashboard);

    final FakeDietRepository diet = FakeDietRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          dietRepositoryProvider.overrideWithValue(diet as DietRepository),
          ...demoExerciseOverrides(exerciseDb),
          dashboardRepositoryProvider.overrideWithValue(
            FakeDashboardRepository(diet) as DashboardRepository,
          ),
          activityCalendarProvider.overrideWith((Ref ref) async {
            calendarCalls++;
            // 그래프는 "오늘" 로 끝난다 — 몇 일 기준으로 다시 읽혔는지 남긴다.
            lastCalendarDay = todayKst();
            return const ActivityCalendar(
              days: <ActivityDay>[],
              recordStreakDays: 0,
              color: GraphColorState.base,
            );
          }),
          myStreakShieldsProvider.overrideWith((Ref ref) async {
            shieldCalls++;
            return const StreakShields(held: 0, maxHeld: 2, cost: 100);
          }),
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

    // MY 화면이 그래프와 보호권을 보고 있는 상태 — 비우면 바로 다시 읽힌다.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(MainShell)),
    );
    container.listen(activityCalendarProvider, (_, _) {});
    container.listen(myStreakShieldsProvider, (_, _) {});
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('같은 날 안의 복귀에서는 그래프를 다시 읽지 않는다', (WidgetTester tester) async {
    await pumpShell(tester);
    final int calendar = calendarCalls;
    final int shields = shieldCalls;

    now = DateTime(2026, 8, 20, 23, 55);
    await resume(tester);

    expect(calendarCalls, calendar);
    expect(shieldCalls, shields);
  });

  testWidgets('자정을 넘겨 복귀하면 그래프·보호권을 새 날짜로 다시 읽는다', (WidgetTester tester) async {
    await pumpShell(tester);
    final int calendar = calendarCalls;
    final int shields = shieldCalls;

    now = DateTime(2026, 8, 21, 0, 10);
    await resume(tester);

    expect(calendarCalls, calendar + 1);
    expect(shieldCalls, shields + 1);
    expect(lastCalendarDay, DateTime(2026, 8, 21));

    // 같은 새 날 안의 다음 복귀는 다시 읽지 않는다.
    await resume(tester);
    expect(calendarCalls, calendar + 1);
  });
}

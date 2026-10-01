/// 운동 탭으로 돌아오면 AI 맞춤 조언을 다시 받는다. (#2631)
///
/// 식단 탭은 탭 재진입 때 조언을 다시 받는다(#2078). 운동 탭은 이번 주 기록만
/// 다시 읽고 조언은 그대로 두어, 하단 `+` 로 운동을 적고 돌아와도 조언은 적기
/// 전 기록을 말했다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/data/repositories/dio_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../helpers/demo_exercise.dart';
import '../helpers/fake_dashboard_repository.dart';
import '../helpers/fake_diet_repository.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 조언을 몇 번 받았는지 센다. 기록은 앱의 데모와 같은 로컬 목업 API(시드한
/// 메모리 drift)가 든다(#2724).
class _CountingExerciseRepository extends DioExerciseRepository {
  _CountingExerciseRepository(super.dio);

  int adviceCalls = 0;

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) {
    adviceCalls++;
    return super.fetchAdvice(period);
  }
}

void main() {
  late _CountingExerciseRepository exercise;
  late GoRouter router;

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    exercise = _CountingExerciseRepository(
      demoExerciseDio(await seededDemoDatabase(tester)),
    );
    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.dashboard);

    final FakeDietRepository diet = FakeDietRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          dietRepositoryProvider.overrideWithValue(diet as DietRepository),
          exerciseRepositoryProvider.overrideWithValue(
            exercise as ExerciseRepository,
          ),
          dashboardRepositoryProvider.overrideWithValue(
            FakeDashboardRepository(diet) as DashboardRepository,
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

  Future<void> goTo(WidgetTester tester, String location) async {
    router.go(location);
    await tester.pumpAndSettle();
    // 목업 저장소는 실제 지연을 두고 답한다 — 남은 타이머를 흘려보낸다.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('다른 탭에 다녀오면 운동 탭 조언을 다시 받는다', (WidgetTester tester) async {
    await pumpShell(tester);
    await goTo(tester, AppRoutes.exercise);
    final int afterFirstVisit = exercise.adviceCalls;
    expect(afterFirstVisit, greaterThan(0), reason: '운동 탭이 조언을 보여 준다');

    await goTo(tester, AppRoutes.dashboard);
    await goTo(tester, AppRoutes.exercise);

    expect(exercise.adviceCalls, greaterThan(afterFirstVisit));
  });
}

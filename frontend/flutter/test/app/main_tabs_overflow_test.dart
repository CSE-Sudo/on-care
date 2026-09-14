/// 앱 기본 글씨 배율에서 주요 화면이 넘치지 않는지 (#995).
///
/// 전역 배율을 올린 뒤 로그인 화면의 소셜 버튼과 헬스장 탭의 트레이너 채팅
/// 버튼이 가로로 넘쳤다. 위젯 테스트는 화면을 하나씩 띄우느라 이 둘을 지나쳤고,
/// E2E 는 실 API 가 붙어야 돌아서 늦게 알았다. 로그인부터 탭을 한 바퀴 도는
/// 얕은 검사를 두어 같은 종류의 회귀를 여기서 잡는다.
///
/// **영어도 함께 돈다.** 라벨이 훨씬 길어("Continue with Kakao" vs
/// "카카오로 시작하기") 한국어만으로는 넘치는 걸 못 본다 — 실제로 이번에도
/// 영어에서 먼저 터졌다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/app.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/dashboard/data/repositories/mock_dashboard_repository.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/shared/services/locale_provider.dart';

import '../helpers/fake_diet_repository.dart';

void main() {
  for (final Locale locale in const <Locale>[Locale('ko'), Locale('en')]) {
    testWidgets('로그인부터 주요 탭까지 넘치지 않는다 — ${locale.languageCode}', (
      WidgetTester tester,
    ) async {
      final List<String> overflows = <String>[];
      final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains('overflowed')) {
          overflows.add(details.toString().split('\n').take(8).join('\n'));
        } else {
          previous?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = previous);

      // 폰이 기준이다. 높이는 넉넉히 둔다 — 짧은 화면에서는 아래쪽 카드가
      // 아예 그려지지 않아 검사 대상이 사라진다.
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const AppConfig config = AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: true,
        // 데모 진입은 기본 빌드에서 감춰 뒀다 — 이 테스트는 그 경로로 화면에
        // 들어가므로 플래그를 켜고 편다. (#1526)
        showDemoEntry: true,
      );
      final FakeDietRepository diet = FakeDietRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(config),
            appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
            dietRepositoryProvider.overrideWithValue(diet as DietRepository),
            exerciseRepositoryProvider.overrideWithValue(
              MockExerciseRepository() as ExerciseRepository,
            ),
            dashboardRepositoryProvider.overrideWithValue(
              MockDashboardRepository(diet) as DashboardRepository,
            ),
            sessionFeatureResetOverride(),
            localeProvider.overrideWith((Ref ref) => locale),
          ],
          child: const OncareApp(),
        ),
      );
      await tester.pumpAndSettle();

      final Finder demoButton = find.byKey(const Key('demoEnterButton'));
      await tester.ensureVisible(demoButton);
      await tester.pumpAndSettle();
      await tester.tap(demoButton);
      await tester.pumpAndSettle();

      Future<void> open(Finder finder) async {
        if (finder.evaluate().isEmpty) return;
        await tester.tap(finder.first);
        await tester.pumpAndSettle();
      }

      await open(find.byKey(const ValueKey<String>('nav-diet')));
      await open(find.byKey(const ValueKey<String>('nav-exercise')));
      await open(find.byKey(const ValueKey<String>('exercise-subtab-1')));
      await open(find.byKey(const ValueKey<String>('nav-my')));

      expect(overflows, isEmpty, reason: overflows.join('\n──────\n'));
    });
  }
}

/// 태블릿 가로 화면에서 주요 화면이 넘치지 않는지 (#3050).
///
/// 휴대폰은 세로로 고정했지만 태블릿은 모든 방향을 그대로 둔다(iPad 멀티태스킹
/// 조건). 화면 폭은 휴대폰 폭으로 제한해 가운데 정렬하므로, 높이가 짧은 가로
/// 태블릿(1194×834)에서도 로그인부터 주요 탭까지 넘침 오류가 없어야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/app.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/shared/services/locale_provider.dart';

import '../helpers/demo_exercise.dart';
import '../helpers/fake_dashboard_repository.dart';
import '../helpers/fake_diet_repository.dart';

void main() {
  for (final Locale locale in const <Locale>[Locale('ko'), Locale('en')]) {
    testWidgets('태블릿 가로에서 로그인부터 주요 탭까지 넘치지 않는다 — ${locale.languageCode}', (
      WidgetTester tester,
    ) async {
      final AppDatabase exerciseDb = await seededDemoDatabase(tester);
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

      // 11인치 iPad 가로 크기.
      tester.view.physicalSize = const Size(1194, 834);
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
      // 저장된 세션이 없다고 답해 준다 — 없으면 복구가 끝나지 않아 시작
      // 화면(#1944)에 머문다.
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final FakeDietRepository diet = FakeDietRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(config),
            appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
            dietRepositoryProvider.overrideWithValue(diet as DietRepository),
            // 운동은 앱의 데모와 같은 경로(로컬 목업 API + drift)로 돈다(#2724).
            ...demoExerciseOverrides(exerciseDb),
            dashboardRepositoryProvider.overrideWithValue(
              FakeDashboardRepository(diet) as DashboardRepository,
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

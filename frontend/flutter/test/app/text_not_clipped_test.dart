/// 글씨를 키운 뒤 문구가 잘리던 자리들 (#1004).
///
/// 세로로 넘치는 것은 예외로 드러나지만 **가로로 줄임표가 되거나 상자에 눌려
/// 잘리는 것은 조용하다.** 서비스 이름과 그래프 목표 라벨은 잘리면 그 자리가
/// 무엇인지가 사라지는 곳이라, 여기서 못 박아 둔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

import '../helpers/fake_diet_repository.dart';

bool _isClipped(WidgetTester tester, String contains) {
  bool clipped = false;
  bool found = false;
  void visit(Element el) {
    final RenderObject? ro = el.renderObject;
    if (ro is RenderParagraph && ro.hasSize) {
      if (ro.text.toPlainText().contains(contains)) {
        found = true;
        if (ro.didExceedMaxLines ||
            ro.getMinIntrinsicHeight(ro.size.width) > ro.size.height + 0.5) {
          clipped = true;
        }
      }
    }
    el.visitChildren(visit);
  }

  visit(tester.binding.rootElement!);
  expect(found, isTrue, reason: '"$contains" 를 그리는 문단을 못 찾았다');
  return clipped;
}

void main() {
  testWidgets('헤더의 서비스 이름과 그래프 목표 라벨이 잘리지 않는다', (WidgetTester tester) async {
    // 폰이 기준이다.
    tester.view.physicalSize = const Size(390, 1600);
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
          exerciseRepositoryProvider.overrideWithValue(
            MockExerciseRepository() as ExerciseRepository,
          ),
          dashboardRepositoryProvider.overrideWithValue(
            MockDashboardRepository(diet) as DashboardRepository,
          ),
          sessionFeatureResetOverride(),
        ],
        child: const OncareApp(),
      ),
    );
    await tester.pumpAndSettle();
    final Finder demo = find.byKey(const Key('demoEnterButton'));
    await tester.ensureVisible(demo);
    await tester.pumpAndSettle();
    await tester.tap(demo);
    await tester.pumpAndSettle();

    expect(_isClipped(tester, 'On - Care'), isFalse);
    // 주간 추이 그래프의 목표 라벨 — `목표` 아래 줄(값)이 상자에 눌려 잘렸다.
    expect(_isClipped(tester, 'Goal'), isFalse);
  });
}

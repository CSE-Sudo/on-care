import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/app.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/dashboard/data/repositories/mock_dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/shared/services/locale_provider.dart';

import '../../helpers/fake_diet_repository.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    // Five stacked dashboard cards — give the surface enough height so
    // the bottom ones stay attached (ListView lazy-builds otherwise).
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const config = AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'https://dev.api.test',
      useMockApi: true,
      // 데모 진입은 기본 빌드에서 감춰 뒀다 — 이 테스트는 그 경로로 화면에
      // 들어가므로 플래그를 켜고 편다. (#1526)
      showDemoEntry: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          localeProvider.overrideWith((ref) => const Locale('ko')),
          dashboardRepositoryProvider.overrideWithValue(
            MockDashboardRepository(FakeDietRepository()),
          ),
        ],
        child: const OncareApp(),
      ),
    );
    await tester.pumpAndSettle();
    // The app now boots into the sign-in screen; enter demo mode to reach
    // the dashboard. Find by Key (locale-independent) and scroll it into view
    // first (it sits below the fold on the compact test surface).
    final demoButton = find.byKey(const Key('demoEnterButton'));
    await tester.ensureVisible(demoButton);
    await tester.pumpAndSettle();
    await tester.tap(demoButton);
    await tester.pumpAndSettle();
  }

  testWidgets('Dashboard renders the current localized sections', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('식단 · 영양'), findsOneWidget);
    // 수치는 식단 하루치에서 온다 — 칼로리 1,067kcal (저녁 제외, #548).
    expect(find.text('1,067'), findsWidgets);
    // 탄단지는 홈 카드에서 뺐다 (#1117).
    expect(find.text('120g'), findsNothing);
    // 오늘의 일정 카드는 화면에서 내려 뒀다 (#1055).
    expect(find.text('오늘의 일정'), findsNothing);
  });

  testWidgets('홈 헤더에 캘린더 버튼과 AI 분석 필이 없다 (#1055)', (WidgetTester tester) async {
    await pumpApp(tester);

    // 캘린더는 쓰지 않아 내려 뒀다 — 아이콘만 남으면 눌러도 아무 일이 없다.
    expect(find.byIcon(AppIcons.calendar), findsNothing);
    // 홈 요약은 대부분 AI 가 만든 것이라 필이 카드를 갈라 주지 못했다.
    expect(find.textContaining('AI 분석'), findsNothing);
    // 로고는 서비스 로고 그대로다 — 하트 아이콘은 자리를 지키던 임시값이었다.
    expect(find.byIcon(AppIcons.favorite), findsNothing);
  });
}

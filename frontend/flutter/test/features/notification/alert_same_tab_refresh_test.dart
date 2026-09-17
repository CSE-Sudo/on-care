/// 같은 탭에 머무는 알림도 화면을 다시 읽는다. (#1939)
///
/// 셸의 브랜치 전환 갱신은 `_lastIndex == nextIndex` 면 곧바로 반환한다. 홈에서
/// 홈 알림을 누르는 것이 가장 흔한 경로인데(기본 알림이 전부 이 목적지다) 그때
/// 아무도 다시 읽지 않으면, 알림이 말한 변화가 홈에 없는 채로 돌아온다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/presentation/alert_navigation.dart';

const DashboardSummary _summary = DashboardSummary(
  indicators: <HealthIndicator>[
    HealthIndicator(label: '칼로리', current: 0, max: 2000, unit: 'kcal'),
  ],
  macros: DietMacros.zero(),
  dietEntries: 0,
  exerciseMinutes: 0,
  weekScore: 0,
  weekScoreDelta: 0,
  sodiumWarning: null,
);

const DietDay _emptyDay = DietDay(
  entries: <DietEntry>[],
  totalCalories: 0,
  macros: DietMacros.zero(),
  totalSodiumMg: 0,
  totalSugarG: 0,
  aiCoachMessage: '',
);

AlertItem _alert(AlertTarget target) => AlertItem(
  id: 'a1',
  title: '알림',
  body: '내용',
  createdAt: '2026-09-17T09:00:00Z',
  timeAgo: '방금',
  category: AlertCategory.reminder,
  action: AlertAction(label: '보기', target: target),
);

void main() {
  late BuildContext ctx;
  late WidgetRef wref;

  /// 각 provider 가 몇 번 조회됐는지 센다 — 무효화가 정말 다시 읽는지 본다.
  Future<({int Function() summary, int Function() diet})> pump(
    WidgetTester tester,
  ) async {
    int summaryLoads = 0;
    int dietLoads = 0;
    final GoRouter router = GoRouter(
      initialLocation: '/home',
      routes: <RouteBase>[
        GoRoute(
          path: '/home',
          builder: (_, _) => Consumer(
            builder: (BuildContext c, WidgetRef r, _) {
              ctx = c;
              wref = r;
              // 듣는 사람이 있어야 무효화가 다시 읽기로 이어진다.
              r
                ..watch(dashboardSummaryProvider)
                ..watch(dietTodayProvider)
                ..watch(dietByDateProvider(nowKst()));
              return const Text('home');
            },
          ),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (_, _) => const Text('대시보드'),
        ),
        GoRoute(path: AppRoutes.diet, builder: (_, _) => const Text('식단')),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dashboardSummaryProvider.overrideWith((ref) async {
            summaryLoads++;
            return _summary;
          }),
          dietTodayProvider.overrideWith((ref) async {
            dietLoads++;
            return _emptyDay;
          }),
          dietByDateFamily.overrideWith((ref, date) async => _emptyDay),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return (summary: () => summaryLoads, diet: () => dietLoads);
  }

  testWidgets('홈 알림은 홈 요약을 다시 읽는다', (WidgetTester tester) async {
    final counts = await pump(tester);
    final int before = counts.summary();

    await openAlertTarget(ctx, wref, _alert(AlertTarget.dashboard));
    await tester.pumpAndSettle();

    expect(counts.summary(), greaterThan(before));
  });

  testWidgets('식단 알림은 그날 식단을 다시 읽는다', (WidgetTester tester) async {
    final counts = await pump(tester);
    final int before = counts.diet();

    await openAlertTarget(ctx, wref, _alert(AlertTarget.diet));
    await tester.pumpAndSettle();

    expect(counts.diet(), greaterThan(before));
  });
}

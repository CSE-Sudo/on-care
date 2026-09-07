import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays;
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 프로그램 탭의 운동 이행률. (#899, #1029)
///
/// 회원 목록 행의 이행률 막대·퍼센트는 #1029 에서 뺐다 — 이 목록은 회원을
/// 고르는 자리고, 이행률 비교는 `운동` 데이터 쪽(요일별 막대그래프)의 몫이다.
/// 그 그래프는 그대로 남아 있다.
void main() {
  Future<void> openCoaching(
    WidgetTester tester,
    List<TrainerClient> roster,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.coaching,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(roster),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// 요일별 이행률 그래프는 이제 `운동` 쪽에 있다(#1027) — 요약 카드가
  /// 사라지면서 운동 데이터끼리 모였다.
  Future<void> openWorkout(WidgetTester tester) async {
    final tabs = find.byKey(const ValueKey<String>('program-client-data-tabs'));
    expect(tabs, findsOneWidget);
    await tester.tap(find.descendant(of: tabs, matching: find.text('운동')));
    await tester.pumpAndSettle();
  }

  Finder rowOf(String id) =>
      find.byKey(ValueKey<String>('program-client-$id'));

  testWidgets('회원 목록 행에는 이행률 막대도 퍼센트도 없다 (#1029)', (tester) async {
    await openCoaching(tester, <TrainerClient>[
      makeClient(
        id: 'steady',
        name: '꾸준회원',
        weekCompletion: const <int>[90, 90, 90, 90, 90, 90, 90],
      ),
    ]);

    // 행 자체가 렌더됐는지 먼저 확인한다 — 아래 findsNothing 어서션들은
    // 행이 아예 없어도 그대로 통과해 버려서, 이 양성 확인이 없으면 위양성이
    // 된다.
    expect(rowOf('steady'), findsOneWidget);
    expect(
      find.descendant(of: rowOf('steady'), matching: find.byType(InlineBarValue)),
      findsNothing,
    );
    expect(
      find.descendant(of: rowOf('steady'), matching: find.text('90%')),
      findsNothing,
    );
    expect(
      find.descendant(of: rowOf('steady'), matching: find.text('운동 이행률')),
      findsNothing,
    );
  });

  testWidgets('운동 쪽에 요일별 이행률 막대그래프가 보인다', (tester) async {
    const week = <int>[80, 0, 90, 70, 60, 50, 40];
    await openCoaching(tester, <TrainerClient>[
      makeClient(id: 'week', name: '주간회원', weekCompletion: week),
    ]);
    await openWorkout(tester);

    final chart = tester.widget<BarSeriesChart>(
      find.byKey(const ValueKey<String>('program-week-completion-chart')),
    );
    expect(chart.values, week);
    expect(chart.maxValue, 100);
    expect(chart.valueSuffix, '%');
    // 아직 오지 않은 요일은 빈 트랙이다 — 0% 수행과 구분한다.
    expect(chart.pendingFromIndex, elapsedWeekdays(nowKst()));
    // 지난 날인데 기록이 없는 요일도 0% 가 아니다. 화요일(index 1)이 그렇다.
    final elapsed = elapsedWeekdays(nowKst());
    expect(chart.missingIndices.contains(1), elapsed > 1);
  });

  testWidgets('주간 계열이 없는 회원은 그래프 자리에 안내가 뜬다', (tester) async {
    await openCoaching(tester, <TrainerClient>[
      makeClient(id: 'short', name: '짧은계열', weekCompletion: const <int>[80]),
    ]);
    await openWorkout(tester);

    expect(
      find.byKey(const ValueKey<String>('program-week-completion-chart')),
      findsNothing,
    );
    expect(find.text('이번 주 운동 기록이 없어요'), findsWidgets);
  });
}

/// 데모 이력이 실제로 대시보드에 닿는가. (#1203)
///
/// 새 계정에서는 `할 일 진행률` 막대와 `지난 할 일` 이 둘 다 채워지고, 실제
/// 기록이 시작되면 그 자리를 내준다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/dashboard/data/demo_task_history.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/today_tasks_card.dart';

import '../../helpers/pump_app.dart';

Finder get _demoCarryOverRow => find.byKey(
  const ValueKey<String>(
    'dashboard-mission-${DemoTaskHistory.kDemoCarryOverKey}',
  ),
);

/// 채워진 막대의 수 — 퍼센트 라벨이 붙은 칸만 센다(기록 없는 날은 빈 문자열).
int _filledBars(WidgetTester tester) {
  int filled = 0;
  for (int i = 0; i < 7; i++) {
    final Finder label = find.byKey(ValueKey<String>('task-progress-percent-$i'));
    if (label.evaluate().isEmpty) continue;
    if (tester.widget<Text>(label).data!.isNotEmpty) filled++;
  }
  return filled;
}

void main() {
  Future<void> openDashboard(
    WidgetTester tester, {
    List<Override> extraOverrides = const <Override>[],
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.dashboard,
      extraOverrides: extraOverrides,
    );
  }

  testWidgets('새 계정도 지난 할 일 한 건과 채워진 막대를 본다', (WidgetTester tester) async {
    await openDashboard(tester);

    // 할 일 진행률 범례도 `지난 할 일` 이라(#2214) 카드 안에서만 찾는다.
    expect(
      find.descendant(
        of: find.byType(TodayTasksCard),
        matching: find.text('지난 할 일'),
      ),
      findsOneWidget,
    );
    // 카테고리 상자는 접힌 채로 시작한다 — 펼쳐야 항목이 보인다.
    await tester.tap(
      find.byKey(const ValueKey<String>('dashboard-category-toggle-지난 할 일')),
    );
    await settle(tester);
    expect(_demoCarryOverRow, findsOneWidget);
    // 펼친 상자는 `지난 할 일` 하나뿐이다. 그 안에 데모 항목 말고 다른 줄이
    // 없다는 것은, 오늘 새로 생긴 실제 항목이 이월로 흡수되지 않았다는
    // 뜻이다 — 예전 시도(#1147)가 바로 그 자리에서 어긋났다.
    expect(
      find.byWidgetPredicate((Widget widget) {
        final Key? key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('dashboard-mission-') &&
            !key.value.startsWith('dashboard-mission-dismiss-');
      }),
      findsOneWidget,
    );

    // 지난주는 이레 모두 지난 날이라 일곱 칸이 모두 채워진다 — 이번 주는
    // 오늘이 무슨 요일이냐에 따라 채워지는 칸 수가 달라진다.
    await tester.tap(find.byKey(const ValueKey<String>('task-progress-prev-week')));
    await settle(tester);
    expect(_filledBars(tester), 7);
  });

  testWidgets('실제 기록이 시작되면 데모는 물러난다', (WidgetTester tester) async {
    final DateTime now = nowKst();
    await openDashboard(
      tester,
      extraOverrides: <Override>[
        // 오늘부터 실제로 쓰기 시작한 계정 — 어제 요약도 데모가 아니다.
        demoTaskHistoryProvider.overrideWithValue(
          DemoTaskHistory(
            today: DateTime(now.year, now.month, now.day),
            firstSavedDate: ymd(
              now.subtract(const Duration(days: DemoTaskHistory.windowDays)),
            ),
          ),
        ),
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('dashboard-category-toggle-지난 할 일')),
    );
    await settle(tester);
    expect(_demoCarryOverRow, findsNothing);
    expect(_filledBars(tester), 0);
  });
}

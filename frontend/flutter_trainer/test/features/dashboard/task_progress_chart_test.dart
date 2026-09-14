import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/task_progress_chart.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  testWidgets('bar heights follow completion rates instead of task counts', (
    tester,
  ) async {
    const snapshots = <DailyTaskSnapshot?>[
      DailyTaskSnapshot(
        total: 10,
        completedToday: 1,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
      ),
      DailyTaskSnapshot(
        total: 4,
        completedToday: 2,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
      ),
      DailyTaskSnapshot(
        total: 10,
        completedToday: 5,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
      ),
      DailyTaskSnapshot(
        total: 6,
        completedToday: 4,
        completedCarriedOver: 2,
        pendingKeys: <String>{},
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: TaskProgressChart(
              snapshots: snapshots,
              dates: <DateTime>[
                DateTime(2026, 8, 24),
                DateTime(2026, 8, 25),
                DateTime(2026, 8, 26),
                DateTime(2026, 8, 27),
              ],
              labels: const <String>['월', '화', '수', '목'],
              todayIndex: 3,
            ),
          ),
        ),
      ),
    );

    final labelRects = <Rect>[
      for (var i = 0; i < snapshots.length; i++)
        tester.getRect(
          find.byKey(ValueKey<String>('task-progress-percent-$i')),
        ),
    ];
    final barRects = <Rect>[
      for (var i = 0; i < snapshots.length; i++)
        tester.getRect(find.byKey(ValueKey<String>('task-progress-bar-$i'))),
    ];

    for (var i = 0; i < snapshots.length; i++) {
      expect(labelRects[i].bottom, lessThanOrEqualTo(barRects[i].top));
    }
    expect(labelRects[1].top, lessThan(labelRects[0].top));
    expect(barRects[2].height, closeTo(barRects[1].height, 0.01));
    expect(barRects[3].height, greaterThan(barRects[2].height));
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('100%'), findsOneWidget);
  });
}

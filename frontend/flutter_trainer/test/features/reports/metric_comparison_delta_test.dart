import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/bar_line_chart.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/metric_comparison_section.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// `이번 주 vs 지난 주` 비교 상자의 차이 수치 자리. (#2186)
///
/// 차이가 상자 제목 줄 오른쪽 끝에 따로 있으면 어느 두 막대 사이의 차이인지
/// 눈으로 이어 붙여야 한다. 두 막대를 잇는 선 위에 그려져야 한다.
void main() {
  Future<void> openReports(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reports,
    );
    await tester.pumpAndSettle();
  }

  List<BarLineChart> comparisonCharts(WidgetTester tester) => tester
      .widgetList<BarLineChart>(
        find.descendant(
          of: find.byType(MetricComparisonSection),
          matching: find.byType(BarLineChart),
        ),
      )
      .toList();

  testWidgets('차이 수치는 제목 줄이 아니라 두 막대를 잇는 선 위에 그려진다', (tester) async {
    await openReports(tester);

    final List<BarLineChart> charts = comparisonCharts(tester);
    expect(charts, hasLength(2), reason: '운동·식단 상자');
    for (final chart in charts) {
      final BarLineDelta? delta = chart.delta;
      expect(delta, isNotNull, reason: chart.semanticsLabel);
      expect(delta!.text, matches(RegExp(r'^[+-]')));
      // 제목 줄에 글자로 따로 남아 있지 않다 — 그래프 캔버스가 그린다.
      expect(
        find.descendant(
          of: find.byType(MetricComparisonSection),
          matching: find.text(delta.text),
        ),
        findsNothing,
      );
      // 캔버스 글자는 시맨틱 트리에 남지 않으므로 그래프 문장이 차이를 말한다.
      expect(chart.semanticsLabel, endsWith('지난 주 대비 ${delta.text}'));
      // 두 상자가 나란히 서므로 차이가 없어도 자리를 비워 높이를 맞춘다.
      expect(chart.reserveDeltaSpace, isTrue);
    }
  });

  testWidgets('운동은 늘면 초록, 줄면 빨강이다', (tester) async {
    await openReports(tester);

    final BarLineChart exercise = comparisonCharts(
      tester,
    ).firstWhere((chart) => chart.semanticsLabel.startsWith('운동'));
    final double change = exercise.values[1]! - exercise.values[0]!;
    expect(
      exercise.delta!.color,
      change >= 0 ? OnCareColors.success : OnCareColors.danger,
    );
  });

  group('BarLineChart delta', () {
    Future<void> pumpChart(
      WidgetTester tester, {
      required List<double?> values,
      BarLineDelta? delta,
      bool reserve = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: BarLineChart(
                key: const ValueKey<String>('chart'),
                values: values,
                labels: const <String>['지난 주', '이번 주'],
                ceiling: 100,
                format: (v) => '${v.round()}분',
                semanticsLabel: '운동',
                height: 96,
                delta: delta,
                reserveDeltaSpace: reserve,
              ),
            ),
          ),
        ),
      );
    }

    double heightOf(WidgetTester tester) =>
        tester.getSize(find.byKey(const ValueKey<String>('chart'))).height;

    testWidgets('차이를 적으면 값 라벨 위 한 줄만큼 위쪽을 더 비운다', (tester) async {
      await pumpChart(tester, values: const <double?>[100, 100]);
      final double plain = heightOf(tester);

      // 두 막대가 꽉 차 선 가운데가 값 라벨 높이여도 그릴 자리가 있다.
      await pumpChart(
        tester,
        values: const <double?>[100, 100],
        delta: (text: '+0분', color: OnCareColors.textSecondary),
      );
      expect(tester.takeException(), isNull);
      expect(heightOf(tester), greaterThan(plain));

      // 차이가 없어도 자리를 비워 두면 같은 높이다.
      await pumpChart(
        tester,
        values: const <double?>[100, null],
        reserve: true,
      );
      expect(tester.takeException(), isNull);
      expect(heightOf(tester), greaterThan(plain));
    });
  });
}

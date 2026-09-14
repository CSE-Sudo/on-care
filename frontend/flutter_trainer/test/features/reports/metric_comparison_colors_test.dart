import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/bar_line_chart.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/metric_comparison_section.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/widgets/activity_charts.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// `이번 주 vs 지난 주` 운동 비교 그래프의 지표별 색. (#1424)
///
/// 지표를 바꿔도 그림이 늘 브랜드 색이면, 지금 무엇을 보고 있는지 알약을 다시
/// 읽어야 안다. 색 기준은 다른 운동 그래프(주간 운동 시간·이행률 막대)와 같은
/// 램프다 — 같은 값이 화면마다 다른 색이면 색이 뜻을 잃는다.
void main() {
  // 트레이너웹 브랜드의 운동 그래프 색 — 화면이 테마에서 읽는 값과 같다.
  const OnCareBrand brand = OnCareBrand.trainer;

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

  /// 운동 상자의 그래프. 두 상자가 같은 위젯을 쓰므로 시맨틱 문구로 가른다.
  BarLineChart exerciseChart(WidgetTester tester) => tester
      .widgetList<BarLineChart>(
        find.descendant(
          of: find.byType(MetricComparisonSection),
          matching: find.byType(BarLineChart),
        ),
      )
      .firstWhere((chart) => chart.semanticsLabel.startsWith('운동'));

  BarLineChart dietChart(WidgetTester tester) => tester
      .widgetList<BarLineChart>(
        find.descendant(
          of: find.byType(MetricComparisonSection),
          matching: find.byType(BarLineChart),
        ),
      )
      .firstWhere((chart) => chart.semanticsLabel.startsWith('식단'));

  Future<void> pickExercise(WidgetTester tester, String metric) async {
    final pill = find.byKey(ValueKey<String>('compare-exercise-$metric'));
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();
  }

  testWidgets('운동 지표를 바꾸면 막대와 꺾은선 색이 그 지표 색으로 바뀐다', (tester) async {
    await openReports(tester);

    // 기본은 소모 칼로리 — 유형 램프보다 한 단계 진한 결과 색이다.
    expect(exerciseChart(tester).barColor, brand.exerciseChart);

    for (final entry in <({String metric, Color color})>[
      (metric: 'cardio', color: brand.exerciseCardio),
      (metric: 'strength', color: brand.exerciseStrength),
      (metric: 'stretching', color: brand.exerciseStretching),
      (metric: 'burned', color: brand.exerciseChart),
    ]) {
      await pickExercise(tester, entry.metric);
      final BarLineChart chart = exerciseChart(tester);
      expect(chart.barColor, entry.color, reason: entry.metric);
      // 꺾은선은 같은 색의 진한 쪽이다 — 한 그림이 한 지표를 말한다.
      expect(
        chart.lineColor,
        Color.lerp(entry.color, OnCareColors.textPrimary, 0.3),
        reason: entry.metric,
      );
    }
  });

  testWidgets('운동 유형 색은 다른 운동 그래프와 같은 램프다', (tester) async {
    expect(kindColor(ExerciseKind.cardio), brand.exerciseCardio);
    expect(kindColor(ExerciseKind.strength), brand.exerciseStrength);
    expect(kindColor(ExerciseKind.stretching), brand.exerciseStretching);
    expect(kBurnColor, brand.exerciseChart);
  });

  testWidgets('식단 비교 그래프의 색은 그대로다', (tester) async {
    await openReports(tester);

    // 식단 상자는 지표와 무관하게 한 색을 쓴다 — 색을 주지 않으므로 그래프의
    // 기본값(브랜드 색)이 그대로 쓰인다.
    final BarLineChart diet = dietChart(tester);
    expect(diet.barColor, isNull);
    expect(diet.lineColor, isNull);
    // 칼로리 막대의 탄·단·지 조각도 그대로다.
    expect(diet.segments, isNotNull);
  });
}

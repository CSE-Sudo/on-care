/// 주간 추이 꺾은선의 목표선(#756).
///
/// 눈금 격자와 눈금 라벨을 걷어내고 목표선 하나만 남겼다. 점마다 값이 붙어
/// 있어 격자는 중복이었고, 축 바닥이 0 이 아니라 데이터 범위에 맞춰 올라가므로
/// 목표선이 없으면 점의 높이 자체에 뜻이 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';

import 'package:oncare_trainer/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double goal,
    String? goalLabel,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MetricTrendChart(
          values: const <double>[2200, 1900, 2050, 2300, 1850, 3428, 0],
          dayLabels: const <String>['월', '화', '수', '목', '금', '토', '일'],
          goal: goal,
          ticks: const <double>[0, 1750, 3500],
          todayIndex: 5,
          semanticsLabel: '나트륨 주간 추이',
          goalLabel: goalLabel,
          formatTick: metricTrendNumber,
        ),
      ),
    ),
  );

  testWidgets('목표선 라벨이 축 칸에 붙는다', (WidgetTester tester) async {
    await pump(tester, goal: 2000, goalLabel: '목표\n2,000');

    expect(find.text('목표\n2,000'), findsOneWidget);
    // 눈금 라벨이 있던 자리다 — 되살아나면 여기서 걸린다.
    expect(find.text('1,750'), findsNothing);
    expect(find.text('3,500'), findsNothing);
  });

  testWidgets('목표가 없는 지표에는 라벨을 그리지 않는다', (WidgetTester tester) async {
    // 목표 0 은 "목표가 없다"는 뜻이다. `목표 0` 이라고 적으면 하루 섭취량을
    // 0 으로 맞추라는 말이 된다.
    await pump(tester, goal: 0, goalLabel: '목표\n0');

    expect(find.text('목표\n0'), findsNothing);
  });

  testWidgets('라벨을 주지 않으면 선만 그린다', (WidgetTester tester) async {
    await pump(tester, goal: 2000);

    expect(find.byType(MetricTrendChart), findsOneWidget);
    expect(find.textContaining('목표'), findsNothing);
  });

  test('눈금은 그리지 않아도 축의 위아래를 정한다', () {
    // `ticks` 를 지우면 세 지표의 축이 서로 다르게 움직인다. 당류처럼 바닥이
    // 0 에 고정되는 성질이 여기서 나온다.
    for (final (
          String name,
          List<double> values,
          List<double> ticks,
          double goal,
        )
        in <(String, List<double>, List<double>, double)>[
          ('칼로리', <double>[1710, 1830, 1560], <double>[0, 1500, 2500], 2000),
          ('나트륨', <double>[2200, 1900, 2050], <double>[0, 1750, 3500], 2000),
          ('당류', <double>[41.5, 28, 45.5], <double>[0, 25, 50], 50),
        ]) {
      final (double lo, _) = metricTrendScale(
        values: values,
        ticks: ticks,
        goal: goal,
      );
      expect(lo, 0, reason: '$name 축의 바닥이 0 이 아니다');
    }
  });

  test('목표 안쪽인 날은 영양 요약 카드와 같은 메인 색으로 찍는다 (#1166)', () {
    // 초록이 아니다. 초록은 "정상" 으로 읽혀서 목표에 한참 못 미친 날까지
    // 괜찮다고 말한다 — 회원 앱이 #1070 에서 걷어낸 것과 같은 이유다.
    expect(metricStatusColor(1800, 2000), OnCareBrand.trainer.primary);
    expect(metricStatusColor(1800, 2000), isNot(OnCareColors.success));
    // 초과는 그대로 빨강이다.
    expect(metricStatusColor(2400, 2000), OnCareColors.danger);
    // 목표가 없는 지표(0)는 초과로 보지 않는다.
    expect(metricStatusColor(2400, 0), OnCareBrand.trainer.primary);
  });

  testWidgets('진입 애니메이션 없이 한 번에 그린다 (#1027)', (WidgetTester tester) async {
    await pump(tester, goal: 2000);

    // 첫 프레임에서 값이 이미 다 적혀 있다. 예전에는 620ms 동안 선이 이어지며
    // 값이 하나씩 나타나, 읽으려는 사람이 그림이 끝나기를 기다려야 했다.
    expect(find.byType(MetricTrendChart), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

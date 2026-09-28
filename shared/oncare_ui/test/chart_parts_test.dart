/// 차트 부품 공용화(#2469) — 링 게이지·범례·기간 라벨·음성 안내 조립.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(
        brand: OnCareBrand.trainer,
        density: OnCareDensity.web,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

const AppChartA11yLabels _labels = AppChartA11yLabels(
  point: _point,
  empty: _empty,
  summary: _summary,
);
String _point(String day, String value) => '$day $value';
String _empty(String title) => '$title. 기록이 없어요';
String _summary(String title, String detail) => '$title. $detail';

void main() {
  testWidgets('링 게이지는 받은 칸을 채우고 가운데에 내용을 얹는다', (tester) async {
    for (final AppRingGaugeStyle style in AppRingGaugeStyle.values) {
      await _pump(
        tester,
        SizedBox.square(
          dimension: 120,
          child: AppRingGauge(
            value: 1.4,
            color: OnCareBrand.trainer.primary,
            stroke: 12,
            style: style,
            startIcon: Icons.local_fire_department_rounded,
            child: const Center(child: Text('140%')),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppRingGauge)), const Size(120, 120));
      expect(
        tester.getCenter(find.text('140%')),
        tester.getCenter(find.byType(AppRingGauge)),
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('한 바퀴를 넘긴 몫과 목표 배수', () {
    expect(ringOverflowTurn(2.09), closeTo(0.09, 1e-9));
    expect(isAtRingMultiple(2), isTrue);
    expect(isAtRingMultiple(1.37), isFalse);
  });

  testWidgets('범례 한 칸은 견본 8 · 간격 4 · caption 600 보조 글자다', (tester) async {
    await _pump(
      tester,
      const AppChartLegendItem(color: Colors.blue, label: '오늘 할 일'),
    );

    final Rect swatch = tester.getRect(find.byType(AppChartSwatch));
    final Rect label = tester.getRect(find.text('오늘 할 일'));
    expect(swatch.size, const Size(8, 8));
    expect(label.left - swatch.right, OnCareSpacing.s4);
    final TextStyle style = tester.widget<Text>(find.text('오늘 할 일')).style!;
    expect(style.fontWeight, FontWeight.w600);
    expect(style.color, OnCareColors.textSecondary);
  });

  test('기간 라벨은 1년 미만이면 월·일만, 넘으면 연도까지 적는다', () async {
    await initializeDateFormatting('ko');
    expect(
      periodRangeText('ko', DateTime(2026, 9, 14), DateTime(2026, 9, 20)),
      isNot(contains('2026')),
    );
    expect(
      periodRangeText('ko', DateTime(2025, 11, 3), DateTime(2026, 12, 15)),
      contains('2025'),
    );
  });

  test('음성 안내는 0 인 날을 빼고, 비면 비었다고 말한다', () {
    expect(
      chartSemanticsLabel(
        _labels,
        title: '섭취 칼로리',
        points: chartSeriesPoints(
          _labels,
          values: const <double>[1200, 0, 900],
          dayLabels: const <String>['월', '화', '수'],
          format: (double v) => '${v.round()}kcal',
        ),
      ),
      '섭취 칼로리. 월 1200kcal, 수 900kcal',
    );
    expect(
      chartSemanticsLabel(_labels, title: '당류', points: const <String>[]),
      '당류. 기록이 없어요',
    );
  });
}

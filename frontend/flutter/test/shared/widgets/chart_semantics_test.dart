/// `CustomPaint` 로 그린 그래프가 스크린리더에 무엇을 말하는지. (#972)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/chart_semantics.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';

/// [body] 를 두 로케일로 각각 그려 보고, 그 안에서 만든 라벨을 돌려준다.
Future<Map<String, String>> _perLocale(
  WidgetTester tester,
  String Function(AppLocalizations l) body,
) async {
  final Map<String, String> out = <String, String>{};
  for (final String code in <String>['ko', 'en']) {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(code),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            out[code] = body(AppLocalizations.of(context));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
  }
  return out;
}

void main() {
  testWidgets('요일별 값을 한 문장으로 모은다', (WidgetTester tester) async {
    final Map<String, String> labels = await _perLocale(
      tester,
      (AppLocalizations l) => chartSemanticsLabel(
        l,
        title: '주간 소모 칼로리',
        points: chartSeriesPoints(
          l,
          values: const <double>[300, 0, 520],
          dayLabels: const <String>['월', '화', '수'],
          format: (double v) => '${v.round()}kcal',
        ),
      ),
    );

    for (final String label in labels.values) {
      expect(label, contains('주간 소모 칼로리'));
      expect(label, contains('월 300kcal'));
      expect(label, contains('수 520kcal'));
      // 0 은 이 앱에서 `기록 없음` 이다. 측정된 0 처럼 읽히면 안 된다.
      expect(label, isNot(contains('화')));
    }
  });

  testWidgets('아직 오지 않은 요일은 읽지 않는다', (WidgetTester tester) async {
    // 선은 오늘까지만 그린다 — 그 뒤 칸을 읽으면 화면에 없는 값을 말한다.
    final Map<String, String> labels = await _perLocale(
      tester,
      (AppLocalizations l) => chartSemanticsLabel(
        l,
        title: '나트륨',
        points: chartSeriesPoints(
          l,
          values: const <double>[1800, 1900, 2100],
          dayLabels: const <String>['월', '화', '수'],
          format: (double v) => '${v.round()}mg',
          upTo: 1,
        ),
      ),
    );

    for (final String label in labels.values) {
      expect(label, contains('월 1800mg'));
      expect(label, contains('화 1900mg'));
      expect(label, isNot(contains('2100mg')));
    }
  });

  testWidgets('기록이 하나도 없으면 비어 있다고 말한다', (WidgetTester tester) async {
    final Map<String, String> labels = await _perLocale(
      tester,
      (AppLocalizations l) => chartSemanticsLabel(
        l,
        title: '당류',
        points: chartSeriesPoints(
          l,
          values: const <double>[0, 0, 0],
          dayLabels: const <String>['월', '화', '수'],
          format: (double v) => '${v.round()}g',
        ),
      ),
    );

    expect(labels['ko'], '당류. 기록이 없어요');
    expect(labels['en'], '당류. No records yet');
  });

  testWidgets('꺾은선 그래프는 요약 한 문장만 시맨틱 트리에 남긴다', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: 320,
            child: MetricTrendChart(
              values: <double>[1800, 1900, 2100, 0, 0, 0, 0],
              dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
              goal: 2000,
              ticks: <double>[0, 1750, 3500],
              todayIndex: 2,
              replayKey: 'sodium',
              semanticsLabel: '나트륨 주간 추이. 월 1800mg, 화 1900mg, 수 2100mg',
              formatTick: metricTrendNumber,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.bySemanticsLabel('나트륨 주간 추이. 월 1800mg, 화 1900mg, 수 2100mg'),
      findsOneWidget,
    );
    // 요일 낱글자는 시맨틱 트리에 남지 않는다 — `월` `화` 만 읽어서는 그래프가
    // 무슨 값을 말하는지 알 수 없다.
    expect(find.bySemanticsLabel('월'), findsNothing);
    handle.dispose();
  });
}

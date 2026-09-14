/// `CustomPaint` 로 그린 그래프가 스크린리더에 무엇을 말하는지. (#972)
///
/// 회원 앱의 같은 이름 테스트와 짝이다 — 두 앱이 같은 그림을 그리므로 음성
/// 안내도 같은 말을 해야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';

import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/activity_charts.dart';
import 'package:oncare_trainer/shared/widgets/chart_semantics.dart';
import 'package:oncare_trainer/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<Map<String, String>> _perLocale(
  WidgetTester tester,
  String Function(AppLocalizations l) body,
) async {
  final out = <String, String>{};
  for (final code in <String>['ko', 'en']) {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(code),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
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

Future<void> _pump(WidgetTester tester, Widget child, {String locale = 'ko'}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 360, child: child)),
    ),
  );
}

/// [needle] 을 담은 시맨틱 노드를 찾는 finder.
Finder _labelled(String needle) =>
    find.bySemanticsLabel(RegExp(RegExp.escape(needle)));

/// 그 노드가 실제로 읽어 주는 문장.
String _label(WidgetTester tester, String needle) =>
    tester.getSemantics(_labelled(needle)).label;

void main() {
  testWidgets('요일별 값을 한 문장으로 모으고 0 은 읽지 않는다', (tester) async {
    final labels = await _perLocale(
      tester,
      (l) => chartSemanticsLabel(
        l,
        title: '나트륨 추이',
        points: chartSeriesPoints(
          l,
          values: const <double>[1800, 0, 2100],
          dayLabels: const <String>['월', '화', '수'],
          format: (v) => '${v.round()}mg',
        ),
      ),
    );

    for (final label in labels.values) {
      expect(label, contains('나트륨 추이'));
      expect(label, contains('월 1800mg'));
      expect(label, contains('수 2100mg'));
      // 0 은 이 앱에서 `기록 없음` 이다 — 측정된 0 처럼 읽히면 안 된다.
      expect(label, isNot(contains('화')));
    }
  });

  testWidgets('기록이 없으면 두 로케일 모두 비어 있다고 말한다', (tester) async {
    final labels = await _perLocale(
      tester,
      (l) => chartSemanticsLabel(l, title: '당류', points: const <String>[]),
    );

    expect(labels['ko'], '당류. 기록이 없어요');
    expect(labels['en'], '당류. No records yet');
  });

  testWidgets('꺾은선은 요약 한 문장만 남기고 요일 낱글자는 감춘다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const MetricTrendChart(
        values: <double>[1800, 1900, 2100, 0, 0, 0, 0],
        dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
        goal: 2000,
        ticks: <double>[0, 1750, 3500],
        todayIndex: 2,
        semanticsLabel: '나트륨 주간 추이. 월 1800mg',
        formatTick: metricTrendNumber,
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.bySemanticsLabel('나트륨 주간 추이. 월 1800mg'), findsOneWidget);
    expect(find.bySemanticsLabel('월'), findsNothing);
    handle.dispose();
  });

  testWidgets('막대 계열은 요일과 값을 함께 읽고 없는 칸은 건너뛴다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      BarSeriesChart(
        title: '주간 운동 이행률',
        values: const <int>[80, 0, 70],
        labels: const <String>['월', '화', '수'],
        maxValue: 100,
        valueSuffix: '%',
        missingIndices: const <int>{1},
      ),
    );

    final label = _label(tester, '주간 운동 이행률');
    expect(label, contains('월 80%'));
    expect(label, contains('수 70%'));
    // 기록이 없는 날은 0% 가 아니다.
    expect(label, isNot(contains('화')));
    handle.dispose();
  });

  testWidgets('링은 유형별 달성률을 한 덩어리로 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const BurnGoalRings(
        title: '이번 주 소모',
        calories: 900,
        split: ActivitySplit(
          cardioMinutes: 75,
          strengthSets: 7,
          stretchingMinutes: 30,
        ),
      ),
    );

    expect(_labelled('유산소 50%'), findsOneWidget);
    expect(_labelled('근력 33%'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('한 칸도 기록이 없는 기간은 비어 있다고 한 번만 말한다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      BurnBarChart(
        title: '운동 현황',
        calories: const <int>[0, 0],
        splits: const <ActivitySplit>[ActivitySplit(), ActivitySplit()],
        dates: <DateTime>[DateTime(2026, 8, 17), DateTime(2026, 8, 18)],
        selection: PeriodChartSelection(),
      ),
    );

    expect(_labelled('기록이 없어요'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('도넛은 가운데 숫자를 한 덩어리로 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const BurnDonut(
        title: '오늘 소모',
        calories: 411,
        goal: 300,
        split: ActivitySplit(
          cardioMinutes: 15,
          strengthSets: 15,
          stretchingMinutes: 12,
        ),
      ),
    );

    // 도넛 오른쪽 열 머리글에도 같은 문구가 있다 — 숫자까지 함께 읽는 노드를
    // 지목한다.
    expect(_labelled('오늘 소모. 411kcal'), findsOneWidget);
    handle.dispose();
  });
}

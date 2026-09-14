/// 홈 탭과 식단 탭이 함께 쓰는 주간 추이 꺾은선. (#688)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  group('metricStatusColor', () {
    test('목표를 넘긴 날만 초과색이다', () {
      expect(metricStatusColor(2100, 2000), OnCareColors.danger);
      expect(metricStatusColor(1900, 2000), OnCareBrand.member.statusWithinGoal);
      // 경계는 초과가 아니다.
      expect(metricStatusColor(2000, 2000), OnCareBrand.member.statusWithinGoal);
    });

    test('목표가 0 이면 어떤 값도 초과가 아니다', () {
      // `v > goal` 만 두면 목표 없는 지표의 **모든** 기록이 빨간 점이 되어,
      // 같은 카드의 평균 뱃지(목표가 있을 때만 초과 판정)와 어긋난다.
      expect(metricStatusColor(1, 0), OnCareBrand.member.statusWithinGoal);
      expect(metricStatusColor(9999, 0), OnCareBrand.member.statusWithinGoal);
    });
  });

  group('metricTrendScale', () {
    test('데이터와 눈금을 모두 담는다', () {
      final (double lo, double hi) = metricTrendScale(
        values: <double>[1200, 1800],
        ticks: <double>[0, 1500, 2500],
        goal: 2000,
      );
      expect(lo, lessThanOrEqualTo(0));
      expect(hi, greaterThanOrEqualTo(2500));
    });

    test('0 이 최소 눈금이면 바닥을 0 아래로 내리지 않는다', () {
      final (double lo, double _) = metricTrendScale(
        values: <double>[10, 20],
        ticks: <double>[0, 25, 50],
        goal: 50,
      );
      expect(lo, 0);
    });
  });

  testWidgets('요일 라벨은 로케일을 따른다', (WidgetTester tester) async {
    // 한쪽만 하드코딩하면 영어 로케일에서 한글 요일이 그대로 남는다.
    late List<String> ko;
    late List<String> en;
    for (final (Locale locale, void Function(List<String>) sink) in <
      (Locale, void Function(List<String>))
    >[
      (const Locale('ko'), (List<String> v) => ko = v),
      (const Locale('en'), (List<String> v) => en = v),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) {
              sink(weekDayLabels(AppLocalizations.of(context)));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
    }

    expect(ko, hasLength(7));
    expect(en, hasLength(7));
    expect(en, isNot(ko), reason: '로케일이 달라도 같은 요일 문구가 나옵니다.');
  });

  testWidgets('요일 수만큼 라벨을 그리고 오늘만 강조한다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: MetricTrendChart(
              values: const <double>[1, 2, 3, 4, 5, 6, 7],
              dayLabels: const <String>['월', '화', '수', '목', '금', '토', '일'],
              goal: 5,
              ticks: const <double>[0, 5, 10],
              todayIndex: 2,
              replayKey: 'k',
              semanticsLabel: '나트륨 주간 추이',
              formatTick: (double v) => v.toStringAsFixed(0),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    for (final String d in <String>['월', '화', '수', '목', '금', '토', '일']) {
      expect(find.text(d), findsOneWidget);
    }
    // 오늘 배지는 하나뿐이다.
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
      findsOneWidget,
    );
  });
}

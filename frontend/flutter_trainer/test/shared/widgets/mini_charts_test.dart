import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  Future<void> pumpChart(WidgetTester tester, {int? pendingFromIndex}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BarSeriesChart(
            title: '주간 이행률',
            values: const <int>[100, 80, 60, 40, 20, 10, 5],
            labels: const <String>['월', '화', '수', '목', '금', '토', '일'],
            maxValue: 100,
            showValues: true,
            valueSuffix: '%',
            pendingFromIndex: pendingFromIndex,
          ),
        ),
      ),
    );
  }

  group('BarSeriesChart', () {
    testWidgets('prints every value when no day is pending', (tester) async {
      await pumpChart(tester);

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
      expect(find.text('5%'), findsOneWidget);
    });

    testWidgets('days that have not happened print no value', (tester) async {
      // Shown on a Thursday: 금/토/일 are still ahead. Whatever the source
      // holds for them is not a result the member earned, so the chart
      // must not state it — a printed "20%" for Friday reads as a real,
      // bad Friday.
      await pumpChart(tester, pendingFromIndex: 4);

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('20%'), findsNothing);
      expect(find.text('10%'), findsNothing);
      expect(find.text('5%'), findsNothing);

      // The labels stay: the week is still Mon–Sun, those days just
      // haven't come round yet.
      expect(find.text('금'), findsOneWidget);
      expect(find.text('일'), findsOneWidget);
    });

    testWidgets('a pending day never takes the over-target colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BarSeriesChart(
              title: '주간 이행률',
              // Fri/Sat/Sun are over the threshold in the source data but
              // haven't happened; painting their track red would report a
              // bad day the member could not have had yet.
              values: const <int>[10, 10, 10, 10, 90, 90, 90],
              labels: const <String>['월', '화', '수', '목', '금', '토', '일'],
              maxValue: 100,
              overThreshold: 50,
              pendingFromIndex: 4,
            ),
          ),
        ),
      );

      final tracks = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>()
          .toList();
      expect(tracks, isNot(contains(OnCareColors.danger)));
      expect(tracks.where((c) => c == OnCareColors.lineSubtle).length, 3);
    });

    testWidgets('missing comparison values render as unknown, not zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BarSeriesChart(
              title: '주간 이행률',
              values: const <int>[0, 75],
              labels: const <String>['지난 주', '이번 주'],
              maxValue: 100,
              showValues: true,
              valueSuffix: '%',
              missingIndices: const <int>{0},
            ),
          ),
        ),
      );

      // '-' 는 0 과 헷갈린다 — 기록이 없다는 말을 그대로 쓴다(#754).
      expect(find.text('기록 없음'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
      expect(find.text('75%'), findsOneWidget);
    });
  });
}

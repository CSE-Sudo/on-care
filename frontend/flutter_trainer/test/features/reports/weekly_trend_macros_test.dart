/// 주간 칼로리 추이에 탄·단·지를 함께 보여 준다. (#1437)
///
/// 꺾은선은 그날 **얼마나** 먹었는지를 말하고, 아래 줄은 그 칼로리가
/// **무엇으로** 이루어졌는지를 말한다. 값·색은 리포트가 이미 들고 있는 것과
/// 다른 화면이 쓰는 토큰 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/design_system/theme/app_theme.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/metric_trend_section.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

import '../../helpers/client_factory.dart';

WeeklyReport _report({
  List<double> carbs = const <double>[240, 250, 0, 0, 0, 0, 0],
  List<double> protein = const <double>[120, 118, 0, 0, 0, 0, 0],
  List<double> fat = const <double>[60, 58, 0, 0, 0, 0, 0],
  List<int> calories = const <int>[2000, 2050, 0, 0, 0, 0, 0],
}) => WeeklyReport(
  client: makeClient(name: '김민수'),
  weekStart: DateTime(2026, 8, 17),
  sessionsBooked: 0,
  sessionsDone: 0,
  completionAvg: 80,
  sodiumOverDays: 0,
  sodiumAvg: 1500,
  isCurrentWeek: false,
  caloriesWeek: calories,
  sodiumWeek: const <int>[1400, 1500, 0, 0, 0, 0, 0],
  sugarWeek: const <double>[20, 22, 0, 0, 0, 0, 0],
  carbsWeek: carbs,
  proteinWeek: protein,
  fatWeek: fat,
);

Future<void> _pump(WidgetTester tester, WeeklyReport report) async {
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // 아래 4주 추이 카드가 provider 를 읽는다 — 이 검사의 관심은 위쪽 주간
  // 그래프라 스코프만 세워 준다.
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        // 위젯이 두 앱 공용 규격 토큰(`context.oncare`)을 읽는다.
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MetricTrendSection(report: report),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Finder strip() => find.byKey(const ValueKey<String>('trend-macro-strip'));

  testWidgets('칼로리를 볼 때 탄·단·지 줄이 함께 선다', (tester) async {
    await _pump(tester, _report());

    expect(strip(), findsOneWidget);
    // 이름과 단위 — 칼로리는 kcal, 탄단지는 g.
    expect(find.textContaining('탄수화물'), findsWidgets);
    expect(find.textContaining('단백질'), findsWidgets);
    expect(find.textContaining('지방'), findsWidgets);
    expect(find.textContaining('g'), findsWidgets);
  });

  testWidgets('나트륨·당류를 고르면 탄단지 줄이 사라진다', (tester) async {
    await _pump(tester, _report());

    await tester.tap(find.byKey(const ValueKey<String>('trend-metric-sodium')));
    await tester.pumpAndSettle();
    expect(strip(), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('trend-metric-sugar')));
    await tester.pumpAndSettle();
    expect(strip(), findsNothing);

    // 다시 칼로리로 돌아오면 그대로 있다.
    await tester.tap(
      find.byKey(const ValueKey<String>('trend-metric-calories')),
    );
    await tester.pumpAndSettle();
    expect(strip(), findsOneWidget);
  });

  testWidgets('탄단지 계열이 없거나 7일이 아니면 줄을 그리지 않는다', (tester) async {
    await _pump(
      tester,
      _report(
        carbs: const <double>[],
        protein: const <double>[],
        fat: const <double>[],
      ),
    );
    expect(strip(), findsNothing);

    await _pump(
      tester,
      _report(
        carbs: const <double>[240, 250],
        protein: const <double>[120, 118],
        fat: const <double>[60, 58],
      ),
    );
    expect(strip(), findsNothing);
  });

  testWidgets('영양이 하나도 없는 주는 0g 막대를 지어내지 않는다', (tester) async {
    await _pump(
      tester,
      _report(
        carbs: List<double>.filled(7, 0),
        protein: List<double>.filled(7, 0),
        fat: List<double>.filled(7, 0),
      ),
    );

    expect(strip(), findsNothing);
  });

  testWidgets('음성 안내가 요일별 탄·단·지를 함께 읽는다', (tester) async {
    await _pump(tester, _report());

    final Finder semantics = find.ancestor(
      of: strip(),
      matching: find.byType(Semantics),
    );
    final String label = tester.getSemantics(semantics.first).label;
    expect(label, contains('탄수화물'));
    expect(label, contains('단백질'));
    expect(label, contains('지방'));
  });
}

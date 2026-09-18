/// `이번 주` 꺾은선의 점을 고르면 머리 숫자가 그날 값으로 바뀐다 (#1122).
///
/// `전체` 막대와 같은 규칙이다 — 고른 날이 있으면 그날, 없으면 하루 평균.
/// 점에서 먼 곳을 누르면 선택이 풀려 다시 평균으로 돌아온다. 이번 주가 막대에서
/// 꺾은선으로 돌아온 뒤에도(#1879) 이 규칙은 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

/// 날마다 다른 값을 주는 대역 — 고른 날과 평균이 갈려야 검증이 된다.
class _VaryingDietRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async => _dayOf(date);

  @override
  Future<DietDay> fetchToday() async => _dayOf(nowKst());

  static DietDay _dayOf(DateTime date) {
    final int calories = 1000 + date.day * 20;
    return DietDay(
      entries: <DietEntry>[
        DietEntry(
          id: 'e-${date.day}',
          mealType: MealType.lunch,
          timeLabel: '12:00',
          foods: const <FoodItem>[],
          totalCalories: calories,
          sodiumMg: 800 + date.day * 5,
          sugarG: 10,
          carbsG: 100,
          proteinG: 50,
          fatG: 20,
        ),
      ],
      totalCalories: calories,
      totalSodiumMg: 800 + date.day * 5,
      totalSugarG: 10,
      macros: const DietMacros(
        carbsPct: 50,
        proteinPct: 30,
        fatPct: 20,
        carbsG: 100,
        proteinG: 50,
        fatG: 20,
      ),
      aiCoachMessage: '',
    );
  }
}

Widget _app() => ProviderScope(
  overrides: <Override>[
    dietRepositoryProvider.overrideWithValue(_VaryingDietRepository()),
    accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DietRecordPage(),
  ),
);

void main() {
  Future<void> openWeek(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();
  }

  /// 카드 머리에 적힌 첫 줄(`하루 평균` 또는 `8. 17.`).
  // 날짜 기간이 카드 안으로 들어오며(#2009) 카드의 첫 `Text` 가 됐다 —
  // 머리줄은 `PeriodChartHeadline` 안에서 집는다.
  String headline(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(PeriodChartHeadline),
          matching: find.byType(Text),
        ),
      )
      .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .first;

  /// 꺾은선에서 [index] 번째 점의 화면 좌표. 막대와 달리 점에는 칸마다 키가
  /// 없으므로(그리는 것이 `CustomPaint` 하나다) 자리를 계산해 누른다.
  Offset pointAt(WidgetTester tester, int index, int count) {
    final Rect box = tester.getRect(find.byType(MetricTrendChart));
    // 목표 라벨 칸을 뺀 실제 그리기 영역의 왼쪽 끝을 찾는다.
    final Rect paint = tester.getRect(
      find
          .descendant(
            of: find.byType(MetricTrendChart),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    final double step = paint.width / (count - 1);
    return Offset(paint.left + step * index, box.top + paint.height / 2);
  }

  testWidgets('점을 고르면 하루 평균 대신 그날 값이 뜬다', (WidgetTester tester) async {
    await openWeek(tester);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DietRecordPage)),
    );

    expect(headline(tester), contains(l.dietPeriodAverage));

    // 이번 주 월요일(첫 점)을 누른다.
    await tester.tapAt(pointAt(tester, 0, 7));
    await tester.pumpAndSettle();

    expect(
      headline(tester),
      isNot(contains(l.dietPeriodAverage)),
      reason: '점을 골랐는데 머리 문구가 하루 평균 그대로다',
    );
    // 그날 날짜만 적는다 — 지표가 칼로리 하나뿐이라 `· 칼로리` 를 붙이지 않는다.
    final DateTime monday = dietRangeForTab(DietPeriodTab.week, nowKst()).from;
    // 연도 없이 월·일만 — 날짜 기간과 같은 형식이다.
    expect(headline(tester), DateFormat.Md('ko').format(monday));

    // 같은 점을 다시 누르면 선택이 풀린다.
    await tester.tapAt(pointAt(tester, 0, 7));
    await tester.pumpAndSettle();
    expect(headline(tester), contains(l.dietPeriodAverage));
  });
}

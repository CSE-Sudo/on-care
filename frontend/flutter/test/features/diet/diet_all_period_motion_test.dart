/// `전체` 막대가 바닥에서 자란다. (#1148, #1200)
///
/// 지표를 바꾸면 다시 자라는지도 여기서 봤다 — 칸 수만 보고 되감으면 개수가
/// 같은 전환에서 그림만 슬쩍 바뀌어, 무엇이 달라졌는지 눈으로 따라갈 수가
/// 없었다. 그 경우는 이제 없다(#1879): 그래프가 칼로리 하나라 바꿀 지표가
/// 없고, 기간을 바꾸면 그림(꺾은선 ↔ 막대)이 통째로 바뀐다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';
import '../../helpers/record_span.dart';

/// 날마다 다른 값을 주는 대역 — 막대 높이가 서로 달라야 자라는 것이 보인다.
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
          sugarG: 10 + date.day % 7,
          carbsG: 100,
          proteinG: 50,
          fatG: 20,
        ),
      ],
      totalCalories: calories,
      totalSodiumMg: 800 + date.day * 5,
      totalSugarG: 10 + date.day % 7,
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
    testRecordSpanOverride(),
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

/// 오늘(마지막) 칸에서 **드러난** 높이. 자라는 것은 막대 자체가 아니라 그것을
/// 감싼 `ClipRect` 다(`period-bar-reveal-N`).
Finder _lastReveal() {
  final List<DateTime> dates = dietRangeDates(
    dietRangeForTab(
      DietPeriodTab.month,
      nowKst(),
      firstRecord: testFirstRecordDate(),
    ),
  );
  return find.byKey(ValueKey<String>('period-bar-reveal-${dates.length - 1}'));
}

double _lastBarHeight(WidgetTester tester) {
  final List<DateTime> dates = dietRangeDates(
    dietRangeForTab(
      DietPeriodTab.month,
      nowKst(),
      firstRecord: testFirstRecordDate(),
    ),
  );
  final Finder reveal = find.byKey(
    ValueKey<String>('period-bar-reveal-${dates.length - 1}'),
  );
  return tester.getSize(reveal).height;
}

void main() {
  Future<void> openAll(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    // 애니메이션이 도는 중간에서 멈춘다 — settle 하면 다 자란 뒤다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('막대는 바닥에서 자란다', (WidgetTester tester) async {
    await openAll(tester);
    final double atStart = _lastBarHeight(tester);

    await tester.pumpAndSettle();
    final double settled = _lastBarHeight(tester);

    expect(atStart, lessThan(settled), reason: '막대가 처음부터 다 자라 있다');
    expect(settled, greaterThan(0));
  });

  testWidgets('막대의 바닥은 자라는 동안 제자리다 (#1200)', (WidgetTester tester) async {
    await openAll(tester);
    // 자라는 줄이 위쪽 모서리에 매달려 있으면, 커지는 만큼 바닥이 **아래로**
    // 내려간다 — 막대가 자라는 것이 아니라 그래프가 통째로 내려오는 그림이다.
    final double growingBottom = tester.getRect(_lastReveal()).bottom;
    final double growingHeight = _lastBarHeight(tester);

    await tester.pumpAndSettle();
    final double settledBottom = tester.getRect(_lastReveal()).bottom;

    expect(growingHeight, lessThan(_lastBarHeight(tester)));
    expect(
      growingBottom,
      moreOrLessEquals(settledBottom, epsilon: 0.5),
      reason: '자라는 동안 막대의 바닥이 움직인다',
    );
  });
}

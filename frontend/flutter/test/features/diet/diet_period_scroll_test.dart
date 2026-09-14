/// `전체` 그래프는 옆으로 밀어 보고, 한 칸을 고르면 그날의 값이 머리에 뜬다.
/// (#1018)
///
/// 예전에는 한 달치를 한 화면에 욱여넣어 막대가 실처럼 얇았고, 그 앞의 기록은
/// 볼 방법이 아예 없었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 날마다 다른 칼로리를 주는 저장소 — 고른 날의 숫자가 평균과 갈리는지 보려면
/// 날마다 값이 달라야 한다.
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
          sodiumMg: 900,
          sugarG: 10,
          carbsG: 100,
          proteinG: 50,
          fatG: 20,
        ),
      ],
      totalCalories: calories,
      totalSodiumMg: 900,
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
  Future<void> openAll(WidgetTester tester) async {
    // 오늘을 고정한다. 대역이 날짜(`date.day`)로 칼로리를 만들어, 보이는 30일
    // 창이 달의 어디에 걸리느냐로 평균이 달라진다 — 고정하지 않으면 이 테스트는
    // 달력에 매인다. 실제로 8월 말에 두 구간의 평균이 같아져 깨졌다.
    useFixedKstDate();

    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diet-period-tab-month')));
    await tester.pumpAndSettle();
  }

  testWidgets('전체 그래프는 가로로 스크롤된다 — 한 화면에 30일', (WidgetTester tester) async {
    await openAll(tester);

    final Finder chart = find.descendant(
      of: find.byKey(const Key('diet-period-card')),
      matching: find.byType(Scrollable),
    );
    final Iterable<Scrollable> scrollables = tester.widgetList<Scrollable>(
      chart,
    );
    expect(
      scrollables.any((Scrollable s) => s.axisDirection == AxisDirection.right),
      isTrue,
      reason: '전체 그래프가 옆으로 밀리지 않는다',
    );

    // 12주치가 다 들어 있다 — 화면에 30일만 보일 뿐 잘라내지 않는다.
    final List<DateTime> dates = dietRangeDates(
      dietRangeForTab(DietPeriodTab.month, nowKst()),
    );
    expect(dates.length, kDietAllPeriodDays);
    expect(
      find.byKey(Key('diet-period-bar-${dates.length - 1}')),
      findsOneWidget,
    );
  });

  testWidgets('평균은 화면에 보이는 구간만 센다 — 밀면 따라 바뀐다', (
    WidgetTester tester,
  ) async {
    await openAll(tester);

    String headline() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('diet-period-card')),
            matching: find.byType(Text),
          ),
        )
        .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .firstWhere((String s) => s.contains('kcal'), orElse: () => '');

    final String atFirst = headline();
    expect(atFirst, isNotEmpty);

    // 왼쪽(과거)으로 민다. 대역이 날마다 다른 값을 주므로 보이는 구간이 바뀌면
    // 평균도 바뀌어야 한다.
    final Finder horizontal = find
        .descendant(
          of: find.byKey(const Key('diet-period-card')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(horizontal, const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(headline(), isNot(atFirst), reason: '평균이 보이는 구간을 따라가지 않는다');
  });

  testWidgets('막대를 고르면 평균 대신 그날의 값이 뜬다', (WidgetTester tester) async {
    await openAll(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DietRecordPage)),
    );
    // 평소에는 평균이다.
    expect(find.textContaining(l.dietPeriodAverage), findsWidgets);

    // 오늘 칸(마지막)을 고른다.
    final List<DateTime> dates = dietRangeDates(
      dietRangeForTab(DietPeriodTab.month, nowKst()),
    );
    final Finder lastBar = find.byKey(
      Key('diet-period-bar-${dates.length - 1}'),
    );
    await tester.tap(lastBar, warnIfMissed: false);
    await tester.pumpAndSettle();

    // 머리 문구가 날짜로 바뀐다 — `하루 평균` 이라고 적힌 곳이 없어야 한다.
    expect(find.textContaining(l.dietPeriodAverage), findsNothing);

    // 다시 누르면 선택이 풀리고 평균으로 돌아온다.
    await tester.tap(lastBar, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining(l.dietPeriodAverage), findsWidgets);
  });

  testWidgets('카드의 빈 곳을 누르면 고른 날이 풀린다 (#1123)', (WidgetTester tester) async {
    await openAll(tester);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DietRecordPage)),
    );

    final List<DateTime> dates = dietRangeDates(
      dietRangeForTab(DietPeriodTab.month, nowKst()),
    );
    await tester.tap(find.byKey(Key('diet-period-bar-${dates.length - 1}')));
    await tester.pumpAndSettle();
    expect(find.textContaining(l.dietPeriodAverage), findsNothing);

    // 카드 왼쪽 위 빈 자리 — 막대도 점도 아닌 곳.
    final Rect card = tester.getRect(find.byKey(const Key('diet-period-card')));
    await tester.tapAt(Offset(card.left + 6, card.top + 6));
    await tester.pumpAndSettle();
    expect(find.textContaining(l.dietPeriodAverage), findsWidgets);
  });
}

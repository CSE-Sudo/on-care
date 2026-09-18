/// 기간 토글을 오갈 때 앞 기간에서 고른 날이 남지 않는다 (#1984).
///
/// `DietPeriodView` 는 토글을 눌러도 트리의 같은 자리에 같은 타입으로 남아
/// `State` 가 재사용된다. 고른 것은 날짜가 아니라 **인덱스**라, 그대로 살아남으면
/// 다음 기간의 배열에 쓰인다 — `전체`(84칸)의 인덱스가 `이번 주`(7칸)로 넘어오면
/// 카드가 통째로 죽고, 반대 방향은 회원이 고른 적 없는 날을 가리킨다.
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
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 날마다 다른 값을 주는 대역 — 고른 날과 하루 평균이 갈려야 검증이 된다.
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
  Future<void> open(WidgetTester tester) async {
    // 대역이 날짜로 값을 만들어 보이는 창이 달의 어디에 걸리느냐로 평균이
    // 달라진다 — 고정하지 않으면 이 테스트가 달력에 매인다.
    useFixedKstDate();

    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
  }

  Future<void> tapTab(WidgetTester tester, DietPeriodTab tab) async {
    await tester.tap(dietPeriodTab(tab));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(DietRecordPage)));

  /// 카드 머리에 적힌 첫 줄 — `하루 평균 · 칼로리` 또는 `2026. 8. 17. · 칼로리`.
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

  /// 꺾은선 [index] 번째 점의 화면 좌표. 점에는 칸마다 키가 없다(그리는 것이
  /// `CustomPaint` 하나다) — 자리를 계산해 누른다.
  Offset pointAt(WidgetTester tester, int index, int count) {
    final Rect box = tester.getRect(find.byType(MetricTrendChart));
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

  testWidgets('전체에서 고른 막대가 이번 주로 넘어오지 않는다', (WidgetTester tester) async {
    await open(tester);
    final AppLocalizations l = l10n(tester);

    // 두 기간을 모두 한 번씩 읽어 둔다 — 배포본에서 재현될 때와 같은 상태다.
    await tapTab(tester, DietPeriodTab.week);
    await tapTab(tester, DietPeriodTab.month);

    // 전체의 마지막 칸(오늘, 인덱스 83)을 고른다. 이번 주는 7칸뿐이라 이
    // 인덱스가 넘어오면 범위를 벗어난다.
    await tester.tap(
      find.byKey(const Key('diet-period-bar-${kDietAllPeriodDays - 1}')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(headline(tester), isNot(contains(l.dietPeriodAverage)));

    await tapTab(tester, DietPeriodTab.week);

    expect(tester.takeException(), isNull, reason: '이번 주로 옮기며 카드가 죽었다');
    expect(find.byKey(const Key('diet-period-card')), findsOneWidget);
    expect(
      headline(tester),
      contains(l.dietPeriodAverage),
      reason: '기간을 옮겼는데 앞 기간에서 고른 날이 그대로 남았다',
    );
  });

  testWidgets('이번 주에서 고른 날이 전체로 넘어오지 않는다', (WidgetTester tester) async {
    await open(tester);
    final AppLocalizations l = l10n(tester);

    await tapTab(tester, DietPeriodTab.week);

    // 월요일(첫 점)을 고른다. 인덱스 0 은 전체에서도 범위 안이라 터지지 않고,
    // 12주 전의 엉뚱한 날을 가리킨다.
    await tester.tapAt(pointAt(tester, 0, 7));
    await tester.pumpAndSettle();
    expect(headline(tester), isNot(contains(l.dietPeriodAverage)));

    await tapTab(tester, DietPeriodTab.month);

    expect(tester.takeException(), isNull);
    expect(
      headline(tester),
      contains(l.dietPeriodAverage),
      reason: '전체로 옮겼는데 머리가 고른 날 상태로 굳어 있다',
    );
  });
}

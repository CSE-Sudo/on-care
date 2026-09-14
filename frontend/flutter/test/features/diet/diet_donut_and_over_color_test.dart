/// 식단 영양 요약의 도넛 모션과 초과 색 (#1201 · #1202).
///
///  * 오늘 화면의 달성률 도넛은 12시에서 지금 비율까지 채워지며 들어온다.
///  * 전체 화면의 칼로리 막대는 목표를 넘긴 날만 통으로 빨갛다 (#1352).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

/// 짝수 날은 목표(2,000kcal)를 넘고 홀수 날은 못 미친다 — 한 화면에서 두 색이
/// 함께 나와야 초과 표시가 무엇을 가르는지 잴 수 있다.
class _OverAndUnderDietRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async => _dayOf(date);

  static DietDay _dayOf(DateTime date) {
    final bool over = date.day.isEven;
    final int calories = over ? 3000 : 1200;
    final double carbsG = over ? 300 : 120;
    final double proteinG = over ? 150 : 60;
    final double fatG = over ? 100 : 40;
    return DietDay(
      entries: <DietEntry>[
        DietEntry(
          id: 'e-${date.day}',
          mealType: MealType.lunch,
          timeLabel: '12:00',
          foods: const <FoodItem>[],
          totalCalories: calories,
          sodiumMg: 900,
          sugarG: 12,
          carbsG: carbsG,
          proteinG: proteinG,
          fatG: fatG,
        ),
      ],
      totalCalories: calories,
      totalSodiumMg: 900,
      totalSugarG: 12,
      macros: DietMacros(
        carbsPct: 50,
        proteinPct: 30,
        fatPct: 20,
        carbsG: carbsG,
        proteinG: proteinG,
        fatG: fatG,
      ),
      aiCoachMessage: '',
    );
  }
}

Future<void> _pumpDiet(
  WidgetTester tester, {
  FakeDietRepository? repository,
}) async {
  tester.view.physicalSize = const Size(420, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dietRepositoryProvider.overrideWithValue(
          repository ?? FakeDietRepository(),
        ),
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DietRecordPage(),
      ),
    ),
  );
  // 하루치가 도착할 만큼(대역 120ms) 돌린 뒤 모션 중간에서 멈춘다 —
  // `pumpAndSettle` 하면 이미 다 채운 뒤다.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

double? _donutValue(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.byKey(const Key('nutrition-calorie-progress')),
                )
                .painter!
            as DietCalorieRingPainter)
        .value;

void main() {
  testWidgets('달성률 도넛은 채워지며 들어온다 (#1202)', (WidgetTester tester) async {
    await _pumpDiet(tester);

    final double? growing = _donutValue(tester);
    expect(growing, isNotNull);

    await tester.pumpAndSettle();
    final double? settled = _donutValue(tester);

    expect(growing, lessThan(settled!), reason: '도넛이 처음부터 다 차 있다');
    expect(settled, greaterThan(0));
  });

  testWidgets('다 채운 뒤에는 더 움직이지 않는다 (#1202)', (WidgetTester tester) async {
    await _pumpDiet(tester);
    await tester.pumpAndSettle();
    final double? settled = _donutValue(tester);

    await tester.pump(const Duration(milliseconds: 400));
    expect(_donutValue(tester), settled);
  });

  testWidgets('목표를 넘긴 날의 칼로리 막대는 통으로 빨강이다 (#1352)', (
    WidgetTester tester,
  ) async {
    await _pumpDiet(tester, repository: _OverAndUnderDietRepository());
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    await tester.pumpAndSettle();

    final Iterable<Color?> filled = tester
        .widgetList<Container>(find.byType(Container))
        .map((Container box) => (box.decoration as BoxDecoration?)?.color);

    expect(
      filled.contains(OnCareColors.danger),
      isTrue,
      reason: '초과한 날의 막대가 아직 통짜 빨강이 아니다',
    );
    // 목표 이내인 날은 탄단지 색을 쌓는다 (#1479). 전부 빨개지면 초과 표시가
    // 무의미해지므로 빨간 단색 막대와 누적 막대가 한 화면에 함께 있어야 한다.
    final Finder calorieBars = find.byWidgetPredicate((Widget widget) {
      final Key? key = widget.key;
      return key is ValueKey<String> &&
          RegExp(r'^diet-period-bar-\d+$').hasMatch(key.value);
    });
    final Set<Color> segmentColors = tester
        .widgetList<ColoredBox>(
          find.descendant(of: calorieBars, matching: find.byType(ColoredBox)),
        )
        .map((ColoredBox segment) => segment.color)
        .toSet();
    expect(
      segmentColors,
      containsAll(<Color>[
        OnCareBrand.member.macroCarbs,
        OnCareBrand.member.macroProtein,
        OnCareBrand.member.macroFat,
      ]),
      reason: '목표 이내인 날의 탄단지 누적 막대가 없다',
    );
  });
}

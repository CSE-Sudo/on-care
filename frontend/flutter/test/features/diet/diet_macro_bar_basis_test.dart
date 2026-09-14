import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/design_system/figma/figma_kit.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

/// 누적 칼로리 막대가 불완전한 영양 데이터에서도 총칼로리와 구성 비율을
/// 함께 사실대로 표현하는지 확인한다. (#956, #1479)
class _FixedDietRepository extends FakeDietRepository {
  _FixedDietRepository(this.day);

  final DietDay day;

  @override
  Future<DietDay> fetchByDate(DateTime date) async => day;

  @override
  Future<DietDay> fetchToday() async => day;
}

/// 하루 합계만 들고 있는 [DietDay] — 실서버 응답의 모양이다(음식 배열에는
/// 이름과 칼로리만 들어 있어, 영양은 하루/끼니 단위로만 온다).
DietDay _day({
  required int calories,
  double carbsG = 0,
  double proteinG = 0,
  double fatG = 0,
}) => DietDay(
  entries: <DietEntry>[
    DietEntry(
      id: 'e',
      mealType: MealType.lunch,
      timeLabel: '12:00',
      foods: const <FoodItem>[],
      totalCalories: calories,
      sodiumMg: 900,
      sugarG: 8,
      carbsG: carbsG,
      proteinG: proteinG,
      fatG: fatG,
    ),
  ],
  totalCalories: calories,
  totalSodiumMg: 900,
  totalSugarG: 8,
  macros: DietMacros(
    carbsPct: 0,
    proteinPct: 0,
    fatPct: 0,
    carbsG: carbsG,
    proteinG: proteinG,
    fatG: fatG,
  ),
  aiCoachMessage: '',
);

void main() {
  Future<void> openMonth(WidgetTester tester, DietDay day) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(_FixedDietRepository(day)),
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diet-period-tab-month')));
    await tester.pumpAndSettle();
  }

  List<(Color, double)> segmentsOf(WidgetTester tester) => <(Color, double)>[
    for (final Element e
        in find
            .descendant(
              of: find.byKey(const Key('diet-period-bar-0')),
              matching: find.byType(ColoredBox),
            )
            .evaluate())
      ((e.widget as ColoredBox).color, (e.renderObject! as RenderBox).size.height),
  ];

  testWidgets('탄단지가 다 있는 날은 세 색 구간을 쌓는다', (WidgetTester tester) async {
    await openMonth(
      tester,
      _day(calories: 1560, carbsG: 200, proteinG: 100, fatG: 40),
    );

    expect(segmentsOf(tester).map(((Color, double) s) => s.$1), <Color>[
      FigmaColors.macroFat,
      FigmaColors.macroProtein,
      FigmaColors.macroCarbs,
    ]);
  });

  testWidgets('칼로리와 탄단지 합계가 어긋나면 나머지 구간이 남는다', (
    WidgetTester tester,
  ) async {
    // 탄 100g(400) + 단 50g(200) + 지 20g(180) = 780kcal 인데 하루는 1,560kcal.
    await openMonth(
      tester,
      _day(calories: 1560, carbsG: 100, proteinG: 50, fatG: 20),
    );

    final List<(Color, double)> segments = segmentsOf(tester);
    final double total = segments.fold<double>(
      0,
      (double sum, (Color, double) segment) => sum + segment.$2,
    );
    final (Color, double) rest = segments.firstWhere(
      ((Color, double) segment) => segment.$1 == FigmaColors.track,
    );
    expect(rest.$2 / total, closeTo((1560 - 780) / 1560, 0.03));
  });

  testWidgets('탄수화물만 있는 날도 해당 색 구간이 그려진다', (WidgetTester tester) async {
    await openMonth(tester, _day(calories: 800, carbsG: 200));

    expect(segmentsOf(tester).single.$1, FigmaColors.macroCarbs);
    expect(tester.takeException(), isNull);
  });

  testWidgets('영양이 아예 없는 날은 지표 기본색 막대다', (WidgetTester tester) async {
    await openMonth(tester, _day(calories: 1500));

    expect(segmentsOf(tester), isEmpty);
  });

  testWidgets('영양이 하나도 없는 기간에는 탄단지 범례가 없다', (WidgetTester tester) async {
    // 칼로리 지표에서는 `days` 가 언제나 넘어간다. 범례까지 늘 그리면 한 색
    // 막대에 3색 범례가 붙어 막대 색의 뜻을 잘못 설명한다.
    await openMonth(tester, _day(calories: 1500));

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DietRecordPage)),
    );
    expect(find.byKey(const Key('diet-period-bar-0')), findsOneWidget);
    expect(find.text(l.homeMacroCarbs), findsNothing);
    expect(find.text(l.homeMacroProtein), findsNothing);
    expect(find.text(l.homeMacroFat), findsNothing);
  });

  testWidgets('영양이 있는 기간에는 범례가 보인다', (WidgetTester tester) async {
    await openMonth(
      tester,
      _day(calories: 1560, carbsG: 200, proteinG: 100, fatG: 40),
    );

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DietRecordPage)),
    );
    expect(find.text(l.homeMacroCarbs), findsWidgets);
    expect(find.text(l.homeMacroProtein), findsWidgets);
    expect(find.text(l.homeMacroFat), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/design_system/figma/figma_kit.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

Widget _app(Widget home, {List<Override> overrides = const <Override>[]}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

class _PastDateDietRepository extends FakeDietRepository {
  _PastDateDietRepository({this.fail = false});

  final bool fail;

  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    if (fail) throw StateError('date lookup failed');
    return const DietDay(
      entries: <DietEntry>[
        DietEntry(
          id: 'past-meal',
          mealType: MealType.lunch,
          timeLabel: '12:00',
          foods: <FoodItem>[FoodItem(name: '과거 식사', calories: 420)],
          totalCalories: 420,
          sodiumMg: 350,
          sugarG: 7.5,
          carbsG: 40,
          proteinG: 20,
          fatG: 10,
        ),
      ],
      totalCalories: 420,
      totalSodiumMg: 350,
      totalSugarG: 7.5,
      macros: DietMacros(
        carbsPct: 49,
        proteinPct: 24,
        fatPct: 27,
        carbsG: 40,
        proteinG: 20,
        fatG: 10,
      ),
      aiCoachMessage: '선택한 날짜의 피드백',
    );
  }
}

Future<void> _selectDaysAgo(WidgetTester tester, [int days = 1]) async {
  final DateTime now = nowKst();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime target = today.subtract(Duration(days: days));
  // 스트립은 월요일에서 시작해 일요일로 끝나는 **한 주**만 보여 준다(#1059).
  // 고르려는 날이 이번 주 밖이면 화살표로 그 주까지 옮긴 뒤 고른다 — 날짜만
  // 두드리던 예전 방식은 지난 날이 이번 주에 하나도 없는 **월요일마다**
  // 깨졌다.
  final DateTime monday = today.subtract(
    Duration(days: today.weekday - DateTime.monday),
  );
  for (
    DateTime week = monday;
    target.isBefore(week);
    week = week.subtract(const Duration(days: 7))
  ) {
    await tester.tap(find.byTooltip('지난 주'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('${target.day}'));
  await tester.pumpAndSettle();
}

void main() {
  // 지난 날짜를 누르는 테스트다 — 오늘이 월요일이면 스트립(이번 주 월~일)에
  // 어제가 없어 누를 칸이 사라진다. 오늘을 주 중간으로 고정한다 (#1209).
  setUp(useFixedKstDate);

  test('mock account keeps updated health goals', () async {
    final MockAccountRepository repository = MockAccountRepository();

    await repository.updateHealthGoals(
      dailyCalories: const GoalUpdate(1800),
      dailySodiumMg: const GoalUpdate(1500),
      dailySugarG: const GoalUpdate(35),
      dailyCarbsG: const GoalUpdate(220),
      dailyProteinG: const GoalUpdate(120),
      dailyFatG: const GoalUpdate(50),
    );

    final UserProfile profile = await repository.fetchProfile();
    expect(profile.effectiveDailyCalories, 1800);
    expect(profile.effectiveDailySodiumMg, 1500);
    expect(profile.effectiveDailySugarG, 35);
    expect(profile.effectiveDailyCarbsG, 220);
    expect(profile.effectiveDailyProteinG, 120);
    expect(profile.effectiveDailyFatG, 50);
  });

  test('health goal fallback is applied independently per field', () {
    const UserProfile profile = UserProfile(
      id: 'member',
      name: '회원',
      email: 'member@example.com',
      dailyCalories: 1800,
      dailySodiumMg: 1500,
      dailySugarG: 35,
      dailyCarbsG: 220,
      dailyProteinG: 120,
      dailyFatG: 50,
    );
    expect(profile.effectiveDailyCalories, 1800);
    expect(profile.effectiveDailySodiumMg, 1500);
    expect(profile.effectiveDailySugarG, 35);
    expect(profile.effectiveDailyCarbsG, 220);
    expect(profile.effectiveDailyProteinG, 120);
    expect(profile.effectiveDailyFatG, 50);

    const UserProfile partial = UserProfile(
      id: 'member',
      name: '회원',
      email: 'member@example.com',
      dailyCalories: 1800,
    );
    expect(partial.effectiveDailyCalories, 1800);
    expect(partial.effectiveDailySodiumMg, 2000);
    expect(partial.effectiveDailySugarG, 50);
    expect(partial.effectiveDailyCarbsG, 275);
    expect(partial.effectiveDailyProteinG, 100);
    expect(partial.effectiveDailyFatG, 55);
  });

  testWidgets('nutrition summary uses all personal health goals', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final DietDay day =
        await tester.runAsync(() => FakeDietRepository().fetchToday())
            as DietDay;
    const UserProfile profile = UserProfile(
      id: 'member',
      name: '회원',
      email: 'member@example.com',
      dailyCalories: 1800,
      dailySodiumMg: 1500,
      dailySugarG: 35,
      dailyCarbsG: 220,
      dailyProteinG: 120,
      dailyFatG: 50,
    );

    await tester.pumpWidget(
      _app(
        Scaffold(
          body: NutritionSummary(day: day, profile: profile),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1,800 kcal'), findsOneWidget);
    expect(find.textContaining('/ 220g'), findsOneWidget);
    expect(find.textContaining('/ 120g'), findsOneWidget);
    expect(find.textContaining('/ 50g'), findsOneWidget);
    expect(find.textContaining('/ 1,500mg'), findsOneWidget);
    expect(find.textContaining('/ 35g'), findsOneWidget);
  });

  testWidgets(
    'nutrition summary highlights progress and status on a small screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(340, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final DietDay day =
          await tester.runAsync(() => FakeDietRepository().fetchToday())
              as DietDay;

      await tester.pumpWidget(_app(Scaffold(body: NutritionSummary(day: day))));
      await tester.pumpAndSettle();

      final Finder summaryCard = find.byKey(
        const Key('nutrition-summary-card'),
      );
      expect(summaryCard, findsOneWidget);
      expect(
        find.byKey(const Key('nutrition-calorie-progress')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summaryCard,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('1,067'), findsOneWidget);
      expect(find.textContaining('2,000 kcal'), findsOneWidget);
      expect(find.textContaining('3,428'), findsOneWidget);
      expect(find.textContaining('17.8'), findsOneWidget);
      // 배지도, 차이를 설명하는 문장도 없다 — 카드마다 있고 없고가 갈려
      // 높이를 들쭉날쭉하게 만들었다 (#1070). 초과는 라벨 옆의 작은 빨간
      // 글씨와 수치 색으로만 말한다.
      expect(find.text('목표 초과'), findsNothing);
      expect(find.text('정상'), findsNothing);
      // #1054 에서 짧게 줄인 문구도 함께 사라졌다.
      expect(find.text('1,428mg 많아요'), findsNothing);
      expect(find.text('32.2g 남았어요'), findsNothing);
      expect(find.textContaining('많아요'), findsNothing);
      expect(find.textContaining('남았어요'), findsNothing);
      // 라벨과 한 덩어리(Text.rich)라 리치 텍스트까지 뒤져야 잡힌다.
      expect(
        find.textContaining('+1,428mg', findRichText: true),
        findsOneWidget,
      );
      // 목표 안쪽인 당류에는 초과분 글씨가 붙지 않는다.
      expect(find.textContaining('+32.2g', findRichText: true), findsNothing);
      // 나트륨·당류는 요약 카드 안 가로 바로 들어왔다 (#1120) — 따로 뗀
      // 상태 카드와 세로 바는 없다.
      expect(find.byKey(const Key('nutrition-sodium-status')), findsNothing);
      expect(
        find.byKey(const Key('nutrition-macro-progress-나트륨')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nutrition-macro-progress-당류')),
        findsOneWidget,
      );
      Color? barColor(String label) => tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byKey(Key('nutrition-macro-progress-$label')),
              matching: find.byType(ColoredBox),
            ),
          )
          .last
          .color;
      expect(barColor('나트륨'), FigmaColors.dangerRed);
      expect(barColor('당류'), FigmaColors.statusWithinGoal);

      final Finder carbs = find.byKey(const Key('nutrition-macro-탄수화물'));
      final Finder protein = find.byKey(const Key('nutrition-macro-단백질'));
      final Finder fat = find.byKey(const Key('nutrition-macro-지방'));
      final Finder sodium = find.byKey(const Key('nutrition-macro-나트륨'));
      final Finder sugar = find.byKey(const Key('nutrition-macro-당류'));

      // 좁은 화면에서 각 항목이 겹치지 않고 세로로 쌓이는지 확인한다.
      expect(
        tester.getBottomLeft(carbs).dy,
        lessThanOrEqualTo(tester.getTopLeft(protein).dy),
      );
      expect(
        tester.getBottomLeft(protein).dy,
        lessThanOrEqualTo(tester.getTopLeft(fat).dy),
      );
      // 탄단지는 칼로리 아래, 나트륨·당류는 그 아래 — 한 카드 안에서 순서대로.
      expect(
        tester.getBottomLeft(fat).dy,
        lessThan(tester.getTopLeft(sodium).dy),
      );
      expect(
        tester.getBottomLeft(sodium).dy,
        lessThan(tester.getTopLeft(sugar).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('today diet shows API macro grams without label percentages', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        const DietRecordPage(),
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 오늘 4끼 합계 = 탄140·단79·지72g.
    expect(find.text('탄수화물'), findsOneWidget);
    expect(find.textContaining('탄수화물 45%'), findsNothing);
    expect(find.textContaining('120 / 275g'), findsOneWidget);
    expect(find.text('단백질'), findsOneWidget);
    expect(find.textContaining('단백질 17%'), findsNothing);
    expect(find.textContaining('45 / 100g'), findsOneWidget); // 단백질 45g
    expect(find.text('지방'), findsOneWidget);
    expect(find.textContaining('지방 38%'), findsNothing);
    expect(find.textContaining('45 / 55g'), findsOneWidget); // 지방 45g
    // 탄단지는 바 없이 글자만 쓴다 (#1120) — 초과 여부는 값의 색이 말한다.
    void expectMacroValueColor(String label, Color expectedColor) {
      final Text value = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(Key('nutrition-macro-$label')),
              matching: find.byType(Text),
            ),
          )
          .last;
      final TextSpan span = value.textSpan! as TextSpan;
      expect((span.children!.first as TextSpan).style?.color, expectedColor);
    }

    final Color macroValueColor = FigmaColors.statusWithinGoal.withValues(
      alpha: 0.65,
    );
    expectMacroValueColor('탄수화물', macroValueColor);
    expectMacroValueColor('단백질', macroValueColor);
    expectMacroValueColor('지방', macroValueColor);
    // 칼로리 숫자 아래에 세로로 쌓인다 — 예전처럼 가로로 늘어놓지 않는다.
    expect(
      tester.getTopLeft(find.text('탄수화물')).dy,
      lessThan(tester.getTopLeft(find.text('단백질')).dy),
    );
    expect(
      tester.getTopLeft(find.text('단백질')).dy,
      lessThan(tester.getTopLeft(find.text('지방')).dy),
    );
    expect(find.text('짬뽕'), findsOneWidget);
  });

  testWidgets('selecting a past date shows that date records', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const DietRecordPage(),
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(_PastDateDietRepository()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _selectDaysAgo(tester);

    expect(find.text('과거 식사'), findsOneWidget);
    expect(find.text('선택한 날짜의 피드백'), findsOneWidget);
    expect(find.textContaining('420'), findsWidgets);
  });

  testWidgets('seeded past meals use their registered photos', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const DietRecordPage(),
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _selectDaysAgo(tester);

    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((image) => image.assetName);
    expect(
      assets,
      containsAll(<String>[
        'assets/images/diet-oatmeal-banana.jpeg',
        'assets/images/diet-chicken-salad.jpg',
        'assets/images/diet-doenjang-rice.jpeg',
      ]),
    );
  });

  testWidgets('a past date without records shows the empty state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const DietRecordPage(),
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _selectDaysAgo(tester, 3);

    expect(find.textContaining('선택한 날짜에 기록된 식단'), findsOneWidget);
    expect(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(DietRecordPage)),
        ).dietLoadError,
      ),
      findsNothing,
    );
  });

  testWidgets('a date lookup error is not shown as an empty state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const DietRecordPage(),
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(
            _PastDateDietRepository(fail: true),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _selectDaysAgo(tester);

    expect(find.text('식단 정보를 불러오지 못했어요.'), findsOneWidget);
    expect(find.textContaining('선택한 날짜에 기록된 식단'), findsNothing);
  });

  testWidgets('나트륨과 당류는 같은 색 규칙을 쓴다 — 목표 안쪽은 브랜드 파랑 (#682, #1070)', (
    WidgetTester tester,
  ) async {
    // 목표 안쪽 값. 두 지표가 같은 카드에 나란히 놓이므로 같은 상태를 서로
    // 다른 색으로 말하면 안 된다.
    const DietDay day = DietDay(
      entries: <DietEntry>[
        DietEntry(
          id: 'ok',
          mealType: MealType.lunch,
          timeLabel: '12:00',
          foods: <FoodItem>[
            FoodItem(name: '샐러드', calories: 300, sodiumMg: 400, sugarG: 5),
          ],
          totalCalories: 300,
          sodiumMg: 400,
          sugarG: 5,
          carbsG: 20,
          proteinG: 20,
          fatG: 10,
        ),
      ],
      totalCalories: 300,
      totalSodiumMg: 400,
      totalSugarG: 5,
      macros: DietMacros(
        carbsPct: 40,
        proteinPct: 40,
        fatPct: 20,
        carbsG: 20,
        proteinG: 20,
        fatG: 10,
      ),
      aiCoachMessage: '',
    );

    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SingleChildScrollView(child: NutritionSummary(day: day)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Color barColor(String label) {
      final ColoredBox box = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byKey(Key('nutrition-macro-progress-$label')),
              matching: find.byType(ColoredBox),
            )
            .last,
      );
      return box.color;
    }

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(NutritionSummary)),
    );
    expect(
      barColor(l.dietSodium),
      barColor(l.dietSugar),
      reason: '목표 안쪽의 나트륨과 당류가 다른 색이면 안 된다',
    );
    expect(barColor(l.dietSodium), FigmaColors.statusWithinGoal);
  });

  testWidgets('목표를 넘기면 달성률이 100% 를 넘어 적힌다 (#846)', (WidgetTester tester) async {
    // 기본 목표는 2,000 kcal. 2,500 kcal 은 125% 다.
    const DietDay day = DietDay(
      entries: <DietEntry>[
        DietEntry(
          id: 'over',
          mealType: MealType.dinner,
          timeLabel: '19:00',
          foods: <FoodItem>[
            FoodItem(name: '삼겹살 정식', calories: 2500, sodiumMg: 900, sugarG: 8),
          ],
          totalCalories: 2500,
          sodiumMg: 900,
          sugarG: 8,
          carbsG: 120,
          proteinG: 90,
          fatG: 130,
        ),
      ],
      totalCalories: 2500,
      totalSodiumMg: 900,
      totalSugarG: 8,
      macros: DietMacros(
        carbsPct: 35,
        proteinPct: 25,
        fatPct: 40,
        carbsG: 120,
        proteinG: 90,
        fatG: 130,
      ),
      aiCoachMessage: '',
    );

    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SingleChildScrollView(child: NutritionSummary(day: day)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('125%'), findsOneWidget);
    expect(find.text('100%'), findsNothing, reason: '초과인데 100% 로 멈추면 안 된다');

    // 링은 1.0 을 넘으면 눈금이 깨진다. 라벨과 달리 잘린 값을 받아야 한다.
    final CircularProgressIndicator ring = tester
        .widget<CircularProgressIndicator>(
          find.byKey(const Key('nutrition-calorie-progress')),
        );
    expect(ring.value, 1.0);
  });

  testWidgets('목표 안쪽이면 달성률이 실제 비율 그대로 적힌다 (#846)', (WidgetTester tester) async {
    const DietDay day = DietDay(
      entries: <DietEntry>[
        DietEntry(
          id: 'under',
          mealType: MealType.lunch,
          timeLabel: '12:00',
          foods: <FoodItem>[
            FoodItem(name: '비빔밥', calories: 1000, sodiumMg: 800, sugarG: 6),
          ],
          totalCalories: 1000,
          sodiumMg: 800,
          sugarG: 6,
          carbsG: 60,
          proteinG: 30,
          fatG: 20,
        ),
      ],
      totalCalories: 1000,
      totalSodiumMg: 800,
      totalSugarG: 6,
      macros: DietMacros(
        carbsPct: 50,
        proteinPct: 25,
        fatPct: 25,
        carbsG: 60,
        proteinG: 30,
        fatG: 20,
      ),
      aiCoachMessage: '',
    );

    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SingleChildScrollView(child: NutritionSummary(day: day)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('50%'), findsOneWidget);
    final CircularProgressIndicator ring = tester
        .widget<CircularProgressIndicator>(
          find.byKey(const Key('nutrition-calorie-progress')),
        );
    expect(ring.value, 0.5);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

/// 전체 칼로리 막대는 탄단지의 칼로리 기여분을 색 구간으로 쌓는다 (#1479).
class _MacroRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async => _day;

  @override
  Future<DietDay> fetchToday() async => _day;

  /// 탄 200g(800kcal) · 단 100g(400kcal) · 지 40g(360kcal).
  static const DietDay _day = DietDay(
    entries: <DietEntry>[
      DietEntry(
        id: 'e',
        mealType: MealType.lunch,
        timeLabel: '12:00',
        foods: <FoodItem>[
          FoodItem(
            name: '한 끼',
            calories: 1560,
            sodiumMg: 1200,
            sugarG: 12,
            carbsG: 200,
            proteinG: 100,
            fatG: 40,
          ),
        ],
        totalCalories: 1560,
        sodiumMg: 1200,
        sugarG: 12,
        carbsG: 200,
        proteinG: 100,
        fatG: 40,
      ),
    ],
    totalCalories: 1560,
    totalSodiumMg: 1200,
    totalSugarG: 12,
    macros: DietMacros(
      carbsPct: 51,
      proteinPct: 26,
      fatPct: 23,
      carbsG: 200,
      proteinG: 100,
      fatG: 40,
    ),
    aiCoachMessage: '',
  );
}

/// 칼로리만 있고 탄단지는 모르는 날 — 실서버가 영양을 내려주지 않은 기록이다.
class _NoMacroRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async => _day;

  @override
  Future<DietDay> fetchToday() async => _day;

  static const DietDay _day = DietDay(
    entries: <DietEntry>[
      DietEntry(
        id: 'e',
        mealType: MealType.lunch,
        timeLabel: '12:00',
        foods: <FoodItem>[FoodItem(name: '한 끼', calories: 1200)],
        totalCalories: 1200,
      ),
    ],
    totalCalories: 1200,
    totalSodiumMg: 900,
    totalSugarG: 8,
    macros: DietMacros(carbsPct: 0, proteinPct: 0, fatPct: 0),
    aiCoachMessage: '',
  );
}

Widget _app({required List<Override> overrides}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DietRecordPage(),
  ),
);

void main() {
  group('DietPeriodDay 탄단지', () {
    test('탄·단은 4kcal/g, 지방은 9kcal/g 로 환산한다', () {
      final DietPeriodDay day = DietPeriodDay(
        date: _anyDate,
        calories: 1560,
        sodiumMg: 1200,
        sugarG: 12,
        carbsG: 200,
        proteinG: 100,
        fatG: 40,
      );

      expect(day.carbsKcal, 800);
      expect(day.proteinKcal, 400);
      expect(day.fatKcal, 360);
      expect(day.hasMacros, isTrue);
    });

    test('영양이 없는 날은 쌓지 않는다', () {
      final DietPeriodDay day = DietPeriodDay(
        date: _anyDate,
        calories: 1200,
        sodiumMg: 900,
        sugarG: 8,
      );

      expect(day.hasMacros, isFalse);
    });
  });

  group('이번 달 칼로리 막대 (#7)', () {
    Future<void> openMonthWith(
      WidgetTester tester,
      DietRepository repository,
    ) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(repository),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(dietPeriodTab(DietPeriodTab.month));
      await tester.pumpAndSettle();
    }

    Future<void> openMonth(WidgetTester tester) =>
        openMonthWith(tester, _MacroRepository());

    List<Color> segmentColorsOf(WidgetTester tester, int index) => tester
        .widgetList<ColoredBox>(
          find.descendant(
            of: find.byKey(Key('diet-period-bar-$index')),
            matching: find.byType(ColoredBox),
          ),
        )
        .map((ColoredBox b) => b.color)
        .toList();

    Color labelColor(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label).last).style!.color!;

    testWidgets('전체의 탄단지 라벨은 막대를 쌓은 색 그대로다 (#1479)', (
      WidgetTester tester,
    ) async {
      await openMonth(tester);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );

      // 머리 숫자 옆의 탄단지는 막대의 색 구간이 무엇인지도 함께 말한다 —
      // 그래서 라벨 색이 막대 구간 색과 같아야 한다. 이번 주에서 이 셋을
      // 보조 회색으로 죽이던 규칙은 사라졌다(#1879): 이번 주는 탄단지를
      // 지표로 직접 그려, 머리 숫자 옆에 곁들이는 자리 자체가 없다.
      expect(
        labelColor(tester, l.homeMacroCarbs),
        OnCareBrand.member.macroCarbs,
      );
      expect(
        labelColor(tester, l.homeMacroProtein),
        OnCareBrand.member.macroProtein,
      );
      expect(labelColor(tester, l.homeMacroFat), OnCareBrand.member.macroFat);
    });

    testWidgets('이번 주의 탄단지 라벨만 보조 회색을 사용한다 (#1479)', (
      WidgetTester tester,
    ) async {
      await openMonth(tester);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );

      await tester.tap(dietPeriodTab(DietPeriodTab.week));
      await tester.pumpAndSettle();

      // 이번 주는 꺾은선이라 쌓은 색 구간이 없다 — 세 라벨을 막대 색으로
      // 칠하면 어디에도 없는 색의 범례가 된다.
      expect(labelColor(tester, l.homeMacroCarbs), OnCareColors.textSecondary);
      expect(
        labelColor(tester, l.homeMacroProtein),
        OnCareColors.textSecondary,
      );
      expect(labelColor(tester, l.homeMacroFat), OnCareColors.textSecondary);
    });

    testWidgets('막대가 칸 폭을 채우고 높이를 갖는다 (#947)', (WidgetTester tester) async {
      await openMonth(tester);

      // 폭 0 으로 그려져 통째로 사라진 적이 있다(#947) — 색만 확인하면 그
      // 사라짐을 그대로 통과시킨다.
      final Rect bar = tester.getRect(
        find.byKey(const Key('diet-period-bar-0')),
      );
      expect(bar.width, greaterThan(0));
      expect(bar.height, greaterThan(0));
    });

    /// 막대 툴팁의 글자.
    String tipTextAt(WidgetTester tester, int index) =>
        _tipText(tester, find.byKey(Key('diet-period-bar-tip-$index')));

    testWidgets('전체 구간에는 아직 오지 않은 날이 없다 (#950, #1018)', (
      WidgetTester tester,
    ) async {
      await openMonth(tester);

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );
      final List<DateTime> dates = dietRangeDates(
        dietRangeForTab(DietPeriodTab.month, nowKst()),
      );

      // 전체는 오늘로 끝나는 구간이다 — 달력 달을 그리던 때와 달리 미래 칸이
      // 아예 없다. "기록할 수 없었던 날" 과 "기록하지 않은 날" 을 가르던
      // 구분(#950)은 그래서 이 화면에서 쓸 일이 없어졌다.
      expect(dates.last, DateUtils.dateOnly(nowKst()));
      for (int i = 0; i < dates.length; i++) {
        expect(
          tipTextAt(tester, i),
          isNot(contains(l.dietPeriodNotYet)),
          reason: '${dates[i]}',
        );
      }
    });

    testWidgets('막대는 탄단지 색 구간을 쌓는다 (#1479)', (WidgetTester tester) async {
      await openMonth(tester);

      expect(segmentColorsOf(tester, 0), <Color>[
        OnCareBrand.member.macroFat,
        OnCareBrand.member.macroProtein,
        OnCareBrand.member.macroCarbs,
      ]);
    });

    testWidgets('툴팁이 탄단지 수치를 함께 적는다', (WidgetTester tester) async {
      await openMonth(tester);

      final Finder tip = _tipFinder(
        // 전체는 오늘로 끝나는 구간이라 오늘은 **마지막 칸**이다 (#1018).
        find.byKey(
          Key(
            'diet-period-bar-tip-'
            '${dietRangeDates(dietRangeForTab(DietPeriodTab.month, nowKst())).length - 1}',
          ),
        ),
      );
      final String text = _tipText(tester, tip);

      expect(text, contains('탄수화물'));
      expect(text, contains('200'));
      expect(text, contains('단백질'));
      expect(text, contains('100'));
      expect(text, contains('지방'));
      expect(text, contains('40'));
    });

    testWidgets('영양을 모르는 날의 막대는 브랜드 색 한 칸이다', (WidgetTester tester) async {
      // 누적 구간은 탄단지를 아는 날만의 규칙이다. 실서버가 영양을 주지 않은
      // 날은 쌓을 것이 없어 브랜드 색 한 칸으로 그린다.
      //
      // 예전에는 나트륨 지표로 바꿔 이 규칙을 확인했는데, 전체는 칼로리 하나로
      // 고정되어(#1879) 바꿀 지표가 없다. 규칙 자체는 그대로라 대역을 바꿔
      // 같은 것을 본다.
      await openMonthWith(tester, _NoMacroRepository());

      final Container bar = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const Key('diet-period-bar-0')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (bar.decoration! as BoxDecoration).color,
        OnCareBrand.member.dietChart,
      );
    });
  });
}

final DateTime _anyDate = DateTime(2026, 8, 19);

/// 막대 툴팁의 글자 — 툴팁은 패키지 차트 툴팁 위젯을 담으므로(#1700) 같은 내용을
/// 한 줄로 적은 막대의 시맨틱 라벨을 읽는다.
String _tipText(WidgetTester tester, Finder tip) =>
    tester
        .widget<Semantics>(
          find.ancestor(of: tip, matching: find.byType(Semantics)).first,
        )
        .properties
        .label ??
    '';

Finder _tipFinder(Finder tip) => tip;

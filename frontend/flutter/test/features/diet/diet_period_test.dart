import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 짝수 날에만 기록이 있는 저장소 — 기간 평균이 **기록이 있는 날만으로**
/// 나뉘는지 확인하기 위한 대역.
class _SparseDietRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    if (date.day.isOdd) {
      return const DietDay(
        entries: <DietEntry>[],
        totalCalories: 0,
        totalSodiumMg: 0,
        totalSugarG: 0,
        macros: DietMacros.zero(),
        aiCoachMessage: '',
      );
    }
    return const DietDay(
      entries: <DietEntry>[
        DietEntry(
          id: 'e',
          mealType: MealType.lunch,
          timeLabel: '12:00',
          foods: <FoodItem>[
            FoodItem(name: '점심', calories: 600, sodiumMg: 1000, sugarG: 10),
          ],
          totalCalories: 600,
          sodiumMg: 1000,
          sugarG: 10,
          carbsG: 60,
          proteinG: 30,
          fatG: 20,
        ),
      ],
      totalCalories: 600,
      totalSodiumMg: 1000,
      totalSugarG: 10,
      macros: DietMacros(
        carbsPct: 40,
        proteinPct: 20,
        fatPct: 40,
        carbsG: 60,
        proteinG: 30,
        fatG: 20,
      ),
      aiCoachMessage: '',
    );
  }
}

Widget _app({
  List<Override> overrides = const <Override>[],
  String locale = 'ko',
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DietRecordPage(),
    ),
  );
}

/// 지난 날짜 한 칸을 고른다.
///
/// 스트립은 월요일에서 시작해 일요일로 끝나는 **한 주**만 보여 준다(#1059).
/// 고르려는 날이 이번 주 밖이면 화살표로 그 주까지 옮긴 뒤 고른다 — 날짜만
/// 두드리면 지난 날이 이번 주에 하나도 없는 **월요일마다** 깨진다.
Future<void> _tapPastDay(WidgetTester tester, int daysAgo) async {
  final DateTime now = nowKst();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime target = today.subtract(Duration(days: daysAgo));
  await _showWeekOf(tester, target);
  await tester.tap(find.text('${target.day}').first);
  await tester.pumpAndSettle();
}

/// [target] 이 든 주가 스트립에 보이도록 화살표로 옮긴다.
Future<void> _showWeekOf(WidgetTester tester, DateTime target) async {
  final DateTime now = nowKst();
  final DateTime today = DateTime(now.year, now.month, now.day);
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
}

void main() {
  // 지난 날짜를 누르는 테스트다 — 오늘이 월요일이면 스트립(이번 주 월~일)에
  // 어제가 없어 누를 칸이 사라진다. 오늘을 주 중간으로 고정한다 (#1209).
  setUp(useFixedKstDate);

  group('dietPeriodProvider', () {
    test('기간의 모든 날을 담고, 평균은 기록이 있는 날만으로 나눈다', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(_SparseDietRepository()),
        ],
      );
      addTearDown(container.dispose);

      // 2026-06-01(월) ~ 06-07(일): 짝수 날 3일(2·4·6)만 기록이 있다.
      final DietPeriod period = await container.read(
        dietPeriodProvider((
          from: DateTime(2026, 6),
          to: DateTime(2026, 6, 7),
        )).future,
      );

      expect(period.days.length, 7);
      expect(period.loggedDays, 3);
      expect(period.totalCalories, 1800);
      // 7 이 아니라 3 으로 나눈다 — 기록하지 않은 날의 0 이 평균을 끌어내리면
      // 실제로 먹은 양과 다른 숫자가 된다.
      expect(period.avgCalories, 600);
      expect(period.avgSodiumMg, 1000);
      expect(period.avgSugarG, closeTo(10, 0.001));
    });

    test('기록이 하나도 없는 기간은 비어 있다고 본다(0 으로 나누지 않는다)', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(_EmptyDietRepository()),
        ],
      );
      addTearDown(container.dispose);

      final DietPeriod period = await container.read(
        dietPeriodProvider((
          from: DateTime(2026, 6),
          to: DateTime(2026, 6, 7),
        )).future,
      );

      expect(period.isEmpty, isTrue);
      expect(period.avgCalories, 0);
    });
  });

  group('영양 요약 기간 뷰 배치 (#694)', () {
    Future<AppLocalizations> pumpWeek(WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('diet-period-tab-week')));
      await tester.pumpAndSettle();
      return AppLocalizations.of(tester.element(find.byType(DietRecordPage)));
    }

    testWidgets('지표 버튼 셋이 모두 같은 색이다', (WidgetTester tester) async {
      // 지표마다 색이 다르면 고르기 전부터 셋이 서로 다른 뜻을 가진 것처럼
      // 보인다. 버튼은 '무엇을 고르는가' 만 말해야 한다.
      final AppLocalizations l = await pumpWeek(tester);

      // 고른 것과 안 고른 것의 색이 다른 건 정상이다. 비교할 것은 **각 버튼을
      // 골랐을 때의 색** 이 셋 다 같은가다.
      final Set<Color?> activeColors = <Color?>{};
      for (final String label in <String>[
        l.dietCalories,
        l.dietSodium,
        l.dietSugar,
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        activeColors.add(tester.widget<Text>(find.text(label)).style?.color);
      }

      expect(
        activeColors,
        hasLength(1),
        reason: '지표 버튼 색이 서로 다릅니다: $activeColors',
      );
    });

    testWidgets('날짜 범위가 지표 버튼과 같은 줄에 있다', (WidgetTester tester) async {
      // 범위가 따로 한 줄을 쓰면 제목·범위·버튼 세 줄이 되어 그래프가 밀린다.
      final AppLocalizations l = await pumpWeek(tester);
      final Finder range = find.textContaining(RegExp(r'~|–|-'));

      final Finder rangeInRow = find.descendant(
        of: find.ancestor(
          of: find.text(l.dietCalories),
          matching: find.byType(Row),
        ),
        matching: range,
      );
      expect(rangeInRow, findsWidgets, reason: '날짜 범위가 지표 버튼과 다른 줄에 있습니다.');
    });
  });

  group('식단 탭 기간 토글', () {
    testWidgets('끼니 목록 제목은 날짜에 매이지 않고 어느 날 기록인지 함께 적는다 (#687)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final Element context = tester.element(find.byType(DietRecordPage));
      final AppLocalizations l = AppLocalizations.of(context);
      final MaterialLocalizations m = MaterialLocalizations.of(context);

      // 이 목록은 늘 **선택한 날**을 보여 준다. 제목이 '오늘' 을 주장하면 사흘 전을
      // 골랐을 때 거짓말이 된다 — 그게 #687 이 신고된 경로다.
      final Finder title = find.text(l.dietMealLog);
      expect(title, findsOneWidget);
      expect(l.dietMealLog.contains('오늘'), isFalse);
      expect(l.dietMealLog.toLowerCase().contains('today'), isFalse);

      // 제목 줄 안에서만 날짜를 찾는다. 화면 다른 곳의 같은 문자열을 주워 담으면
      // 이 단언이 무엇을 보장하는지 흐려진다.
      Finder dateInHeader(DateTime day) => find.descendant(
        of: find.byKey(const ValueKey<String>('meal-log-header')),
        matching: find.text(m.formatMediumDate(day)),
      );

      final DateTime now = nowKst();
      final DateTime today = DateTime(now.year, now.month, now.day);
      expect(dateInHeader(today), findsOneWidget);

      // 핵심: 다른 날을 고르면 제목 옆 날짜도 함께 움직여야 한다. 오늘만 확인하면
      // `date: _selected` 가 갱신되는지는 증명되지 않는다.
      //
      // 이틀 전을 쓰는 이유: 기록이 **없는** 지난 날짜는 끼니 목록 자체가 숨겨져
      // (`!atToday && day.entries.isEmpty`) 제목 줄이 아예 없다. 대역은 어제·이틀
      // 전까지만 기록을 준다.
      final DateTime other = today.subtract(const Duration(days: 2));
      await _showWeekOf(tester, other);
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'diet-day-${other.year}-${other.month}-${other.day}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(dateInHeader(other), findsOneWidget);
      expect(dateInHeader(today), findsNothing);
      expect(find.text(l.dietMealLog), findsOneWidget);
    });

    // 로케일도 축이다. 영어 라벨이 더 길어 같은 폭에서 먼저 넘친다 — 날짜
    // 스트립이 딱 그래서 영어에서만 넘치고 있었다(#743).
    for (final String locale in <String>['ko', 'en']) {
      testWidgets('$locale · 좁은 화면·큰 글자 배율에서 먼저 접히는 것은 날짜다 (#687 리뷰)', (
        WidgetTester tester,
      ) async {
        // 제목·날짜·추가 버튼이 한 줄이라, 폭이 좁거나 글자 배율이 크면 셋의 최소 폭
        // 합이 화면을 넘긴다. 접히는 쪽은 날짜여야 한다 — 추가 버튼이 밀려나면 끼니를
        // 넣을 수 없다.
        // 폭만 좁힌다. 높이를 넉넉히 두는 이유는 `ListView` 가 보이는 자식만 만들기
        // 때문이다 — 짧은 화면에서는 끼니 목록이 아래로 밀려 아예 그려지지 않는다.
        tester.view.physicalSize = const Size(320, 2400);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          _app(
            locale: locale,
            overrides: <Override>[
              dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
              accountRepositoryProvider.overrideWithValue(
                MockAccountRepository(),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final Element context = tester.element(find.byType(DietRecordPage));
        final AppLocalizations l = AppLocalizations.of(context);
        final DateTime now = nowKst();
        final String todayLabel = MaterialLocalizations.of(
          context,
        ).formatMediumDate(DateTime(now.year, now.month, now.day));

        final Finder header = find.byKey(
          const ValueKey<String>('meal-log-header'),
        );
        final Finder date = find.descendant(
          of: header,
          matching: find.text(todayLabel),
        );
        final Finder addButton = find.descendant(
          of: header,
          matching: find.text(l.dietAddMeal),
        );
        expect(date, findsOneWidget);
        expect(addButton, findsOneWidget);

        // 날짜는 한 줄로 접힌다.
        final Text dateText = tester.widget<Text>(date);
        expect(dateText.maxLines, 1);
        expect(dateText.overflow, TextOverflow.ellipsis);

        // 추가 버튼이 제목 줄 안에 남는다 — 밀려나면 끼니를 넣을 수 없다.
        final Rect headerRect = tester.getRect(header);
        final Rect addRect = tester.getRect(addButton);
        expect(addRect.left, greaterThanOrEqualTo(headerRect.left));
        expect(addRect.right, lessThanOrEqualTo(headerRect.right + 0.5));

        // 날짜와 추가 버튼이 겹치지 않는다. 겹치면 화면상 글자가 버튼을 파고든다.
        expect(
          tester.getRect(date).right,
          lessThanOrEqualTo(addRect.left + 0.5),
        );

        // 화면 어디에서도 넘치지 않는다. 화면 전체가 좁은 폭을 견디게 된 뒤로
        // (#739) 이 단언을 이 자리에서 그대로 쓸 수 있다.
        expect(tester.takeException(), isNull);
        expect(find.text(l.dietMealLog), findsOneWidget);
      });
    }

    testWidgets('토글은 영양 요약 섹션만 바꾸고, 날짜 스트립·끼니 목록은 남는다 (#681)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );

      // 처음에는 하루 요약.
      expect(find.byKey(const Key('nutrition-summary-card')), findsOneWidget);
      expect(find.byKey(const Key('diet-period-card')), findsNothing);
      // 제목은 기간과 무관한 '영양 요약'.
      expect(find.text(l.dietNutritionSummary), findsOneWidget);
      expect(l.dietNutritionSummary.contains('오늘'), isFalse);

      await tester.tap(find.byKey(const Key('diet-period-tab-week')));
      await tester.pumpAndSettle();

      // 요약 자리만 그래프로 바뀐다.
      expect(find.byKey(const Key('diet-period-card')), findsOneWidget);
      expect(find.byKey(const Key('nutrition-summary-card')), findsNothing);
      // 날짜 스트립과 끼니 목록은 그대로 남는다 — 운동 탭과 같은 규칙.
      expect(find.text(l.dietMealLog), findsOneWidget);
      expect(find.text(l.dietAddMeal), findsOneWidget);
      // 토글도 제목 줄에 그대로 있다.
      expect(find.byKey(const Key('diet-period-tab-month')), findsOneWidget);

      await tester.tap(find.byKey(const Key('diet-period-tab-month')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diet-period-card')), findsOneWidget);

      await tester.tap(find.byKey(const Key('diet-period-tab-day')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nutrition-summary-card')), findsOneWidget);
      expect(find.byKey(const Key('diet-period-card')), findsNothing);
    });
  });

  group('dietRangeForTab', () {
    test('이번 주는 월~일 7일이다 (일요일에도 그 주로 묶인다)', () {
      // 2026-06-07 은 일요일 → weekday 7. Duration 으로 빼면 다음 주로 샌다.
      final DietDateRange r = dietRangeForTab(
        DietPeriodTab.week,
        DateTime(2026, 6, 7),
      );
      expect(r.from, DateTime(2026, 6));
      expect(r.to, DateTime(2026, 6, 7));
      expect(dietRangeDates(r).length, 7);
    });

    test('전체는 오늘로 끝나는 12주다 — 달이 바뀌어도 앞의 기록이 남는다', () {
      // 예전에는 이번 달 1일~말일이었다. 달이 바뀌면 그 앞의 이야기가 통째로
      // 사라져서, 추세를 보려고 연 화면이 매달 1일에 비었다. (#1018)
      final DietDateRange r = dietRangeForTab(
        DietPeriodTab.month,
        DateTime(2026, 12, 15),
      );
      final List<DateTime> dates = dietRangeDates(r);
      expect(dates.length, kDietAllPeriodDays);
      expect(dates.last, DateTime(2026, 12, 15));
      expect(dates.first, DateTime(2026, 9, 23));
    });

    test('전체는 달 경계·윤년과 상관없이 늘 같은 길이다', () {
      for (final DateTime today in <DateTime>[
        DateTime(2026, 2, 10),
        DateTime(2028, 2, 10),
        DateTime(2026, 3, 15),
        DateTime(2026, 1, 2),
      ]) {
        final List<DateTime> dates = dietRangeDates(
          dietRangeForTab(DietPeriodTab.month, today),
        );
        expect(dates.length, kDietAllPeriodDays, reason: '$today');
        expect(dates.last, today, reason: '$today');
      }
    });
  });

  test('음식 배열이 비어 있으면 서버가 준 하루 합계로 떨어진다', () async {
    // 실서버 응답은 영양을 하루/끼니 단위로만 내려준다.
    final container = ProviderContainer(
      overrides: <Override>[
        dietRepositoryProvider.overrideWithValue(_DayTotalsOnlyRepository()),
      ],
    );
    addTearDown(container.dispose);

    final DietPeriod period = await container.read(
      dietPeriodProvider((
        from: DateTime(2026, 6),
        to: DateTime(2026, 6, 2),
      )).future,
    );

    expect(period.loggedDays, 2);
    expect(period.avgCalories, 500);
    expect(period.avgSodiumMg, 800);
    expect(period.avgSugarG, closeTo(9, 0.001));
  });

  group('지난 날짜에서는 기간 토글이 사라진다 (#912)', () {
    testWidgets('지난 날짜를 고르면 토글이 사라지고, 오늘로 돌아오면 고르던 기간이 살아난다', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          overrides: <Override>[
            // 어제만 비어 있고 나머지는 기록이 있다 — 주간 집계는 충분하다.
            dietRepositoryProvider.overrideWithValue(
              _EmptyYesterdayRepository(),
            ),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('diet-period-tab-week')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diet-period-card')), findsOneWidget);

      await _tapPastDay(tester, 1);

      // 운동 탭과 같은 규칙 — 오늘이 아닌 날은 그날 하루만 말한다.
      expect(
        find.byKey(const ValueKey<String>('diet-period-toggle')),
        findsNothing,
        reason: '스트립은 하루를, 그래프는 한 주를 가리키는 화면이 되면 안 된다',
      );
      expect(find.byKey(const Key('diet-period-card')), findsNothing);
      // 되돌아오는 길은 스트립의 `오늘` 버튼이다.
      expect(
        find.byKey(const ValueKey<String>('diet-today-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey<String>('diet-today-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('diet-period-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('diet-period-card')),
        findsOneWidget,
        reason: '고르던 기간(이번 주)은 상태에 남아 있어야 한다',
      );
    });

    testWidgets('하루 조회가 실패해도 오늘로 돌아올 길이 남는다', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(_FailPastRepository()),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('diet-period-tab-week')));
      await tester.pumpAndSettle();

      await _tapPastDay(tester, 1);

      expect(
        find.byKey(const ValueKey<String>('diet-today-button')),
        findsOneWidget,
      );
    });
  });

  group('이번 달 막대는 정확한 수치를 툴팁으로 말한다 (#912)', () {
    testWidgets('막대마다 날짜·지표·값을 담은 툴팁이 붙는다', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('diet-period-tab-month')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('diet-period-bar-0')), findsOneWidget);

      // 막대 하나마다 hover 영역이 하나. 개수가 어긋나면 칸과 툴팁이 밀린다.
      final int tipCount = tester
          .widgetList<Tooltip>(
            find.byWidgetPredicate(
              (Widget w) =>
                  w is Tooltip && '${w.key}'.contains('diet-period-bar-tip-'),
            ),
          )
          .length;
      expect(
        tipCount,
        dietRangeDates(dietRangeForTab(DietPeriodTab.month, nowKst())).length,
      );

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );
      // 대역은 오늘·어제·그저께에만 기록을 둔다.
      final Tooltip todayTip = tester.widget<Tooltip>(
        // 전체는 오늘로 끝나는 구간이라 오늘은 **마지막 칸**이다 (#1018).
        find.byKey(
          Key(
            'diet-period-bar-tip-'
            '${dietRangeDates(dietRangeForTab(DietPeriodTab.month, nowKst())).length - 1}',
          ),
        ),
      );
      final String text = todayTip.richMessage!.toPlainText();
      // 지표 이름과 단위가 카드 머리 숫자와 같은 말로 적혀야 한다.
      expect(text, contains(l.dietCalories));
      expect(text, contains(l.unitKcal));
      expect(text, isNot(contains(l.dietPeriodNoRecord)));
    });

    testWidgets('기록이 없는 날의 툴팁은 기록 없음이다', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          overrides: <Override>[
            // 홀수 날에는 기록이 없다 — 어느 달이든 1일은 늘 비어 있다.
            dietRepositoryProvider.overrideWithValue(_SparseDietRepository()),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('diet-period-tab-month')));
      await tester.pumpAndSettle();

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );
      // 홀수 날에 기록이 없다. 전체는 오늘로 끝나는 구간이라 0번 칸이 무슨
      // 날인지 고정돼 있지 않으므로, 비어 있는 날을 날짜로 찾는다. (#1018)
      final List<DateTime> dates = dietRangeDates(
        dietRangeForTab(DietPeriodTab.month, nowKst()),
      );
      final int emptyIndex = dates.indexWhere((DateTime d) => d.day.isOdd);
      final Tooltip empty = tester.widget<Tooltip>(
        find.byKey(Key('diet-period-bar-tip-$emptyIndex')),
      );
      expect(empty.richMessage!.toPlainText(), contains(l.dietPeriodNoRecord));
    });
  });
}

/// 어느 날짜에도 기록이 없는 저장소.
class _EmptyDietRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async => const DietDay(
    entries: <DietEntry>[],
    totalCalories: 0,
    totalSodiumMg: 0,
    totalSugarG: 0,
    macros: DietMacros.zero(),
    aiCoachMessage: '',
  );
}

/// 끼니에 음식 상세가 없고 하루 합계만 있는 저장소(실서버 페이로드 모양).
class _DayTotalsOnlyRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async => const DietDay(
    entries: <DietEntry>[
      DietEntry(
        id: 'e',
        mealType: MealType.lunch,
        timeLabel: '12:00',
        foods: <FoodItem>[],
        totalCalories: 500,
        sodiumMg: 800,
        sugarG: 9,
      ),
    ],
    totalCalories: 500,
    totalSodiumMg: 800,
    totalSugarG: 9,
    macros: DietMacros.zero(),
    aiCoachMessage: '',
  );
}

/// 어제만 비어 있는 저장소.
class _EmptyYesterdayRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    final DateTime y = nowKst().subtract(const Duration(days: 1));
    if (date.year == y.year && date.month == y.month && date.day == y.day) {
      return const DietDay(
        entries: <DietEntry>[],
        totalCalories: 0,
        totalSodiumMg: 0,
        totalSugarG: 0,
        macros: DietMacros.zero(),
        aiCoachMessage: '',
      );
    }
    return super.fetchByDate(date);
  }
}

/// 오늘이 아닌 날짜 조회가 실패하는 저장소.
class _FailPastRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    if (date.day != nowKst().day) throw StateError('boom');
    return super.fetchByDate(date);
  }
}

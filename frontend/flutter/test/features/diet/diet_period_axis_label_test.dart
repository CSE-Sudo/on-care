/// `전체` 그래프 x축의 날짜 라벨. (#1240)
///
/// 라벨은 칸(30칸 화면에서 10px 남짓)보다 넓다. 예전에는 칸 안에 앉혀 두어
/// 글자가 칸 경계에서 잘렸고, 화면에는 `666`·`77` 처럼 날짜가 아닌 값이
/// 보였다.
///
/// 라벨 글자 폭은 달에 따라 다르다 — `9/26` 은 고정 칸(52px)에 들어가지만
/// `10/23` 은 넘쳤다(#3493). 오늘 날짜에 따라 결과가 바뀌지 않도록 한 자리 월과
/// 두 자리 월 기준일을 모두 고정해 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/mock_account_repository.dart';
import '../../helpers/record_span.dart';

/// 날마다 값이 다른 저장소 — 막대가 모두 0이면 라벨만 남는 빈 그래프가 된다.
class _VaryingDietRepository extends FakeDietRepository {
  @override
  Future<DietDay> fetchByDate(DateTime date) async => _dayOf(date);

  @override
  Future<DietDay> fetchToday() async => _dayOf(nowKst());

  static DietDay _dayOf(DateTime date) => DietDay(
    entries: <DietEntry>[
      DietEntry(
        id: 'e-${date.month}-${date.day}',
        mealType: MealType.lunch,
        timeLabel: '12:00',
        foods: const <FoodItem>[],
        totalCalories: 1000 + date.day * 20,
        sodiumMg: 900,
        sugarG: 10,
        carbsG: 100,
        proteinG: 50,
        fatG: 20,
      ),
    ],
    totalCalories: 1000 + date.day * 20,
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

/// 축에 적힌 날짜 라벨들 — 빈 칸(라벨 없는 칸)은 위젯 자체가 없다.
final RegExp _dateLabel = RegExp(r'^\d{1,2}/\d{1,2}$');

List<Element> _labelElements() => find
    .byType(Text)
    .evaluate()
    .where((Element e) => _dateLabel.hasMatch((e.widget as Text).data ?? ''))
    .toList(growable: false);

/// 그래프의 가로 스크롤.
ScrollableState _chartScrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .byType(Scrollable)
          .at(
            find
                .byType(Scrollable)
                .evaluate()
                .toList()
                .indexWhere(
                  (Element e) =>
                      (e.widget as Scrollable).axis == Axis.horizontal,
                ),
          ),
    );

/// 그래프 스크롤 뷰가 화면에 보여 주는 가로 구간.
Rect _viewRect(WidgetTester tester) {
  final RenderBox viewport =
      _chartScrollable(tester).context.findRenderObject()! as RenderBox;
  return Rect.fromLTWH(
    viewport.localToGlobal(Offset.zero).dx,
    0,
    viewport.size.width,
    double.infinity,
  );
}

void main() {
  Future<void> openAll(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    await tester.pumpAndSettle();
  }

  // 2026-08-20 기준 `전체` 는 5/29 부터(라벨이 모두 한 자리 월), 2026-12-31
  // 기준은 10/9 부터다(라벨이 모두 두 자리 월).
  for (final DateTime today in <DateTime>[
    DateTime(2026, 8, 20),
    DateTime(2026, 12, 31),
  ]) {
    final String day = '${today.month}/${today.day}';

    testWidgets('축 날짜는 칸 경계에서 잘리지 않는다 — 기준일 $day', (WidgetTester tester) async {
      useFixedKstDate(today);
      await openAll(tester);

      final List<Element> labels = _labelElements();
      expect(labels, isNotEmpty);
      for (final Element e in labels) {
        final RenderParagraph p = e.renderObject! as RenderParagraph;
        final String text = (e.widget as Text).data!;
        // 한 줄로 눕고(줄바꿈 없음), 그 한 줄이 통째로 들어간다 — 예전에는
        // 칸 폭(10px 남짓)에 눌려 글자 중간에서 잘렸다.
        expect(p.didExceedMaxLines, isFalse, reason: text);
        expect(
          p.size.width,
          greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
          reason: text,
        );
      }

      // 처음 열면 오른쪽 끝(최근)이다 — 마지막 라벨이 그래프 밖으로 밀려
      // 잘리지 않는다.
      final Rect view = _viewRect(tester);
      final RenderBox last = labels.last.renderObject! as RenderBox;
      final double left = last.localToGlobal(Offset.zero).dx;
      expect(left, greaterThanOrEqualTo(view.left - 0.5));
      expect(left + last.size.width, lessThanOrEqualTo(view.right + 0.5));
    });
  }

  testWidgets('맨 왼쪽으로 밀어도 첫 날짜가 온전히 보인다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 12, 31));
    await openAll(tester);

    // 처음 열면 오른쪽 끝(최근)이다 — 과거 쪽으로 끝까지 민다.
    final Finder chart = find.byKey(const Key('diet-period-bar-0'));
    await tester.fling(
      find.byKey(const Key('diet-period-bar-83')),
      const Offset(2000, 0),
      3000,
    );
    await tester.pumpAndSettle();
    expect(chart, findsOneWidget);

    expect(_chartScrollable(tester).position.pixels, 0);
    final Rect viewRect = _viewRect(tester);

    // 왼쪽 끝 라벨이 잘려 나가지 않는다 — 칸 가운데에 맞추다 그래프 밖으로
    // 삐져나가면 스크롤 뷰가 그만큼을 잘라 낸다.
    final List<Element> labels = _labelElements();
    final RenderBox first = labels.first.renderObject! as RenderBox;
    final double left = first.localToGlobal(Offset.zero).dx;
    expect(left, greaterThanOrEqualTo(viewRect.left - 0.5));
    expect(left + first.size.width, lessThanOrEqualTo(viewRect.right + 0.5));
  });

  testWidgets('연·월이 바뀌는 구간도 실제 달력 날짜를 순서대로 적는다', (WidgetTester tester) async {
    // 2027-01-10 기준 `전체`(84일)는 2026-10-19 부터다 — 달 경계와 해 경계를
    // 모두 지난다.
    useFixedKstDate(DateTime(2027, 1, 10));
    await openAll(tester);

    expect(
      _labelElements()
          .map((Element e) => (e.widget as Text).data!)
          .toList(growable: false),
      <String>['10/19', '11/2', '11/16', '11/30', '12/14', '12/28'],
    );
  });
}

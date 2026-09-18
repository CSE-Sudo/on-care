/// 날짜 기간 줄 — 어디에, 무엇을, 어떤 형식으로 적는가.
///
/// **무엇을**: `전체` 는 지금 보이는 막대의 구간이다(#1985). 바로 아래의
/// `하루 평균` 이 이미 보이는 구간만 세므로(#1018), 날짜만 12주 전체에 머물면
/// 한 카드의 두 글이 서로 다른 기간을 말한다.
///
/// **어디에**: 카드 **안** 오른쪽 위다(#2009). 카드 밖에 두면 카드가 제
/// 기간을 스스로 말하지 않는다.
///
/// **어떤 형식으로**: 운동 탭과 같은 `periodRangeText` 로 적는다 — 같은 성격의
/// 카드가 탭마다 다른 말투로 말하지 않도록.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare/shared/widgets/period_range_label.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

Widget _app() => ProviderScope(
  overrides: <Override>[
    dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
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
  /// 카드 안 오른쪽 위의 날짜 기간 한 줄.
  String rangeLabel(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const Key('diet-period-range')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  Future<void> open(WidgetTester tester, DietPeriodTab tab) async {
    // 기간의 양끝이 오늘에 매여 있다 — 고정하지 않으면 기대값이 달력을 탄다.
    useFixedKstDate();

    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(tab));
    await tester.pumpAndSettle();
  }

  testWidgets('전체를 밀면 상단 날짜가 보이는 구간을 따라간다', (WidgetTester tester) async {
    await open(tester, DietPeriodTab.month);

    final DietDateRange whole = dietRangeForTab(DietPeriodTab.month, nowKst());
    final String wholeText = periodRangeText('ko', whole.from, whole.to);

    // 오른쪽 끝(오늘)에서 시작한다 — 끝 날짜는 기간의 끝이지만 시작 날짜는
    // 12주 전이 아니라 한 화면 앞이다.
    final String atEnd = rangeLabel(tester);
    expect(atEnd, endsWith(wholeText.split(' ~ ').last));
    expect(atEnd, isNot(wholeText), reason: '오른쪽 끝에 붙어 있는데 날짜 줄이 12주 전체를 가리킨다');

    // 왼쪽(과거)으로 민다.
    final Finder horizontal = find
        .descendant(
          of: find.byKey(const Key('diet-period-card')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(horizontal, const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(rangeLabel(tester), isNot(atEnd), reason: '그래프를 밀었는데 상단 날짜가 그대로다');
  });

  testWidgets('날짜 줄은 카드 안 오른쪽 위, 탄단지 바로 위에 있다', (WidgetTester tester) async {
    await open(tester, DietPeriodTab.week);

    final Rect label = tester.getRect(
      find.byKey(const Key('diet-period-range')),
    );
    final Rect card = tester.getRect(find.byKey(const Key('diet-period-card')));
    final Rect macros = tester.getRect(
      find.byKey(const Key('diet-period-macros')),
    );
    final Rect caption = tester.getRect(
      find.textContaining(
        AppLocalizations.of(
          tester.element(find.byType(DietRecordPage)),
        ).dietPeriodAverage,
      ),
    );

    // 카드 **안**이다 — 카드 위에 뜬 줄이 아니다.
    expect(card.contains(label.topLeft), isTrue, reason: '날짜 줄이 카드 밖에 있다');
    expect(card.contains(label.bottomRight), isTrue);
    // 오른쪽 — 카드 안쪽 여백까지 폭을 쓴다.
    expect(
      label.right,
      moreOrLessEquals(card.right - OnCareSpacing.cardPadding, epsilon: 1),
      reason: '날짜 줄이 카드 오른쪽 끝에 붙지 않았다',
    );
    // 탄단지 **바로 위**다 — 오른쪽 칸의 맨 위.
    expect(
      label.bottom,
      lessThanOrEqualTo(macros.top),
      reason: '날짜 줄이 탄단지 아래로 내려갔다',
    );
    // 왼쪽 머리 문구(`하루 평균 · 칼로리`)와 **같은 높이**에서 시작한다 —
    // 날짜에 제 줄을 따로 주면 그 줄 왼쪽이 통째로 빈다(#2009).
    expect(
      label.top,
      moreOrLessEquals(caption.top, epsilon: 2),
      reason: '날짜 줄이 제 줄을 따로 써서 왼쪽에 빈 줄이 생겼다',
    );
  });

  testWidgets('날을 고르면 날짜 기간이 빠진다 — 머리 문구가 그날을 말한다', (
    WidgetTester tester,
  ) async {
    // 운동 탭 `전체` 와 같다 — 막대를 고르면 머리 문구가 `평균 소모` 에서
    // `9월 3주차` 로 바뀌어 그 기간을 말하므로 날짜 기간 줄은 빠진다. 식단은
    // 머리 문구가 `2026. 9. 17. · 칼로리` 로 그날을 말하는데, 보이는 구간까지
    // 함께 적으면 한 카드에 날짜가 둘 떠 서로 다른 말을 한다.
    await open(tester, DietPeriodTab.month);
    final Finder range = find.byKey(const Key('diet-period-range'));
    final Finder bar = find.byKey(
      const Key('diet-period-bar-${kDietAllPeriodDays - 1}'),
    );
    expect(range, findsOneWidget);

    await tester.tap(bar, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(range, findsNothing, reason: '날을 골랐는데 보이는 구간이 함께 떠 있다');

    // 다시 풀면 날짜 기간이 돌아온다.
    await tester.tap(bar, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(range, findsOneWidget);
  });

  // 머리줄은 날을 고르든 말든 **같은 높이**를 쓴다 — 운동 탭 `전체` 와 같다
  // (#1194). 고르면 날짜 기간이 빠지고 회색 바탕의 여백이 붙어 두 상태의
  // 높이가 몇 dp 씩 어긋났고(72 ↔ 67~71), 카드 내용이 가운데 정렬이라 그
  // 절반만큼 그래프가 위아래로 튀었다.
  for (final DietPeriodTab tab in <DietPeriodTab>[
    DietPeriodTab.week,
    DietPeriodTab.month,
  ]) {
    testWidgets('날을 고르고 풀어도 그래프가 움직이지 않는다 — $tab', (WidgetTester tester) async {
      await open(tester, tab);
      final bool weekly = tab == DietPeriodTab.week;
      final Finder card = find.byKey(const Key('diet-period-card'));
      final Finder chart = weekly
          ? find.byType(MetricTrendChart)
          : find.byType(PeriodScrollChart);
      final Finder head = find.byType(PeriodChartHeadline);
      double chartTop() => tester.getRect(chart).top - tester.getRect(card).top;

      final double cardBefore = tester.getSize(card).height;
      final double headBefore = tester.getSize(head).height;
      final double chartBefore = chartTop();

      // 이번 주는 월요일 점, 전체는 오늘 막대를 고른다.
      if (weekly) {
        final Rect paint = tester.getRect(
          find
              .descendant(
                of: find.byType(MetricTrendChart),
                matching: find.byType(CustomPaint),
              )
              .first,
        );
        await tester.tapAt(Offset(paint.left + 2, paint.center.dy));
      } else {
        await tester.tap(
          find.byKey(const Key('diet-period-bar-${kDietAllPeriodDays - 1}')),
          warnIfMissed: false,
        );
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('diet-period-range')),
        findsNothing,
        reason: '날이 골라지지 않아 이 테스트가 두 상태를 견주지 못한다',
      );

      expect(tester.getSize(card).height, cardBefore, reason: '카드가 커졌다');
      expect(tester.getSize(head).height, headBefore, reason: '머리줄 높이가 바뀌었다');
      expect(
        chartTop(),
        moreOrLessEquals(chartBefore, epsilon: 0.5),
        reason: '날을 고르자 그래프가 밀렸다',
      );
    });
  }

  testWidgets('운동 탭과 같은 형식으로 적는다', (WidgetTester tester) async {
    // 같은 성격의 카드가 탭마다 다른 말투로 말하지 않도록 두 탭이
    // `periodRangeText` 하나를 함께 쓴다.
    await open(tester, DietPeriodTab.week);

    final DietDateRange whole = dietRangeForTab(DietPeriodTab.week, nowKst());
    expect(rangeLabel(tester), periodRangeText('ko', whole.from, whole.to));
  });

  testWidgets('이번 주는 한 화면에 다 들어가므로 월~일 그대로다', (WidgetTester tester) async {
    await open(tester, DietPeriodTab.week);

    final DietDateRange whole = dietRangeForTab(DietPeriodTab.week, nowKst());

    expect(rangeLabel(tester), periodRangeText('ko', whole.from, whole.to));
  });
}

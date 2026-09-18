/// `전체` 카드 머리의 날짜 기간은 **지금 보이는 막대의 구간**을 가리킨다
/// (#1985).
///
/// 같은 줄의 `하루 평균` 은 이미 보이는 구간만 센다(#1018). 날짜만 12주 전체에
/// 머물면 한 화면의 두 글이 서로 다른 기간을 말한다 — 운동 탭 `전체` 가 이미
/// `_selection.visible` 로 구간을 적는 방식과 맞춘다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

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
  /// 카드 머리 오른쪽의 날짜 기간 한 줄.
  String rangeLabel(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('diet-period-range'))).data!;

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

    final DateFormat fmt = DateFormat.MMMd('ko');
    final DietDateRange whole = dietRangeForTab(DietPeriodTab.month, nowKst());

    // 오른쪽 끝(오늘)에서 시작한다 — 끝 날짜는 기간의 끝이지만 시작 날짜는
    // 12주 전이 아니라 한 화면 앞이다.
    final String atEnd = rangeLabel(tester);
    expect(atEnd, endsWith(fmt.format(whole.to)));
    expect(
      atEnd,
      isNot(startsWith(fmt.format(whole.from))),
      reason: '오른쪽 끝에 붙어 있는데 상단이 12주 전체를 가리킨다',
    );

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

  testWidgets('날짜 줄은 오른쪽에 붙는다', (WidgetTester tester) async {
    // 칩과 한 줄을 쓰던 시절에는 `Expanded` 가 남는 자리를 줘서 오른쪽에
    // 붙었다. 칩이 빠지며(#1986) 그 `Expanded` 도 사라져 글자 폭만큼만
    // 차지하고 왼쪽으로 갔다 — `textAlign` 은 제 폭 안에서만 도는 규칙이라
    // 그것만으로는 오른쪽에 붙지 않는다.
    await open(tester, DietPeriodTab.week);

    final Rect label = tester.getRect(
      find.byKey(const Key('diet-period-range')),
    );
    final Rect card = tester.getRect(find.byKey(const Key('diet-period-card')));
    expect(
      label.right,
      moreOrLessEquals(card.right, epsilon: 1),
      reason: '날짜 줄의 오른쪽 끝이 카드의 오른쪽 끝과 맞지 않는다',
    );
    expect(
      label.left,
      lessThan(card.left + 1),
      reason: '날짜 줄이 폭을 끝까지 쓰지 않아 textAlign 이 돌 자리가 없다',
    );
  });

  testWidgets('이번 주는 한 화면에 다 들어가므로 월~일 그대로다', (WidgetTester tester) async {
    await open(tester, DietPeriodTab.week);

    final DateFormat fmt = DateFormat.MMMd('ko');
    final DietDateRange whole = dietRangeForTab(DietPeriodTab.week, nowKst());

    expect(
      rangeLabel(tester),
      '${fmt.format(whole.from)} ~ ${fmt.format(whole.to)}',
    );
  });
}

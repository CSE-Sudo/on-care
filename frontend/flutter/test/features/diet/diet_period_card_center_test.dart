/// 이번 주 / 전체 카드의 그래프는 카드를 채우고, 남는 자리는 위아래로 나눈다
/// (#1956).
///
/// 카드 높이는 오늘 카드에 맞춰 고정돼 있는데(#1124) 그래프 높이가 카드가
/// 240 이던 시절 값에 묶여 있어, 그 뒤 카드가 284 로 오르는 동안 늘어난 만큼이
/// 전부 카드 아래 빈 칸으로 남았다. 그래프 높이를 카드 높이에서 끌어내고
/// 남는 몇 dp 는 가운데 정렬이 위아래로 나눈다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

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

/// 카드 위쪽에 머리 숫자까지 남은 자리와, 그래프 아래에서 카드 끝까지 남은
/// 자리. 카드 안쪽 여백(16)이 기본이고 그 위에 얹히는 것이 빈 칸이다.
(double, double) _gaps(WidgetTester tester, Finder chart) {
  final Rect card = tester.getRect(find.byKey(const Key('diet-period-card')));
  final Rect head = tester.getRect(find.byType(PeriodChartHeadline));
  final Rect graph = tester.getRect(chart);
  return (head.top - card.top, card.bottom - graph.bottom);
}

/// 카드 안쪽 여백 위에 더 얹혀도 되는 빈 칸. 글자 지표가 조금 달라도(로컬과
/// CI 의 Flutter 판이 다르다) 통과하도록 둔 여유다 — 56dp 씩 비어 있던 예전
/// 배치는 이 선을 한참 넘는다.
const double _slack = 8;

void main() {
  testWidgets('이번 주·전체 카드 그래프가 카드를 채우고 가운데에 놓인다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();
    final (double weekTop, double weekBottom) = _gaps(
      tester,
      find.byType(MetricTrendChart),
    );
    expect(
      weekBottom,
      lessThan(OnCareSpacing.cardPadding + _slack),
      reason: '이번 주 그래프 아래에 빈 칸이 남는다',
    );
    expect(
      weekTop,
      moreOrLessEquals(weekBottom, epsilon: 1),
      reason: '이번 주 카드 내용이 가운데가 아니다',
    );

    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    await tester.pumpAndSettle();
    final (double allTop, double allBottom) = _gaps(
      tester,
      find.byType(PeriodScrollChart),
    );
    expect(
      allBottom,
      lessThan(OnCareSpacing.cardPadding + _slack),
      reason: '전체 그래프 아래에 빈 칸이 남는다',
    );
    expect(
      allTop,
      moreOrLessEquals(allBottom, epsilon: 1),
      reason: '전체 카드 내용이 가운데가 아니다',
    );
  });
}

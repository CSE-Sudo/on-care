/// 이번 주 / 전체 카드의 내용은 카드 높이 안에서 세로 가운데다 (#1956).
///
/// 카드 높이는 오늘 카드에 맞춰 고정돼 있는데(#1124) 이 두 기간은 내용이 그보다
/// 짧다. 위에서부터 채우면 남는 자리가 전부 카드 아래로 몰려 그래프가 위로
/// 쏠려 보였다.
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

/// 카드 위 여백과 아래 여백. 둘이 같으면 내용이 가운데다.
(double, double) _gaps(WidgetTester tester) {
  final Rect card = tester.getRect(find.byKey(const Key('diet-period-card')));
  final Rect content = tester.getRect(
    find.byKey(const Key('diet-period-card-content')),
  );
  return (content.top - card.top, card.bottom - content.bottom);
}

void main() {
  testWidgets('이번 주·전체 카드 내용이 세로 가운데에 놓인다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();
    final (double weekTop, double weekBottom) = _gaps(tester);
    expect(
      weekTop,
      moreOrLessEquals(weekBottom, epsilon: 0.5),
      reason: '이번 주 카드 내용이 가운데가 아니다',
    );

    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    await tester.pumpAndSettle();
    final (double allTop, double allBottom) = _gaps(tester);
    expect(
      allTop,
      moreOrLessEquals(allBottom, epsilon: 0.5),
      reason: '전체 카드 내용이 가운데가 아니다',
    );
  });
}

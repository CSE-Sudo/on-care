/// 오늘 / 이번 주 / 전체 세 화면의 영양 요약 카드는 같은 높이다 (#1124).
///
/// 기간 토글을 누를 때 카드가 커졌다 작아지면 그 아래 내용이 그때마다 뛴다.
///
/// 셋이 맞춰지는 값([kDietSummaryCardHeight])은 **가장 키가 큰 카드(오늘)** 의
/// 실제 내용 높이를 재서 4 격자로 올린 것이다. 그 내용이 바뀌면 다시 재야
/// 한다 — 나트륨 진행바가 붙을 때 올렸고(#1879), 그 줄이 빠지며 다시 내렸다
/// (#1986). 셋이 서로 같기만 하면 상수가 근거 없이 높아도 통과하므로, 값을
/// 함께 못박아 그때 다시 재도록 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_period_view.dart';
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

void main() {
  testWidgets('기간 토글을 눌러도 요약 카드 높이가 그대로다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final double today = tester
        .getSize(find.byKey(const Key('nutrition-summary-card')))
        .height;

    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();
    final double week = tester
        .getSize(find.byKey(const Key('diet-period-card')))
        .height;

    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    await tester.pumpAndSettle();
    final double all = tester
        .getSize(find.byKey(const Key('diet-period-card')))
        .height;

    expect(week, today, reason: '이번 주 카드가 오늘 카드와 높이가 다르다');
    expect(all, today, reason: '전체 카드가 오늘 카드와 높이가 다르다');
    // 390 폭·배율 1.0 에서 오늘 카드 내용은 213.2 다. 4 격자의 다음 값이
    // 216 이고, 셋이 거기에 맞춰진다.
    expect(
      today,
      kDietSummaryCardHeight,
      reason: '오늘 카드가 기준 높이를 넘겼다 — 내용을 다시 재서 상수를 맞춰야 한다',
    );
    expect(kDietSummaryCardHeight, 216);
  });
}

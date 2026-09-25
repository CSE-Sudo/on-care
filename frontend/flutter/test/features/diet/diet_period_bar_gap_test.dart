/// `전체` 막대는 서로 붙어 보이지 않게 띄우되, 그 여유를 막대에서 깎지 않는다.
///
/// 한 화면에 30칸을 둔 채로 벌리면 그 여유가 전부 막대 두께에서 깎인다. 칸 수를
/// 줄여 자리를 만들어야 간격만 벌어진다 — 이 테스트가 지키는 것은 **막대 두께가
/// 예전(한 화면 30칸·양옆 hairline)보다 얇아지지 않는다** 는 것이다.
///
/// 기준 폭(375)에서 잰다. 칸 수가 상수라 막대 두께는 폭을 따라가므로, 더 좁은
/// 기기에서는 예전보다 조금 얇아질 수 있다 — 거기까지 지키려면 칸 수를 폭에서
/// 구해야 하는데, 그러면 `하루 평균`의 구간이 기기마다 달라진다(#1018).
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
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/record_span.dart';

Widget _app() => ProviderScope(
  overrides: <Override>[
    testRecordSpanOverride(),
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
  testWidgets('막대는 예전 두께 그대로이고 사이만 벌어진다', (WidgetTester tester) async {
    useFixedKstDate();
    // 회원 앱의 기준 폭.
    tester.view.physicalSize = const Size(375, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(DietPeriodTab.month));
    await tester.pumpAndSettle();

    // 화면에 올라온 첫 막대와 그 이웃.
    int? first;
    for (int i = 0; i < kTestAllPeriodDays; i++) {
      if (find.byKey(Key('diet-period-bar-$i')).evaluate().isNotEmpty) {
        first = i;
        break;
      }
    }
    expect(first, isNotNull, reason: '전체 막대가 하나도 그려지지 않았다');

    Finder bar(int i) => find.byKey(Key('diet-period-bar-$i'));
    final double width = tester.getSize(bar(first!)).width;
    final double pitch =
        tester.getTopLeft(bar(first + 1)).dx - tester.getTopLeft(bar(first)).dx;

    // 예전 폭: 목표치 칸을 뺀 자리를 30칸으로 나누고 양옆 hairline 을 뺀 값.
    const double axis = chartGoalAxisWidth + chartGoalAxisGap;
    final double inner =
        tester.getSize(find.byKey(const Key('diet-period-card'))).width -
        OnCareSpacing.s20 * 2 -
        axis;
    final double before = inner / 30 - OnCareSize.hairline * 2;

    expect(
      width,
      greaterThanOrEqualTo(before),
      reason: '간격을 벌린 만큼 막대가 깎였다 (예전 $before, 지금 $width)',
    );
    expect(
      pitch - width,
      closeTo(OnCareSpacing.s2 * 2, 0.01),
      reason: '막대 사이가 벌어지지 않았다',
    );
  });
}

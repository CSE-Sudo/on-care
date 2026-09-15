/// 섹션 아이콘 · 기간 버튼 폭 · 전체 그래프 등장 모션 (#1058).
///
/// 트레이너웹 고객 탭의 `영양 요약`·`운동 현황` 은 이미 아이콘을 달고 있다.
/// 회원 앱만 글자만 있으면 두 화면이 같은 것을 말하는지 한눈에 붙지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

void main() {
  Future<void> pumpDiet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('영양 요약 제목에 아이콘이 붙는다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final AppSectionHeader title = tester.widget<AppSectionHeader>(
      find.byType(AppSectionHeader).first,
    );
    // 트레이너웹 고객 식단이 쓰는 아이콘과 같은 모양이다.
    expect(title.icon, AppIcons.diet);
    expect(find.text(title.title), findsWidgets);
  });

  testWidgets('기간 버튼은 글자보다 넉넉하다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final Rect button = tester.getRect(dietPeriodTab(DietPeriodTab.day));
    final Rect label = tester.getRect(
      find.descendant(
        of: dietPeriodTab(DietPeriodTab.day),
        matching: find.byType(Text),
      ),
    );
    // 누를 자리가 글자에 딱 붙어 빠듯했다 — 패키지 세그먼트의 좌우 여백만큼
    // 여유가 있다(#1700).
    expect(
      button.width - label.width,
      greaterThanOrEqualTo(OnCareSpacing.s12 * 2),
    );
  });

  testWidgets('전체 그래프의 막대는 바닥에서 자라 오른다', (WidgetTester tester) async {
    await pumpDiet(tester);
    await tester.tap(dietPeriodTab(DietPeriodTab.month));

    // 전체는 오늘로 끝나는 구간이고 그래프는 끝으로 스크롤돼 열린다 —
    // 화면에 실제로 있는 마지막 칸을 본다.
    final Key today = ValueKey<String>(
      'period-bar-reveal-'
      '${dietRangeDates(dietRangeForTab(DietPeriodTab.month, nowKst())).length - 1}',
    );

    // 기간을 바꾸면 값을 다시 읽어 오므로, 막대가 나타날 때까지 프레임을
    // 흘린 뒤 첫 모습을 잰다.
    for (int i = 0; i < 20 && find.byKey(today).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final double early = tester.getRect(find.byKey(today)).height;

    await tester.pumpAndSettle();
    final double settled = tester.getRect(find.byKey(today)).height;

    expect(settled, greaterThan(0));
    expect(early, lessThan(settled));
  });
}

/// 식단 탭 제목 줄의 끝 요소가 오른쪽 끝에 붙는지 (#761).
///
/// 기간 토글·끼니 카드 화살표·`추가` 버튼은 모두 `Row` 의 마지막 요소인데,
/// 앞 요소를 `Expanded`/`Spacer` 로 늘려 두면 접히는 자식이 배정받은 폭을 다
/// 쓰지 않은 만큼이 **줄 끝에 빈 자리로 쌓여** 끝 요소가 가운데로 당겨졌다.
///
/// **넓은 폭에서 잰다.** 남는 폭이 클수록 어긋남이 커지고, 폭 390 에서는 토글이
/// 우연히 거의 붙어 보였다(361 vs 366). 320px 회귀 테스트(`diet_narrow_layout_test`)
/// 로는 이 문제를 잡을 수 없다 — 그쪽은 넘침만 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';

void main() {
  group('식단 탭 제목 줄 오른쪽 정렬 (#761)', () {
    Future<void> pumpPage(WidgetTester tester) async {
      // 폭 상한(720)보다 넓게 잡아, 카드가 화면 가운데에 놓인 상태에서 잰다.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
            accountRepositoryProvider.overrideWithValue(
              MockAccountRepository(),
            ),
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

    testWidgets('기간 토글은 영양 요약 제목 줄의 오른쪽 끝에 붙는다', (WidgetTester tester) async {
      await pumpPage(tester);

      final Finder header = find.byKey(
        const ValueKey<String>('nutrition-section-header'),
      );
      final Finder toggle = find.byKey(
        const ValueKey<String>('diet-period-toggle'),
      );
      expect(header, findsOneWidget);
      expect(toggle, findsOneWidget);

      // 줄의 오른쪽 끝 = 토글의 오른쪽 끝. 제목이 짧아도 토글이 왼쪽으로
      // 딸려 오면 안 된다.
      expect(
        tester.getRect(toggle).right,
        moreOrLessEquals(tester.getRect(header).right, epsilon: 0.5),
      );
      // 제목은 여전히 줄 왼쪽에 있다 — 둘이 가운데로 몰리지 않는다.
      // 제목 왼쪽에는 이제 아이콘이 붙으므로 제목 묶음 전체로 잰다. (#1058)
      expect(
        tester.getRect(find.byType(AppSectionHeader).first).left,
        moreOrLessEquals(tester.getRect(header).left, epsilon: 0.5),
      );
    });

    testWidgets('기간을 이번 주로 바꿔도 토글은 오른쪽 끝에 남는다', (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(dietPeriodTab(DietPeriodTab.week));
      await tester.pumpAndSettle();

      expect(
        tester
            .getRect(find.byKey(const ValueKey<String>('diet-period-toggle')))
            .right,
        moreOrLessEquals(
          tester
              .getRect(
                find.byKey(const ValueKey<String>('nutrition-section-header')),
              )
              .right,
          epsilon: 0.5,
        ),
      );
    });

    // 아이콘은 연필에서 `>` 로 되돌아갔다(#1848) — 붙는 자리는 그대로다.
    testWidgets('끼니 카드 화살표는 카드 오른쪽 끝에 붙는다', (WidgetTester tester) async {
      await pumpPage(tester);

      final Finder headers = find.byKey(
        const ValueKey<String>('meal-card-header'),
      );
      expect(headers, findsWidgets);

      for (int i = 0; i < headers.evaluate().length; i++) {
        final Finder header = headers.at(i);
        final Finder arrow = find.descendant(
          of: header,
          matching: find.byIcon(AppIcons.chevronRight),
        );
        expect(arrow, findsOneWidget);
        expect(
          tester.getRect(arrow).right,
          moreOrLessEquals(tester.getRect(header).right, epsilon: 0.5),
          reason: '$i 번째 끼니 카드의 화살표가 카드 오른쪽 끝에 붙지 않았다',
        );
      }
    });

    testWidgets('끼니 카드 제목 줄은 합계 칼로리를 되풀이하지 않는다', (WidgetTester tester) async {
      await pumpPage(tester);

      // 대역의 아침 끼니는 217 kcal 이다. 이 값은 카드 안에서 **총량 배지
      // 한 곳에만** 나온다 — 제목 줄에도 있으면 같은 숫자가 두 번 읽힌다.
      // 배지는 `Text.rich` 라 `findRichText` 를 켜야 잡힌다.
      expect(find.textContaining('217 kcal', findRichText: true), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('meal-card-header')).first,
          matching: find.textContaining('kcal', findRichText: true),
        ),
        findsNothing,
      );
    });

    testWidgets('끼니 목록의 추가 버튼은 제목 줄 오른쪽 끝에 붙는다', (WidgetTester tester) async {
      await pumpPage(tester);

      final Finder header = find.byKey(
        const ValueKey<String>('meal-log-header'),
      );
      final Finder addButton = find.descendant(
        of: header,
        matching: find.byType(GestureDetector),
      );
      expect(addButton, findsOneWidget);

      expect(
        tester.getRect(addButton).right,
        moreOrLessEquals(tester.getRect(header).right, epsilon: 0.5),
      );
    });
  });
}

/// 나트륨은 그래프에서 내려가고, 말로 남는다 (#1986).
///
/// 회의 결정은 나트륨을 **당류와 같은 자리**로 내리는 것이었다 — 그래프로
/// 시각화하지 않고 AI 맞춤 조언이 말로 알려 준다. 화면에서 내리는 것과 제품에서
/// 없애는 것은 다른 일이라, 두 쪽을 한 파일에서 함께 고정한다. 한쪽만 보면
/// "안 보이니 지우자" 로 근거까지 함께 사라진다.
///
/// 식단 상세와 분석 완료 시트의 나트륨 영양 행은 각각
/// `meal_card_photo_and_badges_test.dart` 와 `diet_result_macros_test.dart` 가
/// 이미 붙잡고 있다 — 거기도 당류와 같은 대접이라 이 결정에 닿지 않는다.
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
import 'package:oncare/shared/widgets/ai_advice_card.dart';

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
  Future<AppLocalizations> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(DietRecordPage)));
  }

  /// AI 맞춤 조언 카드가 실제로 적은 글.
  String advice(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(PeriodAiAdviceCard),
          matching: find.byType(Text),
        ),
      )
      .map((Text t) => t.data ?? '')
      .join(' ');

  testWidgets('오늘 카드에 나트륨 줄이 없다 — 대신 조언이 말한다', (WidgetTester tester) async {
    final AppLocalizations l = await open(tester);

    // 그래프 쪽: 탄단지 아래에 있던 나트륨 진행바가 사라졌다.
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-summary-card')),
        matching: find.textContaining(l.dietSodium, findRichText: true),
      ),
      findsNothing,
      reason: '오늘 카드에 나트륨이 남아 있다',
    );
    expect(find.byKey(const Key('nutrition-macro-progress-나트륨')), findsNothing);

    // 말 쪽: 같은 화면의 조언은 여전히 나트륨을 근거로 삼는다. 이 문장이
    // 이 결정의 핵심이다 — 화면에서 내리는 대신 조언이 말한다.
    expect(
      advice(tester),
      contains(l.dietSodium),
      reason: '나트륨을 그래프에서 내렸는데 조언도 함께 말하지 않는다',
    );
  });

  testWidgets('이번 주·전체 조언도 나트륨을 그대로 말한다', (WidgetTester tester) async {
    final AppLocalizations l = await open(tester);

    for (final DietPeriodTab tab in <DietPeriodTab>[
      DietPeriodTab.week,
      DietPeriodTab.month,
    ]) {
      await tester.tap(dietPeriodTab(tab));
      await tester.pumpAndSettle();
      expect(advice(tester), contains(l.dietSodium), reason: '$tab');
      // 기간 그래프 쪽에는 나트륨이 없다 — 지표 칩 줄째로 걷어냈다.
      expect(
        find.descendant(
          of: find.byKey(const Key('diet-period-card')),
          matching: find.textContaining(l.dietSodium, findRichText: true),
        ),
        findsNothing,
        reason: '$tab 그래프 카드에 나트륨이 남아 있다',
      );
    }
  });
}

/// 탄단지 줄이 목표 초과를 색으로 말하는지 (#891, #1166).
///
/// 바는 없어졌다 — 회원 앱처럼 값 옆에 목표를 적은 **글자 한 줄**이고, 색이 곧
/// 초과 여부다(#1166). 세 항목이 각자 판단하므로 지방만 넘긴 날은 지방 줄만
/// 빨개진다.
///
/// 회원 앱과 같은 그림을 보여 주는 것이 이 카드의 존재 이유이므로(#698),
/// 회원 화면에서 빨간 것은 트레이너 화면에서도 빨개야 한다(#690).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

void main() {
  /// [label] 줄의 **값**에 칠해진 색들. 목표(`/275g`)는 늘 흐린 회색이라
  /// 초과 여부를 말하는 것은 앞의 값 하나다.
  List<Color?> barColors(WidgetTester tester, String label) {
    final List<Color?> out = <Color?>[];
    for (final Text text in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(Key('client-nutrition-macro-$label')),
        matching: find.byType(Text),
      ),
    )) {
      for (final InlineSpan? span in <InlineSpan?>[
        text.textSpan,
        ...?(text.textSpan as TextSpan?)?.children,
      ]) {
        final Color? color = span?.style?.color;
        if (color != null) out.add(color);
      }
    }
    return out;
  }

  Future<void> pumpCard(WidgetTester tester, TrainerClient client) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: NutritionSummaryCard(client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('목표를 넘긴 항목만 빨강이 된다', (WidgetTester tester) async {
    // 지방만 초과(56 > 55). 탄수·단백질은 목표 아래.
    await pumpCard(tester, makeClient(carbsG: 120, proteinG: 45, fatG: 56));

    expect(barColors(tester, '지방'), contains(OnCareColors.danger));
    expect(
      barColors(tester, '탄수화물'),
      isNot(contains(OnCareColors.danger)),
      reason: '탄수화물은 목표 아래인데 빨강이 됐습니다.',
    );
    expect(barColors(tester, '단백질'), isNot(contains(OnCareColors.danger)));
  });

  testWidgets('목표 아래면 메인 색이다 (#1166)', (WidgetTester tester) async {
    await pumpCard(tester, makeClient(carbsG: 120, proteinG: 45, fatG: 45));

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(
        barColors(tester, label),
        // 목표 안쪽은 메인 색의 65% 농담(불투명 환산) — 탄단지 중간 단계와 같다.
        contains(OnCareBrand.trainer.macroProtein),
        reason: label,
      );
      expect(barColors(tester, label), isNot(contains(OnCareColors.danger)));
    }
  });

  testWidgets('목표와 정확히 같으면 초과가 아니다', (WidgetTester tester) async {
    // 경계는 다른 지표와 같다 — `>` 지, `>=` 가 아니다.
    await pumpCard(tester, makeClient(carbsG: 275, proteinG: 100, fatG: 55));

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(
        barColors(tester, label),
        isNot(contains(OnCareColors.danger)),
        reason: label,
      );
    }
  });

  testWidgets('세 항목이 모두 넘으면 셋 다 빨강이다', (WidgetTester tester) async {
    await pumpCard(tester, makeClient(carbsG: 300, proteinG: 140, fatG: 80));

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(
        barColors(tester, label),
        contains(OnCareColors.danger),
        reason: label,
      );
    }
  });
}

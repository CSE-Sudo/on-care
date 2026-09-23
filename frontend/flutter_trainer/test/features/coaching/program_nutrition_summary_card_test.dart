/// 프로그램 탭 `식단 - 오늘` 카드가 회원 앱 `오늘` 카드와 같은 기준인지 (#2189).
///
/// 이 칸은 회원 상세보다 좁아 회원 앱 배치(위 칼로리+도넛, 아래 탄단지 가로
/// 세 칸)를 쓴다(#1531). 구분선 아래가 나트륨·당류였고 목표는 상수였다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_nutrition_summary_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

void main() {
  Color? barColor(WidgetTester tester, String label) => tester
      .widget<AppProgressBar>(
        find.byKey(Key('client-nutrition-macro-progress-$label')),
      )
      .color;

  Future<void> pumpCard(
    WidgetTester tester,
    TrainerClient client, {
    MemberHealthProfile? profile,
    double width = 420,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ProgramNutritionSummaryCard(
                client: client,
                profile: profile,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('구분선 아래는 탄·단·지 진행 바 세 칸이고 나트륨·당류는 없다', (tester) async {
    await pumpCard(tester, makeClient(sodiumMg: 3200, sugarG: 80));

    expect(find.byType(AppProgressBar), findsNWidgets(3));
    expect(find.text('나트륨'), findsNothing);
    expect(find.text('당류'), findsNothing);
    // 회원 앱처럼 가로로 나란히 놓인다.
    final double carbs = tester
        .getTopLeft(find.byKey(const Key('client-nutrition-macro-탄수화물')))
        .dx;
    final double fat = tester
        .getTopLeft(find.byKey(const Key('client-nutrition-macro-지방')))
        .dx;
    expect(carbs, lessThan(fat));
  });

  testWidgets('좁으면 세 칸을 위아래로 쌓는다', (tester) async {
    await pumpCard(tester, makeClient(), width: 260);

    final double carbs = tester
        .getTopLeft(find.byKey(const Key('client-nutrition-macro-탄수화물')))
        .dy;
    final double fat = tester
        .getTopLeft(find.byKey(const Key('client-nutrition-macro-지방')))
        .dy;
    expect(carbs, lessThan(fat));
    expect(tester.takeException(), isNull);
  });

  testWidgets('목표는 회원 프로필에서 읽고, 빈 칸은 기본값이다', (tester) async {
    await pumpCard(
      tester,
      makeClient(calories: 1700, carbsG: 200, proteinG: 60, fatG: 50),
      profile: const MemberHealthProfile(
        memberId: 'c1',
        memberName: '테스트회원',
        dailyCalories: 1600,
        dailyCarbsG: 180,
      ),
    );

    expect(find.textContaining('/ 1,600 kcal', findRichText: true), findsOne);
    expect(barColor(tester, '탄수화물'), OnCareColors.danger);
    // 비어 있는 칸은 회원 앱 기본값 — 단백질 100g, 지방 55g.
    expect(find.textContaining('/ 100g', findRichText: true), findsOne);
    expect(find.textContaining('/ 55g', findRichText: true), findsOne);
    expect(barColor(tester, '지방'), isNot(OnCareColors.danger));
  });
}

/// 탄단지 진행 바가 목표 초과를 색으로 말하는지 (#891, #1166, #2156).
///
/// 회원 앱 `오늘` 카드처럼 탄·단·지가 **진행 바 세 줄**이다(#2156). 세 항목이
/// 각자 판단하므로 지방만 넘긴 날은 지방 바만 빨개진다. 목표는 회원의 건강
/// 프로필에서 읽고, 비어 있으면 회원 앱 기본값(275/100/55)이다.
///
/// 회원 앱과 같은 그림을 보여 주는 것이 이 카드의 존재 이유이므로(#698),
/// 회원 화면에서 빨간 것은 트레이너 화면에서도 빨개야 한다(#690).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

void main() {
  /// [label] 진행 바의 색.
  Color? barColor(WidgetTester tester, String label) => tester
      .widget<AppProgressBar>(
        find.byKey(Key('client-nutrition-macro-progress-$label')),
      )
      .color;

  /// [label] 진행 바가 채운 비율.
  double barValue(WidgetTester tester, String label) => tester
      .widget<AppProgressBar>(
        find.byKey(Key('client-nutrition-macro-progress-$label')),
      )
      .value;

  Future<void> pumpCard(
    WidgetTester tester,
    TrainerClient client, {
    MemberHealthProfile? profile,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: NutritionSummaryCard(client: client, profile: profile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('목표를 넘긴 항목만 빨강이 된다', (WidgetTester tester) async {
    // 지방만 초과(56 > 55). 탄수·단백질은 목표 아래.
    await pumpCard(tester, makeClient(carbsG: 120, proteinG: 45, fatG: 56));

    expect(barColor(tester, '지방'), OnCareColors.danger);
    expect(
      barColor(tester, '탄수화물'),
      isNot(OnCareColors.danger),
      reason: '탄수화물은 목표 아래인데 빨강이 됐습니다.',
    );
    expect(barColor(tester, '단백질'), isNot(OnCareColors.danger));
    // 넘긴 만큼은 라벨 옆에 적는다(회원 앱 #1070).
    expect(find.textContaining('+1g'), findsOneWidget);
  });

  testWidgets('목표 아래면 메인 색이다 (#1166)', (WidgetTester tester) async {
    await pumpCard(tester, makeClient(carbsG: 120, proteinG: 45, fatG: 45));

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(
        barColor(tester, label),
        OnCareBrand.trainer.statusWithinGoal,
        reason: label,
      );
    }
  });

  testWidgets('목표와 정확히 같으면 초과가 아니다', (WidgetTester tester) async {
    // 경계는 다른 지표와 같다 — `>` 지, `>=` 가 아니다.
    await pumpCard(tester, makeClient(carbsG: 275, proteinG: 100, fatG: 55));

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(
        barColor(tester, label),
        isNot(OnCareColors.danger),
        reason: label,
      );
      expect(barValue(tester, label), 1.0, reason: label);
    }
  });

  testWidgets('세 항목이 모두 넘으면 셋 다 빨강이다', (WidgetTester tester) async {
    await pumpCard(tester, makeClient(carbsG: 300, proteinG: 140, fatG: 80));

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(barColor(tester, label), OnCareColors.danger, reason: label);
    }
  });

  testWidgets('나트륨·당류 막대는 없다 — 회원 앱 #1986 (#2156)', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, makeClient(sodiumMg: 3200, sugarG: 80));

    expect(find.text('나트륨'), findsNothing);
    expect(find.text('당류'), findsNothing);
    expect(find.byType(AppProgressBar), findsNWidgets(3));
  });

  testWidgets('목표는 회원 프로필에서 읽는다 (#2156)', (WidgetTester tester) async {
    // 기본값(275/100/55, 2,000kcal)으로는 모두 안쪽인 하루가, 회원이 낮춰 둔
    // 목표로는 초과다 — 회원 앱에서 빨간 날이 트레이너 화면에서도 빨개야 한다.
    await pumpCard(
      tester,
      makeClient(calories: 1700, carbsG: 200, proteinG: 60, fatG: 50),
      profile: const MemberHealthProfile(
        memberId: 'c1',
        memberName: '테스트회원',
        dailyCalories: 1600,
        dailyCarbsG: 180,
        dailyFatG: 40,
      ),
    );

    expect(find.textContaining('/ 1,600 kcal'), findsOneWidget);
    expect(barColor(tester, '탄수화물'), OnCareColors.danger);
    expect(barColor(tester, '지방'), OnCareColors.danger);
    // 비어 있는 칸(단백질)은 회원 앱 기본값 100g 이다.
    expect(find.textContaining('/ 100g'), findsOneWidget);
    expect(barColor(tester, '단백질'), isNot(OnCareColors.danger));
  });
}

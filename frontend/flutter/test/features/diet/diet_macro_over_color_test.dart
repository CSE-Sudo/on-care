/// 탄단지가 목표 초과를 색으로 말하는지 (#890).
///
/// 탄단지는 카드 머리에서 글자만으로 적는다(#1120) — 바가 없으니 **값의 색**이
/// 초과를 말한다. 넘긴 항목은 빨강, 그 외는 브랜드 파랑이다. 같은 카드의
/// 칼로리와 아래의 나트륨·당류 바도 같은 규칙을 쓴다.
///
/// 달성률·칼로리 링은 이 파일의 관심사가 아니다 — 탄단지 색만 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';

/// 탄단지를 원하는 값으로 고정해 돌려주는 대역. 기본 목표는 275/100/55g 이다.
class _MacroDietRepository extends FakeDietRepository {
  _MacroDietRepository({
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
  });

  final double carbsG;
  final double proteinG;
  final double fatG;

  @override
  Future<DietDay> fetchToday() async => DietDay(
    entries: <DietEntry>[
      DietEntry(
        id: 'macro-meal',
        mealType: MealType.lunch,
        timeLabel: '12:00',
        foods: const <FoodItem>[FoodItem(name: '한 끼', calories: 600)],
        totalCalories: 600,
        sodiumMg: 300,
        sugarG: 5,
        carbsG: carbsG,
        proteinG: proteinG,
        fatG: fatG,
      ),
    ],
    totalCalories: 600,
    totalSodiumMg: 300,
    totalSugarG: 5,
    macros: DietMacros(
      carbsPct: 50,
      proteinPct: 25,
      fatPct: 25,
      carbsG: carbsG,
      proteinG: proteinG,
      fatG: fatG,
    ),
    aiCoachMessage: '',
  );

  @override
  Future<DietDay> fetchByDate(DateTime date) => fetchToday();
}

void main() {
  /// [label] 줄의 **값**에 칠해진 색.
  Color? barColor(WidgetTester tester, String label) {
    final Text value = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key('nutrition-macro-$label')),
            matching: find.byType(Text),
          ),
        )
        .last;
    final TextSpan span = value.textSpan! as TextSpan;
    return (span.children!.first as TextSpan).style?.color;
  }

  Future<void> pumpDiet(
    WidgetTester tester, {
    required double carbsG,
    required double proteinG,
    required double fatG,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dietRepositoryProvider.overrideWithValue(
            _MacroDietRepository(
              carbsG: carbsG,
              proteinG: proteinG,
              fatG: fatG,
            ),
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

  testWidgets('목표를 넘긴 항목만 빨강이 된다', (WidgetTester tester) async {
    // 지방만 초과(56 > 55). 탄수·단백질은 목표 아래.
    await pumpDiet(tester, carbsG: 120, proteinG: 45, fatG: 56);

    expect(barColor(tester, '지방'), OnCareColors.danger);
    expect(
      barColor(tester, '탄수화물'),
      OnCareBrand.member.macroProtein,
      reason: '탄수화물은 목표 아래인데 빨강이 됐습니다.',
    );
    expect(barColor(tester, '단백질'), OnCareBrand.member.macroProtein);
  });

  testWidgets('목표 아래면 브랜드 파랑이다 (#1070)', (WidgetTester tester) async {
    await pumpDiet(tester, carbsG: 120, proteinG: 45, fatG: 45);

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(
        barColor(tester, label),
        OnCareBrand.member.macroProtein,
        reason: label,
      );
    }
  });

  testWidgets('목표와 정확히 같으면 초과가 아니다', (WidgetTester tester) async {
    // 경계는 다른 지표와 같다 — `>` 지, `>=` 가 아니다.
    await pumpDiet(tester, carbsG: 275, proteinG: 100, fatG: 55);

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(
        barColor(tester, label),
        OnCareBrand.member.macroProtein,
        reason: label,
      );
    }
  });

  testWidgets('세 항목이 모두 넘으면 셋 다 빨강이다', (WidgetTester tester) async {
    await pumpDiet(tester, carbsG: 300, proteinG: 140, fatG: 80);

    for (final String label in <String>['탄수화물', '단백질', '지방']) {
      expect(barColor(tester, label), OnCareColors.danger, reason: label);
    }
  });
}

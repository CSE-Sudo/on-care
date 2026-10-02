/// 목표 미설정 기본값이 원본 표와 같다(#2906).
///
/// 두 앱이 읽는 `kGoalDefault…` 는 이 패키지 한 곳에만 있고, 서버
/// (`app/services/goal_defaults.py`)와는 원본 표
/// `shared/oncare_rules/vectors/goal_defaults.json` 으로 대조한다. 서버 pytest 도
/// 같은 파일을 읽으므로 원본을 바꾸면 어긋난 쪽이 깨진다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Map<String, Object?> _original() =>
    (jsonDecode(
              File(
                '../oncare_rules/vectors/goal_defaults.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>)
        ..remove('_comment');

void main() {
  final Map<String, Object?> original = _original();

  final Map<String, num> constants = <String, num>{
    'daily_calories': kGoalDefaultDailyCalories,
    'daily_sodium_mg': kGoalDefaultDailySodiumMg,
    'daily_sugar_g': kGoalDefaultDailySugarG,
    'daily_carbs_g': kGoalDefaultDailyCarbsG,
    'daily_protein_g': kGoalDefaultDailyProteinG,
    'protein_g_per_kg': kGoalDefaultProteinGPerKg,
    'daily_fat_g': kGoalDefaultDailyFatG,
    'daily_burn_kcal': kGoalDefaultDailyBurnKcal,
    'weekly_cardio_minutes': kGoalDefaultWeeklyCardioMinutes,
    'weekly_strength_sets': kGoalDefaultWeeklyStrengthSets,
    'weekly_flexibility_minutes': kGoalDefaultWeeklyFlexibilityMinutes,
  };

  test('원본 표의 값마다 공용 상수가 하나씩 있다', () {
    expect(constants.keys.toSet(), original.keys.toSet());
  });

  for (final MapEntry<String, num> e in constants.entries) {
    test('${e.key} 가 원본 표와 같다', () {
      expect(e.value, original[e.key]);
    });
  }

  test('기본 정보가 모자라 물러선 권장값은 기본 칼로리에서 시작한다', () {
    final RecommendedGoals goals = recommendedGoalsFor();
    expect(goals.basis, RecommendationBasis.fallback);
    expect(goals.dailyCalories, kGoalDefaultDailyCalories);
    expect(goals.dailyBurnKcal, kGoalDefaultDailyBurnKcal);
    expect(goals.weeklyStrengthSets, kGoalDefaultWeeklyStrengthSets);
    expect(goals.weeklyFlexibilityMinutes, kGoalDefaultWeeklyFlexibilityMinutes);
  });
}

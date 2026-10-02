/// 권장값 계산을 `oncare_ui` 로 옮기면서(#2359) 기본값 상수도 그쪽에 한 벌 두었다.
/// 회원 앱의 기준선(`UserProfile.default…`·`kDefaultExerciseLoadGoals`)과 어긋나면
/// 목표를 세우지 않은 회원이 홈에서 보는 목표와 권장값이 갈린다.
///
/// 기준선의 원본 표는 `shared/oncare_rules/vectors/goal_defaults.json` 이다(#2906).
/// 서버 pytest·`oncare_ui`·트레이너 웹 테스트가 같은 파일을 읽는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/demo/diet_advice.dart'
    show DemoDietTargets, demoDietTargets;
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/recommended_goals.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';

import '../../helpers/shared_rule_vectors.dart';

void main() {
  final Map<String, Object?> original = loadSharedRuleVectors('goal_defaults');

  test('회원 앱 기준선이 원본 표와 같다', () {
    expect(UserProfile.defaultDailyCalories, original['daily_calories']);
    expect(UserProfile.defaultDailySodiumMg, original['daily_sodium_mg']);
    expect(UserProfile.defaultDailySugarG, original['daily_sugar_g']);
    expect(UserProfile.defaultDailyCarbsG, original['daily_carbs_g']);
    expect(UserProfile.defaultDailyProteinG, original['daily_protein_g']);
    expect(UserProfile.proteinGPerKg, original['protein_g_per_kg']);
    expect(UserProfile.defaultDailyFatG, original['daily_fat_g']);
    expect(kDefaultExerciseLoadGoals.dailyBurnKcal, original['daily_burn_kcal']);
    expect(
      kDefaultExerciseLoadGoals.weeklyCardioMinutes,
      original['weekly_cardio_minutes'],
    );
    expect(
      kDefaultExerciseLoadGoals.weeklyStrengthSets,
      original['weekly_strength_sets'],
    );
    expect(
      kDefaultExerciseLoadGoals.weeklyFlexibilityMinutes,
      original['weekly_flexibility_minutes'],
    );
  });

  test('데모 서버의 식단 목표도 같은 기준선이다', () {
    final DemoDietTargets targets = demoDietTargets(
      const <String, Object?>{},
    );
    expect(targets.calories, original['daily_calories']);
    expect(targets.proteinG, original['daily_protein_g']);
    expect(targets.sodiumMg, original['daily_sodium_mg']);
    expect(targets.sugarG, original['daily_sugar_g']);
    // 체중이 있으면 체중 × 1.2g — 서버 `PROTEIN_G_PER_KG` 와 같다.
    expect(
      demoDietTargets(const <String, Object?>{'weight_kg': 70}).proteinG,
      84,
    );
  });

  test('공유 기본값이 회원 앱 기준선과 같다', () {
    expect(kGoalDefaultDailyCalories, UserProfile.defaultDailyCalories);
    expect(kGoalDefaultDailySodiumMg, UserProfile.defaultDailySodiumMg);
    expect(kGoalDefaultDailyProteinG, UserProfile.defaultDailyProteinG);
    expect(
      kGoalDefaultDailyBurnKcal,
      kDefaultExerciseLoadGoals.dailyBurnKcal.round(),
    );
    expect(
      kGoalDefaultWeeklyCardioMinutes,
      kDefaultExerciseLoadGoals.weeklyCardioMinutes.round(),
    );
    expect(
      kGoalDefaultWeeklyStrengthSets,
      kDefaultExerciseLoadGoals.weeklyStrengthSets.round(),
    );
    expect(
      kGoalDefaultWeeklyFlexibilityMinutes,
      kDefaultExerciseLoadGoals.weeklyFlexibilityMinutes.round(),
    );
  });

  test('공유 계산이 회원 앱 건강 목표 키를 알아본다', () {
    // 문자열로 옮겨 적은 키가 앱의 키와 어긋나면 목표를 골라도 반영되지 않는다.
    expect(
      kDietFocus,
      containsAll(<String>[
        kHealthFocusWeightLoss,
        kHealthFocusStrength,
        kHealthFocusEating,
      ]),
    );
    expect(
      kExerciseFocus,
      containsAll(<String>[
        kHealthFocusWeightLoss,
        kHealthFocusStrength,
        kHealthFocusFitness,
        kHealthFocusPosture,
        kHealthFocusRehab,
        kHealthFocusExerciseHabit,
      ]),
    );
    final RecommendedGoals loss = recommendedGoalsFromCalories(
      2000,
      basis: RecommendationBasis.personalized,
      focus: const <String>{kHealthFocusWeightLoss},
    );
    expect(loss.dailyBurnKcal, kFocusWeightLossBurnKcal);
  });
}

/// 권장값 계산을 `oncare_ui` 로 옮기면서(#2359) 기본값 상수도 그쪽에 한 벌 두었다.
/// 회원 앱의 기준선(`UserProfile.default…`·`kDefaultExerciseLoadGoals`)과 어긋나면
/// 목표를 세우지 않은 회원이 홈에서 보는 목표와 권장값이 갈린다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/recommended_goals.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';

void main() {
  test('공유 기본값이 회원 앱 기준선과 같다', () {
    expect(kGoalDefaultDailyCalories, UserProfile.defaultDailyCalories);
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

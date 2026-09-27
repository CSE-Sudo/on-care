/// 권장 목표 계산은 두 앱이 함께 쓰도록 `oncare_ui` 로 옮겼다(#2359).
///
/// 회원 앱 코드는 예전처럼 이 경로로 읽는다 — 계산 본문과 출처 설명은
/// `shared/oncare_ui/lib/src/forms/app_recommended_goals.dart` 에 있다.
library;

export 'package:oncare_ui/oncare_ui.dart'
    show
        RecommendationBasis,
        RecommendedGoals,
        ageFromBirthDate,
        estimatedEnergyRequirement,
        kDietFocus,
        kEerMinAgeYears,
        kExerciseFocus,
        kFocusEatingSugarShare,
        kFocusHabitCardioMinutes,
        kFocusMobilityFlexibilityMinutes,
        kFocusRehabStrengthSets,
        kFocusStrengthProteinGPerKg,
        kFocusStrengthSets,
        kFocusActiveCardioMinutes,
        kFocusWeightLossBurnKcal,
        kFocusWeightLossDeficitKcal,
        kGoalDefaultDailyBurnKcal,
        kGoalDefaultDailyCalories,
        kGoalDefaultWeeklyCardioMinutes,
        kGoalDefaultWeeklyFlexibilityMinutes,
        kGoalDefaultWeeklyStrengthSets,
        kKcalPerCarbG,
        kKcalPerFatG,
        kKcalPerProteinG,
        kMaxRecommendedCalories,
        kMinRecommendedCalories,
        kPaLowActiveFemale,
        kPaLowActiveMale,
        kRecommendedCarbShare,
        kRecommendedFatShare,
        kRecommendedProteinShare,
        kRecommendedSodiumMg,
        kRecommendedSugarShare,
        recommendedGoalsFor,
        recommendedGoalsFromCalories;

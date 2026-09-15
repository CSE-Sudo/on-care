import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/account/domain/entities/recommended_goals.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';

/// 온보딩이 미리 채우는 권장 목표의 계산. (#1276 후속 — 온보딩 개편)
///
/// 화면이 "나이·성별·키·체중으로 계산한 값" 이라고 말하므로, 그 말이 참인지를
/// 여기서 못 박는다.
void main() {
  group('에너지필요추정량(EER)', () {
    test('성인 남성은 2020 한국인 영양소 섭취기준 추정식을 그대로 쓴다', () {
      // 662 − 9.53×35 + 1.11×(15.91×70 + 539.6×1.75) = 2,612.83
      expect(
        estimatedEnergyRequirement(
          ageYears: 35,
          gender: 'male',
          heightCm: 175,
          weightKg: 70,
        ),
        2613,
      );
    });

    test('성인 여성은 여성 식을 쓴다', () {
      // 354 − 6.91×35 + 1.12×(9.36×55 + 726×1.60) = 1,989.72
      expect(
        estimatedEnergyRequirement(
          ageYears: 35,
          gender: 'female',
          heightCm: 160,
          weightKg: 55,
        ),
        1990,
      );
    });

    test('성별을 고르지 않았거나 기타면 두 식의 평균이다', () {
      final int? male = estimatedEnergyRequirement(
        ageYears: 35,
        gender: 'male',
        heightCm: 170,
        weightKg: 65,
      );
      final int? female = estimatedEnergyRequirement(
        ageYears: 35,
        gender: 'female',
        heightCm: 170,
        weightKg: 65,
      );
      final int? other = estimatedEnergyRequirement(
        ageYears: 35,
        gender: 'other',
        heightCm: 170,
        weightKg: 65,
      );
      expect(other, isNotNull);
      expect(other, greaterThan(female!));
      expect(other, lessThan(male!));
      // 한쪽 성별로 몰아 두면 그 회원의 목표만 조용히 한 성별 값이 된다.
      // 각 칸을 따로 반올림한 뒤 평균 낸 값과는 1kcal 어긋날 수 있다.
      expect(other, closeTo((male + female) / 2, 1));
    });

    test('나이가 많을수록 낮아진다', () {
      final int? young = estimatedEnergyRequirement(
        ageYears: 25,
        gender: 'male',
        heightCm: 175,
        weightKg: 70,
      );
      final int? old = estimatedEnergyRequirement(
        ageYears: 65,
        gender: 'male',
        heightCm: 175,
        weightKg: 70,
      );
      expect(old, lessThan(young!));
    });

    test('넷 중 하나라도 없으면 계산하지 않는다', () {
      expect(
        estimatedEnergyRequirement(gender: 'male', heightCm: 175, weightKg: 70),
        isNull,
      );
      expect(
        estimatedEnergyRequirement(ageYears: 35, gender: 'male', weightKg: 70),
        isNull,
      );
    });

    test('성인 추정식이므로 미성년은 계산하지 않는다', () {
      expect(
        estimatedEnergyRequirement(
          ageYears: 15,
          gender: 'male',
          heightCm: 170,
          weightKg: 60,
        ),
        isNull,
      );
    });

    test('키·체중이 범위를 벗어나면 계산하지 않는다', () {
      expect(
        estimatedEnergyRequirement(
          ageYears: 35,
          gender: 'male',
          heightCm: 5,
          weightKg: 70,
        ),
        isNull,
      );
      expect(
        estimatedEnergyRequirement(
          ageYears: 35,
          gender: 'male',
          heightCm: 175,
          weightKg: 900,
        ),
        isNull,
      );
    });

    test('결과는 사람이 먹을 수 있는 범위 안에 머문다', () {
      final int? tiny = estimatedEnergyRequirement(
        ageYears: 100,
        gender: 'female',
        heightCm: 130,
        weightKg: 25,
      );
      expect(tiny, greaterThanOrEqualTo(kMinRecommendedCalories));
      final int? huge = estimatedEnergyRequirement(
        ageYears: 19,
        gender: 'male',
        heightCm: 250,
        weightKg: 400,
      );
      expect(huge, lessThanOrEqualTo(kMaxRecommendedCalories));
    });
  });

  group('권장 목표', () {
    test('탄단지는 칼로리를 에너지적정비율로 나눈 값이다', () {
      final RecommendedGoals r = recommendedGoalsFromCalories(
        2000,
        basis: RecommendationBasis.personalized,
      );
      expect(r.dailyCalories, 2000);
      expect(r.dailyCarbsG, 275); // 2000×0.55 / 4
      expect(r.dailyProteinG, 100); // 2000×0.20 / 4
      expect(r.dailyFatG, 56); // 2000×0.25 / 9
    });

    test('세 비율의 합은 100% 이고 각자 기준 범위 안에 있다', () {
      // 2020 한국인 영양소 섭취기준: 탄 55~65 · 단 7~20 · 지 15~30.
      expect(
        kRecommendedCarbShare + kRecommendedProteinShare + kRecommendedFatShare,
        closeTo(1.0, 1e-9),
      );
      expect(kRecommendedCarbShare, inInclusiveRange(0.55, 0.65));
      expect(kRecommendedProteinShare, inInclusiveRange(0.07, 0.20));
      expect(kRecommendedFatShare, inInclusiveRange(0.15, 0.30));
    });

    test('당류는 총 열량의 10%, 나트륨은 몸과 무관한 고정값이다', () {
      final RecommendedGoals r = recommendedGoalsFromCalories(
        2400,
        basis: RecommendationBasis.personalized,
      );
      expect(r.dailySugarG, 60); // 2400×0.10 / 4
      expect(r.dailySodiumMg, kRecommendedSodiumMg);
      expect(kRecommendedSodiumMg, 2000); // WHO 권고
    });

    test('운동 권장값은 운동 탭·MY 가 쓰는 상수와 같은 값이다', () {
      final RecommendedGoals r = recommendedGoalsFor(
        ageYears: 35,
        gender: 'male',
        heightCm: 175,
        weightKg: 70,
      );
      expect(r.dailyBurnKcal, kDefaultExerciseLoadGoals.dailyBurnKcal.round());
      expect(r.weeklyCardioMinutes, 150); // WHO: 주 150분 중강도 유산소
      expect(
        r.weeklyStrengthSets,
        kDefaultExerciseLoadGoals.weeklyStrengthSets.round(),
      );
      expect(
        r.weeklyFlexibilityMinutes,
        kDefaultExerciseLoadGoals.weeklyFlexibilityMinutes.round(),
      );
    });

    test('기본 정보가 모자라면 앱 기본값으로 물러서고 그렇다고 밝힌다', () {
      final RecommendedGoals r = recommendedGoalsFor(gender: 'male');
      expect(r.basis, RecommendationBasis.fallback);
      expect(r.isPersonalized, isFalse);
      expect(r.dailyCalories, UserProfile.defaultDailyCalories);
    });

    test('기본 정보가 다 있으면 계산한 값이라고 밝힌다', () {
      final RecommendedGoals r = recommendedGoalsFor(
        ageYears: 35,
        gender: 'male',
        heightCm: 175,
        weightKg: 70,
      );
      expect(r.basis, RecommendationBasis.personalized);
      expect(r.dailyCalories, 2613);
    });
  });

  // 고른 건강 목표에 맞춘 조정(#1816). 조정 폭은 화면 각주가 밝히는 공개 권고안
  // 범위 안이어야 한다.
  group('건강 목표 반영', () {
    RecommendedGoals from(Set<String> focus, {double? weightKg}) =>
        recommendedGoalsFromCalories(
          2000,
          basis: RecommendationBasis.personalized,
          focus: focus,
          weightKg: weightKg,
        );

    test('목표가 없으면 기준값 그대로다', () {
      final RecommendedGoals r = from(const <String>{}, weightKg: 70);
      expect(r.dailyCarbsG, 275);
      expect(r.dailyProteinG, 100);
      expect(r.dailyFatG, 56);
      expect(r.dailySugarG, 50);
      expect(r.dailyBurnKcal, 300);
      expect(r.weeklyCardioMinutes, 150);
      expect(r.weeklyStrengthSets, 21);
      expect(r.weeklyFlexibilityMinutes, 60);
      expect(r.isDietAdjusted, isFalse);
      expect(r.isExerciseAdjusted, isFalse);
    });

    test('체중 감량은 추정 열량에서 500kcal 빼고 소모·유산소를 올린다', () {
      final RecommendedGoals base = recommendedGoalsFor(
        ageYears: 35,
        gender: 'male',
        heightCm: 175,
        weightKg: 70,
      );
      final RecommendedGoals r = recommendedGoalsFor(
        ageYears: 35,
        gender: 'male',
        heightCm: 175,
        weightKg: 70,
        focus: const <String>{kHealthFocusWeightLoss},
      );
      expect(r.dailyCalories, base.dailyCalories - 500);
      expect(r.dailyBurnKcal, 400);
      expect(r.weeklyCardioMinutes, 200);
      expect(r.isDietAdjusted, isTrue);
      expect(r.isExerciseAdjusted, isTrue);
    });

    test('감량해도 최소 열량 아래로 내려가지 않는다', () {
      final RecommendedGoals r = recommendedGoalsFor(
        ageYears: 100,
        gender: 'female',
        heightCm: 130,
        weightKg: 25,
        focus: const <String>{kHealthFocusWeightLoss},
      );
      expect(r.dailyCalories, kMinRecommendedCalories);
    });

    test('회원이 적은 칼로리에서는 감량분을 다시 빼지 않는다', () {
      expect(from(const <String>{kHealthFocusWeightLoss}).dailyCalories, 2000);
    });

    test('근력 향상은 단백질을 체중 1kg당 1.6g 으로 올리고 그만큼 탄수화물을 줄인다', () {
      final RecommendedGoals r = from(const <String>{
        kHealthFocusStrength,
      }, weightKg: 70);
      expect(r.dailyProteinG, 112); // 70×1.6
      expect(r.dailyFatG, 56);
      // 총열량은 그대로: (2000 − 112×4 − 56×9) / 4 = 262
      expect(r.dailyCarbsG, 262);
      expect(r.weeklyStrengthSets, 28);
      expect(kFocusStrengthProteinGPerKg, inInclusiveRange(1.4, 2.0)); // ISSN
    });

    test('체중을 모르면 단백질은 비율 그대로다', () {
      final RecommendedGoals r = from(const <String>{kHealthFocusStrength});
      expect(r.dailyProteinG, 100);
      expect(r.dailyCarbsG, 275);
    });

    test('비율로 이미 넉넉하면 단백질을 줄이지 않는다', () {
      // 50kg × 1.6 = 80g < 비율 100g
      expect(
        from(const <String>{kHealthFocusStrength}, weightKg: 50).dailyProteinG,
        100,
      );
    });

    test('단백질을 늘려도 탄수화물이 0 아래로 내려가지 않는다', () {
      final RecommendedGoals r = recommendedGoalsFromCalories(
        1200,
        basis: RecommendationBasis.personalized,
        focus: const <String>{kHealthFocusStrength},
        weightKg: 300,
      );
      expect(r.dailyCarbsG, greaterThanOrEqualTo(0));
      expect(
        r.dailyProteinG * 4 + r.dailyFatG * 9 + r.dailyCarbsG * 4,
        lessThanOrEqualTo(1200 + 4),
      );
    });

    test('식습관 개선은 당류를 총열량 5% 로 낮춘다', () {
      expect(from(const <String>{kHealthFocusEating}).dailySugarG, 25);
    });

    test('체력 강화는 유산소를, 자세 교정은 스트레칭을 올린다', () {
      expect(
        from(const <String>{kHealthFocusFitness}).weeklyCardioMinutes,
        200,
      );
      expect(
        from(const <String>{kHealthFocusPosture}).weeklyFlexibilityMinutes,
        90,
      );
    });

    test('재활은 근력을 낮추고 스트레칭을 올린다', () {
      final RecommendedGoals r = from(const <String>{kHealthFocusRehab});
      expect(r.weeklyStrengthSets, 14);
      expect(r.weeklyFlexibilityMinutes, 90);
    });

    test('여러 목표는 칸마다 가장 적극적인 값을 쓴다', () {
      final RecommendedGoals r = from(const <String>{
        kHealthFocusWeightLoss,
        kHealthFocusStrength,
        kHealthFocusRehab,
      }, weightKg: 70);
      expect(r.weeklyCardioMinutes, 200);
      expect(r.weeklyStrengthSets, 28);
      expect(r.weeklyFlexibilityMinutes, 90);
      expect(r.dailyProteinG, 112);
    });

    test('운동 습관을 고르면 유산소는 낮게 시작한다', () {
      expect(
        from(const <String>{
          kHealthFocusWeightLoss,
          kHealthFocusExerciseHabit,
        }).weeklyCardioMinutes,
        90,
      );
    });

    test('혈압 관리는 기준값(나트륨 2,000mg·유산소 150분)을 그대로 쓴다', () {
      final RecommendedGoals r = from(const <String>{
        kHealthFocusBloodPressure,
      });
      expect(r.dailySodiumMg, 2000);
      expect(r.weeklyCardioMinutes, 150);
      expect(r.isDietAdjusted, isFalse);
      expect(r.isExerciseAdjusted, isFalse);
    });

    test('혈압 관리 밖의 목표는 모두 권장값을 무언가 바꾼다', () {
      final RecommendedGoals base = from(const <String>{}, weightKg: 80);
      for (final String option in kHealthFocusOptions) {
        if (option == kHealthFocusBloodPressure) continue;
        final RecommendedGoals r = from(<String>{option}, weightKg: 80);
        final bool changed =
            r.dailyCarbsG != base.dailyCarbsG ||
            r.dailyProteinG != base.dailyProteinG ||
            r.dailySugarG != base.dailySugarG ||
            r.dailyBurnKcal != base.dailyBurnKcal ||
            r.weeklyCardioMinutes != base.weeklyCardioMinutes ||
            r.weeklyStrengthSets != base.weeklyStrengthSets ||
            r.weeklyFlexibilityMinutes != base.weeklyFlexibilityMinutes ||
            recommendedGoalsFor(
                  ageYears: 35,
                  gender: 'male',
                  heightCm: 175,
                  weightKg: 80,
                  focus: <String>{option},
                ).dailyCalories !=
                recommendedGoalsFor(
                  ageYears: 35,
                  gender: 'male',
                  heightCm: 175,
                  weightKg: 80,
                ).dailyCalories;
        expect(changed, isTrue, reason: option);
      }
    });
  });

  group('만 나이', () {
    test('생일이 지나지 않았으면 한 살 적다', () {
      expect(ageFromBirthDate('1990-07-15', today: DateTime(2026, 8, 24)), 36);
      expect(ageFromBirthDate('1990-09-15', today: DateTime(2026, 8, 24)), 35);
    });

    test('읽을 수 없는 값은 null 이다', () {
      expect(ageFromBirthDate('', today: DateTime(2026, 8, 24)), isNull);
      expect(ageFromBirthDate('언젠가', today: DateTime(2026, 8, 24)), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 트레이너 웹이 견주는 목표 미설정 기본값이 원본 표와 같은가(#2906).
///
/// 원본은 `shared/oncare_rules/vectors/goal_defaults.json` 이고, 서버 pytest·
/// 공용 패키지·회원 앱 테스트가 같은 파일을 읽는다. 트레이너 화면만 옛 값을
/// 들고 있으면 같은 회원의 같은 날이 회원 폰과 트레이너 화면에서 다른 목표선으로
/// 그려진다.
void main() {
  final Map<String, Object?> original = loadSharedRuleVectors('goal_defaults');

  test('식단 기본 목표가 원본 표와 같다', () {
    expect(calorieTargetKcal, original['daily_calories']);
    expect(sodiumTargetMg, original['daily_sodium_mg']);
    expect(sugarTargetG, original['daily_sugar_g']);
    expect(carbsTargetG, original['daily_carbs_g']);
    expect(proteinTargetG, original['daily_protein_g']);
    expect(fatTargetG, original['daily_fat_g']);
    expect(MemberHealthProfile.defaultDailyProteinG, original['daily_protein_g']);
    expect(MemberHealthProfile.proteinGPerKg, original['protein_g_per_kg']);
  });

  test('운동 기본 목표가 원본 표와 같다', () {
    expect(kDailyBurnKcal, original['daily_burn_kcal']);
    expect(kWeeklyCardioMinutes, original['weekly_cardio_minutes']);
    expect(kWeeklyStrengthSets, original['weekly_strength_sets']);
    expect(kWeeklyStretchingMinutes, original['weekly_flexibility_minutes']);
    expect(
      ExerciseBurnGoals.fromProfile(null).dailyBurnKcal,
      original['daily_burn_kcal'],
    );
  });

  test('리포트 요약과 결과지도 같은 기본값을 쓴다', () {
    expect(summarySodiumTargetMg, original['daily_sodium_mg']);
    expect(summaryCalorieTargetKcal, original['daily_calories']);
    expect(summarySugarTargetG, original['daily_sugar_g']);
    expect(kReportCalorieTargetKcal, original['daily_calories']);
    expect(kReportSodiumTargetMg, original['daily_sodium_mg']);
    expect(kReportCarbsTargetG, original['daily_carbs_g']);
    expect(kReportProteinTargetG, original['daily_protein_g']);
    expect(kReportFatTargetG, original['daily_fat_g']);
    expect(sugarLimitG, original['daily_sugar_g']);
  });
}

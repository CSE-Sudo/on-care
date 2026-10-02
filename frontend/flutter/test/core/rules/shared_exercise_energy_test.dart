import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 입력 시트의 운동 칼로리 계수가 원본 표와 같은가(#2906).
///
/// 원본은 `shared/oncare_rules/vectors/exercise_energy.json` 이고 서버
/// `exercise_catalog.energy`·트레이너 폼도 같은 파일로 대조한다.
void main() {
  final Map<String, Object?> original = loadSharedRuleVectors(
    'exercise_energy',
  );
  final Map<String, Object?> factor =
      original['intensity_factor']! as Map<String, Object?>;
  final Map<String, Object?> perMinute =
      original['fallback_kcal_per_min']! as Map<String, Object?>;

  test('강도 배수가 원본 표와 같다', () {
    for (final ExerciseIntensity i in ExerciseIntensity.values) {
      expect(kIntensityFactor[i], factor[i.name], reason: i.name);
    }
  });

  test('보통 강도 60분은 원본 표의 분당 kcal × 60 이다', () {
    const Map<ExerciseType, String> code = <ExerciseType, String>{
      ExerciseType.cardio: 'cardio',
      ExerciseType.strength: 'strength',
      ExerciseType.stretching: 'stretching',
      ExerciseType.other: 'other',
      // 옛 유형은 서버처럼 표준 유형으로 접는다.
      ExerciseType.walking: 'cardio',
      ExerciseType.yoga: 'stretching',
    };
    for (final MapEntry<ExerciseType, String> e in code.entries) {
      expect(
        estimateExerciseCalories(e.key, 60),
        ((perMinute[e.value]! as num) * 60).round(),
        reason: e.key.name,
      );
    }
  });
}

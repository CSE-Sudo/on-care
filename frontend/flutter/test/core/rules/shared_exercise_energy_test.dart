import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare_rules/oncare_rules.dart' show kExerciseIntensityFactor;

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

  // 앱은 강도 이름(`ExerciseIntensity.name`)으로 공용 표를 찾는다 — 이름이
  // 어긋나면 배수가 1.0 으로 떨어지므로, 앱의 모든 강도가 원본 값으로 읽히는지 본다.
  test('강도 배수가 원본 표와 같다', () {
    for (final ExerciseIntensity i in ExerciseIntensity.values) {
      expect(kExerciseIntensityFactor[i.name], factor[i.name], reason: i.name);
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

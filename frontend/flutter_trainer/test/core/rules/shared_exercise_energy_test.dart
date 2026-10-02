import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 추천 개인운동 폼의 칼로리 계수가 원본 표와 같은가(#2906).
///
/// 원본은 `shared/oncare_rules/vectors/exercise_energy.json` 이고 서버
/// `exercise_catalog.energy`·회원 앱 입력 시트도 같은 파일로 대조한다.
void main() {
  final Map<String, Object?> original = loadSharedRuleVectors(
    'exercise_energy',
  );
  final Map<String, Object?> factor =
      original['intensity_factor']! as Map<String, Object?>;
  final Map<String, Object?> perMinute =
      original['fallback_kcal_per_min']! as Map<String, Object?>;
  const Map<String, String> label = <String, String>{
    'cardio': '유산소',
    'strength': '근력',
    'stretching': '스트레칭',
    'other': '기타',
  };

  test('유형·강도마다 60분 값이 원본 표의 분당 kcal × 배수 × 60 이다', () {
    for (final MapEntry<String, String> type in label.entries) {
      for (final MapEntry<String, Object?> i in factor.entries) {
        final RoutineCalorieEstimate? estimate = estimateRoutineCalories(
          name: '테스트 운동',
          type: type.value,
          minutes: 60,
          intensity: i.key,
        );
        expect(
          estimate?.calories,
          ((perMinute[type.key]! as num) * 60 * (i.value! as num)).round(),
          reason: '${type.key}/${i.key}',
        );
      }
    }
  });
}

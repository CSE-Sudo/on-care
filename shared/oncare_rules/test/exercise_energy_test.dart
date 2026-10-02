import 'package:oncare_rules/oncare_rules.dart';
import 'package:test/test.dart';

import 'vectors.dart';

/// 운동 칼로리 계수가 원본 표와 같다(#2906). 서버 pytest
/// (`tests/test_shared_rule_sources.py`)도 같은 파일을 읽는다.
void main() {
  final Map<String, Object?> original = loadVectors('exercise_energy');

  test('강도 배수가 원본 표와 같다', () {
    expect(kExerciseIntensityFactor, original['intensity_factor']);
  });

  test('유형별 분당 kcal 폴백이 원본 표와 같다', () {
    expect(kFallbackKcalPerMinute, original['fallback_kcal_per_min']);
  });

  test('모르는 강도는 1배, 모르는 유형은 기타의 값이다', () {
    expect(exerciseIntensityFactor(null), 1.0);
    expect(exerciseIntensityFactor('extreme'), 1.0);
    expect(fallbackKcalPerMinute('수영장'), kFallbackKcalPerMinute['other']);
    expect(fallbackKcalPerMinute(null), kFallbackKcalPerMinute['other']);
  });

  test('한글 라벨·옛 값도 표준 유형으로 접어 센다', () {
    expect(fallbackKcalPerMinute('유산소'), 9.0);
    expect(fallbackKcalPerMinute('walking'), 9.0);
    expect(fallbackKcalPerMinute('yoga'), 3.0);
  });

  group('fallbackExerciseCalories — 서버 energy.fallback 과 같다', () {
    final List<Object?> rows =
        loadVectors('rounding')['fallback_calories']! as List<Object?>;
    for (final Object? row in rows) {
      final Map<String, Object?> r = row! as Map<String, Object?>;
      test('${r['type']} ${r['minutes']}분 ${r['intensity']}', () {
        expect(
          fallbackExerciseCalories(
            r['type'] as String?,
            r['minutes']! as int,
            r['intensity'] as String?,
          ),
          r['calories'],
        );
      });
    }

    test('음수 시간은 0분이다', () {
      expect(fallbackExerciseCalories('cardio', -10, 'high'), 0);
    });
  });
}

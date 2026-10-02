import 'package:oncare_rules/oncare_rules.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final Map<String, Object?> vectors = loadVectors('exercise_types');

  group('운동 유형 정규화 — 서버 exercise_types 와 같은 표', () {
    for (final Object? row in vectors['normalize']! as List<Object?>) {
      final List<Object?> r = row! as List<Object?>;
      final String? input = r[0] as String?;
      test('${input == null ? 'null' : '"$input"'} → ${r[1]} / ${r[2]}', () {
        expect(normalizeExerciseType(input), r[1]);
        expect(normalizeExerciseTypeKo(input), r[2]);
      });
    }
  });

  test('표준 코드마다 한글 라벨이 하나씩 있다', () {
    expect(kExerciseTypeKoLabels.keys, kExerciseTypeCodes);
    expect(kExerciseTypeKoLabels.values.toSet(), hasLength(4));
  });

  test('한글 라벨을 다시 접으면 제 코드로 돌아온다', () {
    for (final String code in kExerciseTypeCodes) {
      expect(normalizeExerciseType(kExerciseTypeKoLabels[code]), code);
    }
  });
}

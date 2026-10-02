import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/diet_analysis_rules.dart'
    show pyRound;
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 트레이너 웹의 분·kcal 반올림이 서버(Python `round`)·회원 앱과 같은가(#2860).
void main() {
  final Map<String, Object?> vectors = loadSharedRuleVectors('rounding');

  group('공용 반올림 — 서버와 같은 입력 표', () {
    for (final (Object? x, Object? expected) in vectorPairs(
      vectors,
      'py_round',
    )) {
      test('pyRound($x) == $expected', () {
        expect(pyRound(x! as num), expected);
      });
    }

    for (final (Object? seconds, Object? minutes) in vectorPairs(
      vectors,
      'minutes_from_seconds',
    )) {
      test('$seconds초 → $minutes분', () {
        expect(minutesFromSeconds(seconds! as int), minutes);
      });
    }

    test('2분 30초·4분 30초는 서버처럼 2분·4분이다', () {
      expect(minutesFromSeconds(150), 2);
      expect(minutesFromSeconds(270), 4);
    });
  });

  group('추천 개인운동 kcal 추정 — 서버 energy.fallback 과 같다', () {
    const Map<String, String> label = <String, String>{
      'cardio': '유산소',
      'strength': '근력',
      'stretching': '스트레칭',
      'other': '기타',
    };
    for (final Map<String, Object?> c in vectorRows(
      vectors,
      'fallback_calories',
    )) {
      test('${c['type']} ${c['minutes']}분 ${c['intensity']} → '
          '${c['calories']}kcal', () {
        final RoutineCalorieEstimate? estimate = estimateRoutineCalories(
          name: '테스트 운동',
          type: label[c['type']]!,
          minutes: c['minutes']! as int,
          intensity: c['intensity']! as String,
        );
        expect(estimate?.calories, c['calories']);
      });
    }

    test('절반에서 짝수 쪽으로 간다 — 기타 2분 가벼움은 8.5 → 8', () {
      expect(
        estimateRoutineCalories(
          name: '테스트 운동',
          type: '기타',
          minutes: 2,
          intensity: 'light',
        )?.calories,
        8,
      );
    });
  });
}

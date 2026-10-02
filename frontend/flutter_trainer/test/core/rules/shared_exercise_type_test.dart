import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 트레이너 웹의 운동 유형 접기가 서버 `exercise_types` 와 같은 표를 쓰는가(#2861).
void main() {
  final Map<String, Object?> vectors = loadSharedRuleVectors('exercise_types');
  final List<List<Object?>> rows = <List<Object?>>[
    for (final Object? r in vectors['normalize']! as List<Object?>)
      r! as List<Object?>,
  ];

  group('normaliseRoutineType — 서버 normalize_ko 와 같다', () {
    for (final List<Object?> r in rows.where((r) => r[0] != null)) {
      test('"${r[0]}" → ${r[2]}', () {
        expect(normaliseRoutineType(r[0]! as String), r[2]);
      });
    }

    test('모르는 값은 근력이 아니라 기타다', () {
      expect(normaliseRoutineType('crossfit'), '기타');
      expect(normaliseRoutineType(''), '기타');
    });

    test('영문 코드도 제 유형으로 접는다', () {
      expect(normaliseRoutineType('cardio'), '유산소');
      expect(normaliseRoutineType('strength'), '근력');
      expect(normaliseRoutineType('stretching'), '스트레칭');
      expect(normaliseRoutineType('walking'), '유산소');
    });

    test('결과는 늘 서버가 받는 네 라벨 중 하나다', () {
      for (final List<Object?> r in rows.where((r) => r[0] != null)) {
        expect(kRoutineTypes, contains(normaliseRoutineType(r[0]! as String)));
      }
    });
  });

  group('추천 개인운동 kcal 추정 — 접힌 유형의 단가를 쓴다', () {
    int? kcal(String type) => estimateRoutineCalories(
      name: '테스트 운동',
      type: type,
      minutes: 10,
      intensity: 'moderate',
    )?.calories;

    test('cardio 는 유산소 단가(분당 9)다', () {
      expect(kcal('cardio'), 90);
      expect(kcal('cardio'), kcal('유산소'));
    });

    test('옛 값·한글·코드가 같은 단가로 떨어진다', () {
      expect(kcal('walking'), 90);
      expect(kcal('걷기'), 90);
      expect(kcal('strength'), 60);
      expect(kcal('yoga'), 30);
      expect(kcal('유연성'), 30);
    });

    test('모르는 값은 기타 단가(분당 5)다', () {
      expect(kcal('crossfit'), 50);
    });
  });

  group('배정 JSON — 서버로 나가는 유형', () {
    test('영문 코드로 들어온 유형도 한글 라벨로 나간다', () {
      final Map<String, Object?> json = assignRoutineToJson(
        const AssignedRoutine(
          id: 'r1',
          name: '러닝',
          minutes: 20,
          type: 'cardio',
          reason: '',
          source: 'trainer',
        ),
      );
      expect(json['type'], '유산소');
    });
  });

  group('회원 주간 운동 응답 — 유형 칸', () {
    for (final List<Object?> r in rows) {
      test('${r[0] == null ? 'null' : '"${r[0]}"'} 기록은 ${r[1]} 칸이다', () {
        final ClientExerciseWeek week = ClientExerciseWeek.fromJson(
          <String, Object?>{
            'day_labels': <String>['월'],
            'daily_minutes': <int>[10],
            'daily_calories': <int>[100],
            'sessions': <Object?>[
              <String, Object?>{
                'day_label': '월',
                'name': '테스트 운동',
                'type': r[0],
                'minutes': 10,
                'calories': 100,
              },
            ],
          },
        );
        expect(week.itemsByDayLabel['월']!.single.type, r[1]);
        final Map<String, List<int>> calories = <String, List<int>>{
          'cardio': week.cardioCalories,
          'strength': week.strengthCalories,
          'stretching': week.stretchingCalories,
          'other': week.otherCalories,
        };
        for (final MapEntry<String, List<int>> e in calories.entries) {
          expect(e.value, <int>[e.key == r[1] ? 100 : 0], reason: e.key);
        }
      });
    }
  });
}

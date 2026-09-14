import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/data/dtos/routine_options_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';

void main() {
  test('routineOptionsFromJson maps analysis + A/B plans', () {
    final o = routineOptionsFromJson(<String, Object?>{
      'analysis': <String, Object?>{
        'goal': '혈압 관리',
        'sodium_today_mg': 2100,
        'sodium_over_target': true,
        'avg_completion_rate': 55,
        'latest_routine': '걷기',
        'note': '무릎 주의',
      },
      'plan_a': <String, Object?>{
        'key': 'A',
        'label': '회복·지속 중심',
        'total_minutes': 21,
        'intensity': '낮음',
        'exercises': <Object?>[
          <String, Object?>{'name': '저강도 걷기', 'minutes': 13, 'type': '유산소'},
          <String, Object?>{'name': '코어 스트레칭', 'minutes': 8, 'type': '스트레칭'},
        ],
        'reason': '지속 중심',
        'rationale': '오늘 나트륨 2100mg (목표 초과) ...',
      },
      'plan_b': <String, Object?>{
        'key': 'B',
        'label': '강도·운동량 중심',
        'total_minutes': 30,
        'intensity': '높음',
        'exercises': <Object?>[
          <String, Object?>{'name': '인터벌 러닝', 'minutes': 30, 'type': '유산소'},
        ],
        'reason': '강도 상향',
        'rationale': '목표 기준 ...',
      },
      'generated_by': 'rule',
    });

    expect(o.analysis.goal, '혈압 관리');
    expect(o.analysis.sodiumOverTarget, isTrue);
    expect(o.analysis.avgCompletionRate, 55);
    expect(o.planA.key, 'A');
    expect(o.planA.exercises.length, 2);
    expect(o.planA.exercises.first.name, '저강도 걷기');
    expect(o.planB.totalMinutes, 30);
    expect(o.generatedBy, 'rule');
    // #776 — absent on this payload, same as an older server: never reads
    // as personalized when there's no analysis to back that up.
    expect(o.analysis.recommendationStatus, RecommendationStatus.template);
    expect(o.analysis.historySessionCount, 0);
    expect(o.analysis.frequentExercises, isEmpty);
    expect(o.analysis.suggestedAvailableMinutes, isNull);
    expect(o.analysis.suggestedIntensity, isNull);
  });

  test('rejects missing fields and invalid A/B keys', () {
    expect(
      () => routineOptionsFromJson(<String, Object?>{}),
      throwsFormatException,
    );

    final invalid = <String, Object?>{
      'analysis': <String, Object?>{
        'goal': '',
        'sodium_today_mg': 0,
        'sodium_over_target': false,
        'avg_completion_rate': 0,
        'latest_routine': '',
        'note': '',
      },
      'plan_a': <String, Object?>{
        'key': 'B',
        'label': '',
        'total_minutes': 0,
        'intensity': '',
        'exercises': <Object?>[],
        'reason': '',
        'rationale': '',
      },
      'plan_b': <String, Object?>{
        'key': 'A',
        'label': '',
        'total_minutes': 0,
        'intensity': '',
        'exercises': <Object?>[],
        'reason': '',
        'rationale': '',
      },
      'generated_by': 'rule',
    };
    expect(() => routineOptionsFromJson(invalid), throwsFormatException);
  });

  group('recent_messages (#580)', () {
    Map<String, Object?> payload(Object? recentMessages) => <String, Object?>{
      'analysis': <String, Object?>{
        'goal': '혈압 관리',
        'sodium_today_mg': 2100,
        'sodium_over_target': true,
        'avg_completion_rate': 55,
        'latest_routine': '걷기',
        'note': '',
        'recent_messages': ?recentMessages,
      },
      'plan_a': <String, Object?>{
        'key': 'A',
        'label': '회복형',
        'total_minutes': 20,
        'intensity': '낮음',
        'exercises': <Object?>[
          <String, Object?>{'name': '걷기', 'minutes': 20, 'type': '유산소'},
        ],
        'reason': 'r',
        'rationale': 'r',
      },
      'plan_b': <String, Object?>{
        'key': 'B',
        'label': '강화형',
        'total_minutes': 20,
        'intensity': '높음',
        'exercises': <Object?>[
          <String, Object?>{'name': '스쿼트', 'minutes': 20, 'type': '근력'},
        ],
        'reason': 'r',
        'rationale': 'r',
      },
      'generated_by': 'ai',
    };

    test('keeps speaker-labelled lines in order', () {
      final o = routineOptionsFromJson(
        payload(<Object?>['회원: 무릎이 아파요', '트레이너: 하체 부하를 낮출게요']),
      );

      expect(o.analysis.recentMessages, <String>[
        '회원: 무릎이 아파요',
        '트레이너: 하체 부하를 낮출게요',
      ]);
    });

    test('a server without the field still yields usable options', () {
      // The evidence block is supporting context — an older backend must not
      // break routine generation.
      final o = routineOptionsFromJson(payload(null));

      expect(o.analysis.recentMessages, isEmpty);
      expect(o.planA.key, 'A');
    });

    test('drops non-string and blank entries instead of throwing', () {
      final o = routineOptionsFromJson(
        payload(<Object?>['회원: 어지러워요', 42, null, '   ']),
      );

      expect(o.analysis.recentMessages, <String>['회원: 어지러워요']);
    });

    test('a malformed field degrades to empty', () {
      final o = routineOptionsFromJson(payload('not-a-list'));

      expect(o.analysis.recentMessages, isEmpty);
    });
  });

  group('recommendation status + history analysis (#776)', () {
    Map<String, Object?> payload(Map<String, Object?> analysisExtra) =>
        <String, Object?>{
          'analysis': <String, Object?>{
            'goal': '체중 감량',
            'sodium_today_mg': 1800,
            'sodium_over_target': false,
            'avg_completion_rate': 70,
            'latest_routine': '스쿼트',
            'note': '',
            ...analysisExtra,
          },
          'plan_a': <String, Object?>{
            'key': 'A',
            'label': '기존 패턴 유지형',
            'total_minutes': 45,
            'intensity': '높음',
            'exercises': <Object?>[
              <String, Object?>{'name': '스쿼트', 'minutes': 45, 'type': '근력'},
            ],
            'reason': 'r',
            'rationale': 'r',
          },
          'plan_b': <String, Object?>{
            'key': 'B',
            'label': '점진적 강화형',
            'total_minutes': 45,
            'intensity': '높음',
            'exercises': <Object?>[
              <String, Object?>{'name': '스쿼트', 'minutes': 45, 'type': '근력'},
            ],
            'reason': 'r',
            'rationale': 'r',
          },
          'generated_by': 'rule',
        };

    test('parses a fully personalized analysis', () {
      final o = routineOptionsFromJson(
        payload(<String, Object?>{
          'recommendation_status': 'personalized',
          'history_session_count': 6,
          'analysis_period_days': 42,
          'frequent_exercises': <Object?>['스쿼트'],
          'suggested_available_minutes': 45,
          'suggested_intensity': 'high',
        }),
      );

      expect(
        o.analysis.recommendationStatus,
        RecommendationStatus.personalized,
      );
      expect(o.analysis.historySessionCount, 6);
      expect(o.analysis.analysisPeriodDays, 42);
      expect(o.analysis.frequentExercises, <String>['스쿼트']);
      expect(o.analysis.suggestedAvailableMinutes, 45);
      expect(o.analysis.suggestedIntensity, 'high');
    });

    test('parses the learning status with no suggested conditions yet', () {
      final o = routineOptionsFromJson(
        payload(<String, Object?>{
          'recommendation_status': 'learning',
          'history_session_count': 3,
        }),
      );

      expect(o.analysis.recommendationStatus, RecommendationStatus.learning);
      expect(o.analysis.suggestedAvailableMinutes, isNull);
      expect(o.analysis.suggestedIntensity, isNull);
    });

    test('an unrecognized status string degrades to template, not a throw', () {
      final o = routineOptionsFromJson(
        payload(<String, Object?>{'recommendation_status': 'not-a-real-status'}),
      );

      expect(o.analysis.recommendationStatus, RecommendationStatus.template);
    });
  });
}

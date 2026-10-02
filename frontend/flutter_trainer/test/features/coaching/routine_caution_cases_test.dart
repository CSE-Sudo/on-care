import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_rules.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 데모 A/B 의 루틴 주의 규칙이 서버 규칙형과 같은 표·같은 판단인가(#2906).
///
/// 원본은 서버 스크립트(`backend/scripts/gen_routine_caution_cases.py`)가 만든
/// `shared/oncare_rules/vectors/routine_caution_cases.json` 이고, 서버 pytest
/// (`tests/test_routine_caution_cases.py`)도 같은 파일을 읽는다.
void main() {
  final Map<String, Object?> file = loadSharedRuleVectors(
    'routine_caution_cases',
  );
  final Map<String, Object?> tables = file['tables']! as Map<String, Object?>;
  final Map<String, Object?> cases = file['cases']! as Map<String, Object?>;

  List<String> strings(Object? v) =>
      (v! as List<Object?>).map((Object? e) => e! as String).toList();

  (String, String, int) part(List<Object?> p) =>
      (p[0]! as String, p[1]! as String, p[2]! as int);

  List<(String, String, int)> parts(Object? v) => <(String, String, int)>[
    for (final Object? p in v! as List<Object?>) part(p! as List<Object?>),
  ];

  group('표 — 서버와 같은 값', () {
    test('주의 부위 · 가리키는 말 · 부담 동작', () {
      expect(<Map<String, Object?>>[
        for (final (String part, List<String> keywords, List<String> risky)
            in demoCautionRules)
          <String, Object?>{'part': part, 'keywords': keywords, 'risky': risky},
      ], tables['caution_rules']);
    });

    test('전문가 확인 낱말', () {
      expect(demoEscalationKeywords, tables['escalation_keywords']);
    });

    test('반복 운동 유형 낱말', () {
      expect(demoStretchKeywords, tables['stretch_keywords']);
      expect(demoCardioKeywords, tables['cardio_keywords']);
    });

    test('라이브러리 운동과 영어 이름', () {
      expect(<Map<String, String>>[
        for (final (String name, String type) in <(String, String)>[
          libCardioEasy,
          libCardioHard,
          libStrength,
          libStrength2,
          libStretch,
          libStretch2,
        ])
          <String, String>{'name': name, 'type': type},
      ], tables['library']);
      expect(demoEnExerciseNames, tables['en_exercise_names']);
      expect(demoEnCautionParts, tables['en_caution_parts']);
    });
  });

  group('판단 — 서버와 같은 결과', () {
    for (final Map<String, Object?> c in vectorRows(cases, 'detect')) {
      test('주의 부위 찾기: "${c['conditions']}" ${c['messages']}', () {
        final String conditions = c['conditions']! as String;
        final List<String> messages = strings(c['messages']);
        expect(cautionsIn(conditions, messages), c['cautions']);
        expect(
          needsProfessionalCheck(conditions, messages),
          c['needs_professional_check'],
        );
      });
    }

    for (final Map<String, Object?> c in vectorRows(cases, 'avoids')) {
      test('부담 동작: ${c['name']} ${c['cautions']}', () {
        expect(
          avoidsFor(c['name']! as String, strings(c['cautions'])),
          c['avoids'],
        );
      });
    }

    for (final Map<String, Object?> c in vectorRows(cases, 'safe_parts')) {
      test('저충격 대안: ${c['cautions']}', () {
        expect(
          safeParts(parts(c['parts']), strings(c['cautions'])),
          parts(c['result']),
        );
      });
    }

    for (final Map<String, Object?> c in vectorRows(cases, 'guess_type')) {
      test('유형 짐작: ${c['name']}', () {
        expect(guessExerciseType(c['name']! as String), c['type']);
      });
    }

    for (final Map<String, Object?> c in vectorRows(cases, 'caution_suffix')) {
      test('안전 메모: ${c['cautions']} ${c['escalate']}', () {
        final List<String> cautions = strings(c['cautions']);
        final bool escalate = c['escalate']! as bool;
        expect(cautionSuffix(cautions, escalate, en: false), c['ko']);
        expect(cautionSuffix(cautions, escalate, en: true), c['en']);
      });
    }
  });
}

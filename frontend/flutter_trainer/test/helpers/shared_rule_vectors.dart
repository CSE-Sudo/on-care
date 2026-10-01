import 'dart:convert';
import 'dart:io';

/// `shared/oncare_rules/vectors/<name>.json` — 서버 pytest 가 함께 읽는 입력 표.
///
/// 같은 표를 서버(`tests/test_shared_rules_vectors.py`)와 이 앱의 테스트가 읽어
/// 두 쪽이 같은 입력에 같은 값을 내는지 본다(#2860, #2861, #2897).
Map<String, Object?> loadSharedRuleVectors(String name) =>
    jsonDecode(
          File(
            '../../shared/oncare_rules/vectors/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

/// 표의 `[입력, 기대값]` 쌍 목록.
List<(Object?, Object?)> vectorPairs(
  Map<String, Object?> vectors,
  String key,
) => <(Object?, Object?)>[
  for (final Object? row in vectors[key]! as List<Object?>)
    ((row! as List<Object?>)[0], (row as List<Object?>)[1]),
];

/// 표의 객체 행 목록.
List<Map<String, Object?>> vectorRows(
  Map<String, Object?> vectors,
  String key,
) => <Map<String, Object?>>[
  for (final Object? row in vectors[key]! as List<Object?>)
    (row! as Map<String, Object?>),
];

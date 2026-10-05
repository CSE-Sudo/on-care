/// 효과 표 영어 문구가 원본 표의 `en` 칸과 같다(#2906).
///
/// 원본은 `shared/routine_effects/routine_effects.json` 이다. 서버와 트레이너 웹은
/// 한국어 칸(`default`·`by_goal`)을 대조하고, 영어 문구는 이 패키지 한 벌을 두
/// 앱이 함께 쓴다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Map<String, Object?> _table() =>
    jsonDecode(
          File('../routine_effects/routine_effects.json').readAsStringSync(),
        )
        as Map<String, Object?>;

/// 표의 빈 칸이 아닌 한국어 문장 전부.
Set<String> _sentences(Map<String, Object?> table) {
  final Set<String> out = <String>{};
  void collect(Object? node) {
    if (node is String && node.isNotEmpty) out.add(node);
    if (node is Map) node.values.forEach(collect);
  }

  collect(table['default']);
  collect(table['by_goal']);
  return out;
}

void main() {
  final Map<String, Object?> table = _table();

  test('영어 문구 표가 원본 표의 en 칸과 같다', () {
    expect(kRoutineEffectEnglish, table['en']);
  });

  test('한국어 표의 모든 문장에 영어 문구가 있다 — 남는 번역도 없다', () {
    expect(kRoutineEffectEnglish.keys.toSet(), _sentences(table));
  });

  test('영어 화면은 영어 문구, 한국어 화면은 표의 문장 그대로다', () {
    expect(routineEffectText('근력 향상', languageCode: 'en'), 'Builds strength');
    expect(
      routineEffectText('근력 향상', languageCode: 'en_US'),
      'Builds strength',
    );
    expect(routineEffectText('근력 향상', languageCode: 'ko'), '근력 향상');
  });

  test('트레이너가 직접 쓴 문장은 그대로 둔다', () {
    expect(routineEffectText('오른쪽 어깨 보호', languageCode: 'en'), '오른쪽 어깨 보호');
  });
}

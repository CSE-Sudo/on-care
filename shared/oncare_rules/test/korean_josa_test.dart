import 'package:oncare_rules/oncare_rules.dart';
import 'package:test/test.dart';

import 'vectors.dart';

void main() {
  final Map<String, Object?> vectors = loadVectors('korean_josa');

  group('조사 고르기 — 서버 korean_josa 와 같은 입력 표', () {
    for (final Object? row in vectors['cases']! as List<Object?>) {
      final Map<String, Object?> c = row! as Map<String, Object?>;
      final String word = c['word']! as String;
      test('"$word"', () {
        expect(hasFinalConsonant(word), c['has_final'], reason: 'has_final');
        expect(endsWithHangul(word), c['ends_with_hangul'], reason: 'hangul');
        expect(josa(word, '을', '를'), c['obj'], reason: '을/를');
        expect(josa(word, '은', '는'), c['topic'], reason: '은/는');
        expect(josa(word, '이', '가'), c['subj'], reason: '이/가');
        expect(josa(word, '으로', '로'), c['dir'], reason: '으로/로');
      });
    }
  });

  test('괄호로 끝나면 괄호 앞 글자로 고른다', () {
    expect(withJosa('레그 프레스(머신)', '을', '를'), '레그 프레스(머신)을');
  });

  test('숫자로 끝나면 읽는 소리로 고른다', () {
    expect(withJosa('플랭크 60', '은', '는'), '플랭크 60은');
    expect(withJosa('하체 근력 2', '을', '를'), '하체 근력 2를');
  });

  test('두 꼴(을(를))을 쓰지 않는다', () {
    for (final Object? row in vectors['cases']! as List<Object?>) {
      final String word = (row! as Map<String, Object?>)['word']! as String;
      expect(josa(word, '을', '를'), isNot(contains('(')));
    }
  });

  test('ㄹ 받침은 으로가 아니라 로다', () {
    expect(withJosa('덤벨 컬', '으로', '로'), '덤벨 컬로');
    expect(withJosa('3일', '으로', '로'), '3일로');
    expect(withJosa('나트륨', '으로', '로'), '나트륨으로');
  });
}

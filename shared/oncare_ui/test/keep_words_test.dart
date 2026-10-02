import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 두 앱이 함께 쓰는 줄바꿈 유지 함수(#2908).
void main() {
  test('줄바꿈 금지 문자는 U+2060, 붙는 공백은 U+00A0 이다', () {
    expect(kWordJoiner.runes.single, 0x2060);
    expect(kNoBreakSpace.runes.single, 0x00A0);
  });

  group('keepWords', () {
    test('낱말 안 글자 사이에만 줄바꿈 금지 문자를 끼운다', () {
      expect(keepWords('받아요'), '받⁠아⁠요');
      expect(keepWords('1인 식판'), '1⁠인 식⁠판');
    });

    test('띄어쓰기는 그대로 남아 그 자리에서만 줄이 바뀐다', () {
      const String text = '100P를 걸고 이번 주 3회 운동하면 200P를 돌려받아요';
      final String kept = keepWords(text);
      expect(kept.split(' ').length, text.split(' ').length);
      expect(kept.replaceAll(kWordJoiner, ''), text);
    });

    test('한 글자 낱말·빈 문자열은 그대로다', () {
      expect(keepWords(''), '');
      expect(keepWords('주 1회'), '주 1⁠회');
    });

    test('BMP 밖 글자(이모지)를 쪼개지 않는다', () {
      expect(keepWords('🔥불'), '🔥⁠불');
    });
  });

  group('keepTogether', () {
    test('띄어쓰기도 붙는 공백으로 바꿔 어디서도 줄이 바뀌지 않는다', () {
      expect(keepTogether('라 토핑'), '라⁠ ⁠토⁠핑');
    });

    test('금지 문자와 붙는 공백을 걷어내면 원문이다', () {
      const String text = '그래놀라 토핑 요거트';
      expect(
        keepTogether(
          text,
        ).replaceAll(kWordJoiner, '').replaceAll(kNoBreakSpace, ' '),
        text,
      );
      expect(keepTogether(text).contains(' '), isFalse);
    });
  });
}

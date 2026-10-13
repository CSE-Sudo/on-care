import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/search_match.dart';

void main() {
  const List<String> sinchon = <String>['온케어짐 신촌점', '서울 서대문구 신촌로 120'];

  group('normalizeSearchText', () {
    test('소문자로 바꾸고 띄어쓰기를 모두 뺀다', () {
      expect(normalizeSearchText(' OnCare  Gym\tSinchon '), 'oncaregymsinchon');
      expect(normalizeSearchText('온케어짐 신촌점'), '온케어짐신촌점');
    });
  });

  group('searchTerms', () {
    test('띄어쓰기 종류와 개수에 상관없이 단어로 나눈다', () {
      expect(searchTerms('  신촌\t헬스메이트 \n'), <String>['신촌', '헬스메이트']);
    });

    test('빈 검색어는 단어가 없다', () {
      expect(searchTerms(''), isEmpty);
      expect(searchTerms('   '), isEmpty);
    });
  });

  group('matchesSearchQuery', () {
    test('저장된 이름을 그대로 치면 맞는다', () {
      expect(matchesSearchQuery('온케어짐 신촌점', sinchon), isTrue);
    });

    test('붙여 쓴 검색어도 맞는다', () {
      expect(matchesSearchQuery('온케어짐신촌', sinchon), isTrue);
    });

    test('단어 순서가 달라도 맞는다', () {
      expect(matchesSearchQuery('신촌 온케어짐', sinchon), isTrue);
    });

    test('이름 단어와 주소 단어를 섞어도 맞는다', () {
      expect(matchesSearchQuery('서대문구 온케어짐', sinchon), isTrue);
    });

    test('대소문자를 보지 않는다', () {
      expect(
        matchesSearchQuery('oncare GYM', <String>['OnCare Gym Sinchon']),
        isTrue,
      );
    });

    test('단어 하나라도 없으면 맞지 않는다', () {
      expect(matchesSearchQuery('온케어짐 강남', sinchon), isFalse);
      expect(matchesSearchQuery('스포애니', sinchon), isFalse);
    });

    test('빈 검색어는 모두 맞는다', () {
      expect(matchesSearchQuery('', sinchon), isTrue);
      expect(matchesSearchQuery('  ', sinchon), isTrue);
    });

    test('비교 대상이 없으면 검색어가 있을 때 맞지 않는다', () {
      expect(matchesSearchQuery('신촌', const <String>[]), isFalse);
    });
  });
}

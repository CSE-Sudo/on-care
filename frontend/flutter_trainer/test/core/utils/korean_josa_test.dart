import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/korean_josa.dart';

void main() {
  group('withObjectJosa', () {
    test('받침이 있으면 을, 없으면 를 을 붙인다', () {
      expect(withObjectJosa('벤치프레스'), '벤치프레스를');
      expect(withObjectJosa('저강도 걷기'), '저강도 걷기를');
      expect(withObjectJosa('코어 스트레칭'), '코어 스트레칭을');
      expect(withObjectJosa('힙 브리지'), '힙 브리지를');
    });

    test('숫자로 끝나면 읽은 소리를 따른다', () {
      // 하체 근력 `일` 에는 받침이 있고, `이` 에는 없다.
      expect(withObjectJosa('하체 근력 1'), '하체 근력 1을');
      expect(withObjectJosa('하체 근력 2'), '하체 근력 2를');
    });

    test('빈 이름에도 터지지 않는다', () {
      expect(withObjectJosa(''), '를');
    });
  });

  group('withTopicJosa', () {
    test('받침이 있으면 은, 없으면 는 을 붙인다', () {
      expect(withTopicJosa('코어 스트레칭'), '코어 스트레칭은');
      expect(withTopicJosa('저강도 걷기'), '저강도 걷기는');
    });
  });
}

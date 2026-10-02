import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  test('낱말 안에만 줄바꿈 금지 문자를 넣고, 두 번 거쳐도 같다 (#2969)', () {
    const String text = '단백질 목표를 넘었어요';
    final String once = keepWords(text);
    expect(
      once,
      '단$kWordJoiner백$kWordJoiner질 목$kWordJoiner표$kWordJoiner를 '
      '넘$kWordJoiner었$kWordJoiner어$kWordJoiner요',
    );
    expect(keepWords(once), once);
    expect(withoutWordJoiners(once), text);
  });
}

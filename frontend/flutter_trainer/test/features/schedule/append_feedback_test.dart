import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';

/// `일정 추가` 로 기존 회차에 붙일 때의 피드백 규칙(#2374). 서버
/// `_append_feedback` 와 같아야 데모와 실 API 가 같은 결과를 낸다.
void main() {
  test('기존 피드백 뒤에 줄을 바꿔 이어 붙인다', () {
    expect(appendFeedback('어깨 조심', '하체 위주로 짰어요'), '어깨 조심\n하체 위주로 짰어요');
  });

  test('기존 피드백이 없으면 새 글만 남는다', () {
    expect(appendFeedback('', ' 하체 위주로 짰어요 '), '하체 위주로 짰어요');
    expect(appendFeedback('   ', '하체 위주로 짰어요'), '하체 위주로 짰어요');
  });

  test('새 글이 비어 있으면 기존 피드백을 그대로 둔다', () {
    expect(appendFeedback('어깨 조심', ''), '어깨 조심');
    expect(appendFeedback('어깨 조심', '   '), '어깨 조심');
  });
}

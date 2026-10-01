/// 회원 메시지가 다시 그려질 때의 스크롤 규칙. (#2749)
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/clients/presentation/controllers/chat_scroll.dart';

ChatEdges _edges(String? oldest, String? newest, int count) =>
    ChatEdges(oldestId: oldest, newestId: newest, count: count);

void main() {
  test('처음 그리면 맨 아래로 간다', () {
    expect(
      chatScrollAction(null, _edges('a', 'z', 50)),
      ChatScrollAction.toBottom,
    );
  });

  test('바뀐 것이 없으면 그대로 둔다 — 폴링이 같은 쪽을 다시 줘도 흔들지 않는다', () {
    expect(
      chatScrollAction(_edges('a', 'z', 50), _edges('a', 'z', 50)),
      ChatScrollAction.none,
    );
  });

  test('뒤에 새 메시지가 붙으면 맨 아래로 간다', () {
    expect(
      chatScrollAction(_edges('a', 'z', 50), _edges('a', 'zz', 51)),
      ChatScrollAction.toBottom,
    );
  });

  test('앞에 이전 쪽이 붙으면 보던 자리를 지킨다', () {
    expect(
      chatScrollAction(_edges('m070', 'm119', 50), _edges('m020', 'm119', 100)),
      ChatScrollAction.keepPosition,
    );
  });

  test('앞뒤가 함께 바뀌면 새 메시지를 보여 준다', () {
    expect(
      chatScrollAction(_edges('m070', 'm119', 50), _edges('m020', 'm120', 101)),
      ChatScrollAction.toBottom,
    );
  });

  test('빈 대화에 처음 메시지가 오면 맨 아래로 간다', () {
    expect(
      chatScrollAction(_edges(null, null, 0), _edges('a', 'a', 1)),
      ChatScrollAction.toBottom,
    );
  });

  test('양 끝은 그대로인데 가운데만 늘면(틈 메우기) 자리를 지킨다', () {
    expect(
      chatScrollAction(_edges('a', 'z', 100), _edges('a', 'z', 110)),
      ChatScrollAction.keepPosition,
    );
  });
}

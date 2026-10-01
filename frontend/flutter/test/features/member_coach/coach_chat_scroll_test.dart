/// 트레이너 채팅을 새로 그릴 때의 스크롤 규칙. (#2640)
///
/// 옛 쪽이 **앞에** 붙으면 보던 자리를 지키고, 새 말이 **뒤에** 붙을 때만 맨
/// 아래로 내린다. 예전에는 메시지 수만 보고 언제나 맨 아래로 내렸다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_scroll.dart';

ChatEdges _edges(String? oldest, String? newest, int count) =>
    ChatEdges(oldestId: oldest, newestId: newest, count: count);

void main() {
  test('처음 그릴 때는 맨 아래로 내린다', () {
    expect(
      chatScrollAction(null, _edges('m0', 'm49', 50)),
      ChatScrollAction.toBottom,
    );
  });

  test('바뀐 것이 없으면 그대로 둔다', () {
    expect(
      chatScrollAction(_edges('m0', 'm49', 50), _edges('m0', 'm49', 50)),
      ChatScrollAction.none,
    );
  });

  test('새 말이 뒤에 붙으면 맨 아래로 내린다', () {
    expect(
      chatScrollAction(_edges('m0', 'm49', 50), _edges('m0', 'm50', 51)),
      ChatScrollAction.toBottom,
    );
  });

  test('옛 쪽이 앞에 붙으면 보던 자리를 지킨다', () {
    expect(
      chatScrollAction(_edges('m50', 'm99', 50), _edges('m0', 'm99', 100)),
      ChatScrollAction.keepPosition,
    );
  });

  test('앞과 뒤가 함께 바뀌면 새 말을 보여 준다', () {
    expect(
      chatScrollAction(_edges('m50', 'm99', 50), _edges('m0', 'm100', 101)),
      ChatScrollAction.toBottom,
    );
  });

  test('보내는 중인 사진이 끝에 붙으면 맨 아래로 내린다', () {
    expect(
      chatScrollAction(
        _edges('m0', 'm49', 50),
        _edges('m0', 'pending-photo-1', 51),
      ),
      ChatScrollAction.toBottom,
    );
  });

  test('빈 대화에 첫 메시지가 오면 맨 아래로 내린다', () {
    expect(
      chatScrollAction(_edges(null, null, 0), _edges('m0', 'm0', 1)),
      ChatScrollAction.toBottom,
    );
  });

  test('양 끝은 그대로고 가운데만 늘면 읽던 자리를 흔들지 않는다', () {
    expect(
      chatScrollAction(_edges('m0', 'm99', 70), _edges('m0', 'm99', 100)),
      ChatScrollAction.keepPosition,
    );
  });
}

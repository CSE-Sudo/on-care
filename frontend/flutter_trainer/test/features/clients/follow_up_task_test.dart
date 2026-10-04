import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';

void main() {
  test('앱이 모르는 갈래는 일반 후속 관리로 읽는다', () {
    // 서버가 새 값을 먼저 내보내도 목록 전체가 실패하지 않는다.
    expect(FollowUpContext.fromWire('billing'), FollowUpContext.general);
  });
}

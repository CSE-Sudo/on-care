/// 후속 관리 할 일이 여는 화면 (#869).
///
/// 대시보드 `FollowUpCard` 를 지우면서(#3104) 그 위젯 테스트에 함께 있던
/// 라우트 표 단언만 옮겨 왔다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';

void main() {
  group('followUpTarget', () {
    test('갈래마다 이미 있는 화면으로 보낸다', () {
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.message.wire),
        AppRoutes.messagesFor('m1'),
      );
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.program.wire),
        AppRoutes.coachingFor('m1'),
      );
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.diet.wire),
        AppRoutes.clientDetail('m1', section: 'diet'),
      );
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.exercise.wire),
        AppRoutes.clientDetail('m1', section: 'workout'),
      );
      expect(
        AppRoutes.followUpTarget('m1', FollowUpContext.schedule.wire),
        AppRoutes.scheduleAt(),
      );
    });

    test('앱이 모르는 갈래는 회원 상세로 데려간다', () {
      // 서버가 새 값을 먼저 내보내도 목록이 죽지 않고, 적어도 그 회원 화면까지는
      // 간다.
      expect(
        AppRoutes.followUpTarget('m1', 'billing'),
        AppRoutes.clientDetail('m1'),
      );
      expect(FollowUpContext.fromWire('billing'), FollowUpContext.general);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/shell/nav_destinations.dart';

void main() {
  test('회원 메뉴는 숫자 배지를 표시하지 않는다', () {
    final clients = navDestinations.singleWhere(
      (destination) => destination.label == NavLabel.clients,
    );
    final messages = navDestinations.singleWhere(
      (destination) => destination.label == NavLabel.messages,
    );

    expect(clients.badge, NavBadge.none);
    expect(messages.badge, NavBadge.unreadMessages);
  });

  // 배지가 '오늘 예약 수' 가 아니라 '남은 일감' 을 가리킨다는 계약(#860).
  test('스케줄 메뉴 배지는 남은 예정 세션을 가리킨다', () {
    final schedule = navDestinations.singleWhere(
      (destination) => destination.label == NavLabel.schedule,
    );

    expect(schedule.badge, NavBadge.todayPendingSessions);
  });
}

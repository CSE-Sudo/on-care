import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/notification/data/repositories/mock_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';

void main() {
  _demoReadStateTests();
}

/// 데모 저장소가 읽음을 기억하는지 — #636 리뷰.
///
/// 예전에는 읽음이 no-op 이라 미읽음 수를 물으면 늘 처음 상태를 답했다. 데모에서
/// "모두 읽음" 을 눌러도 벨의 점이 남아 목록과 배지가 서로 다른 말을 했다.
void _demoReadStateTests() {
  test('데모에서 모두 읽음 처리하면 미읽음 수가 0 이 된다', () async {
    final repo = MockNotificationRepository();
    expect(await repo.unreadCount(), greaterThan(0));

    await repo.markAllRead();

    expect(await repo.unreadCount(), 0);
    expect((await repo.fetchPage()).every((AlertItem a) => a.read), isTrue);
  });

  test('데모에서 한 건 읽으면 그만큼만 줄어든다', () async {
    final repo = MockNotificationRepository();
    final int before = await repo.unreadCount();
    final AlertItem unread = (await repo.fetchPage()).firstWhere(
      (AlertItem a) => !a.read,
    );

    await repo.markRead(unread.id);

    expect(await repo.unreadCount(), before - 1);
  });
}

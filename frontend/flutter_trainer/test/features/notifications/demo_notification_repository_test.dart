/// 데모 알림함과 알림 시드. (#2628)
///
/// 알림은 다 확인해도 이전 기록이 남는 화면이다. 데모에도 과거 알림이 있고,
/// 읽음 처리가 로컬에 남으며, 다음 날 다시 심어도 읽은 기록이 사라지지 않는다.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

import '../../helpers/fixed_clock.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db, clock: kMidWeekKst);
  });
  tearDown(() => db.close());

  test('데모 알림함은 과거 알림을 최신순으로 준다', () async {
    final DemoNotificationRepository repo = DemoNotificationRepository(db);

    final TrainerNotificationPage page = await repo.fetch();
    expect(page.items, isNotEmpty);
    expect(page.hasMore, isFalse);
    for (int i = 1; i < page.items.length; i++) {
      expect(
        page.items[i - 1].createdAt.isAfter(page.items[i].createdAt),
        isTrue,
      );
    }
    // 트레이너가 받는 종류를 골고루 — 회원 주의사항 알림(#2619)도 있다.
    expect(
      page.items.map((TrainerNotification n) => n.template),
      containsAll(<String>[
        'trainer_health_notes',
        'trainer_member_message',
        'trainer_reservation_booked',
        'trainer_health_goal',
        'trainer_invite_accepted',
        'trainer_consult_requested',
      ]),
    );
    // 회원 이름은 심어 둔 회원 행에서 온다.
    expect(page.items.first.args['member_name'], isNotEmpty);
    expect(page.items.every((n) => n.subjectId != null), isTrue);
  });

  test('읽음 처리가 남고, 다시 심어도 지워지지 않는다', () async {
    final DemoNotificationRepository repo = DemoNotificationRepository(db);
    final int unread = await repo.unreadCount();
    expect(unread, greaterThan(0));

    final String first = (await repo.fetch()).items
        .firstWhere((n) => !n.read)
        .id;
    await repo.markRead(first);
    expect(await repo.unreadCount(), unread - 1);

    // 다음 날 시드가 다시 돌아도 읽은 기록은 그대로다.
    await db.putValue('trainer_seeded_v56', '2020-01-01');
    await seedIfEmpty(db, clock: kMidWeekKst.add(const Duration(days: 1)));
    expect(await repo.unreadCount(), unread - 1);

    expect(await repo.markAllRead(), unread - 1);
    expect(await repo.unreadCount(), 0);
    expect((await repo.fetch()).items, isNotEmpty, reason: '다 읽어도 기록은 남는다');
  });

  test('배지는 읽음 처리를 바로 따라간다', () async {
    final DemoNotificationRepository repo = DemoNotificationRepository(db);
    final List<int> counts = <int>[];
    final sub = repo.watchUnreadCount().listen(counts.add);
    await pumpEventQueue();
    await repo.markAllRead();
    await pumpEventQueue();
    await sub.cancel();

    expect(counts.first, greaterThan(0));
    expect(counts.last, 0);
  });

  test('상대 시각은 서버와 같은 말이다', () {
    final DateTime now = DateTime.utc(2026, 9, 30, 12);
    String ago(Duration d, {bool korean = true}) =>
        demoTimeAgo(now.subtract(d), now: now, korean: korean);

    expect(ago(const Duration(seconds: 30)), '방금 전');
    expect(ago(const Duration(minutes: 40)), '40분 전');
    expect(ago(const Duration(hours: 2)), '2시간 전');
    expect(ago(const Duration(days: 3)), '3일 전');
    expect(ago(const Duration(hours: 1), korean: false), '1 hour ago');
    expect(ago(const Duration(days: 2), korean: false), '2 days ago');
  });
}

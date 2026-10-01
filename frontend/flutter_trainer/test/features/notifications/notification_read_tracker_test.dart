/// 알림 한 건의 읽음 처리와 배지의 미리 빼기. (#2762)
///
/// 화면 위젯이 사라져도 끝까지 가야 하므로 앱 전체의 [ProviderContainer] 만
/// 쓴다. 배지는 요청 전에 미리 줄이고, 서버가 센 새 숫자가 오면 미리 뺀 몫을
/// 거둔다. 실패하면 되돌린다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

TrainerNotification _n(String id, {bool read = false}) => TrainerNotification(
  id: id,
  title: id,
  body: '',
  kind: TrainerNotificationKind.other,
  read: read,
  createdAt: DateTime.utc(2026, 8, 9, 10),
  timeAgo: '방금 전',
);

class _Repo implements TrainerNotificationRepository {
  _Repo(this.rows, {this.next});

  List<TrainerNotification> rows;
  final TrainerNotificationCursor? next;
  Completer<void>? hold;
  bool failRead = false;
  int unreadReads = 0;

  @override
  bool get supportsInbox => true;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async => before == null
      ? TrainerNotificationPage(items: rows, next: next)
      : TrainerNotificationPage(items: <TrainerNotification>[_n('old-1')]);

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.fromFuture(fetch());

  @override
  Future<int> unreadCount() async {
    unreadReads++;
    return rows.where((TrainerNotification r) => !r.read).length;
  }

  @override
  Stream<int> watchUnreadCount() => Stream<int>.fromFuture(unreadCount());

  @override
  Future<void> markRead(String id) async {
    final Completer<void>? wait = hold;
    if (wait != null) await wait.future;
    if (failRead) throw StateError('read failed');
    rows = <TrainerNotification>[
      for (final TrainerNotification r in rows)
        r.id == id ? r.copyWith(read: true) : r,
    ];
  }

  @override
  Future<int> markAllRead() async => 0;
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Repo repo;
  late ProviderContainer container;
  late ProviderSubscription<int?> badge;

  setUp(() async {
    repo = _Repo(<TrainerNotification>[_n('a'), _n('b')]);
    container = ProviderContainer(
      overrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    // 화면 머리의 배지처럼 늘 구독한다.
    badge = container.listen<int?>(trainerUnreadBadgeProvider, (_, _) {});
    await _flush();
  });

  tearDown(() {
    badge.close();
    container.dispose();
  });

  test('처음에는 서버 숫자를 그대로 보여 준다', () {
    expect(badge.read(), 2);
  });

  test('요청이 끝나기 전에 배지를 미리 줄인다', () async {
    repo.hold = Completer<void>();
    unawaited(NotificationReadTracker(container).markRead('a'));
    await _flush();

    expect(container.read(trainerPendingNotificationReadsProvider), <String>{
      'a',
    });
    expect(badge.read(), 1);

    repo.hold!.complete();
    await _flush();
    // 서버가 센 새 숫자(1)가 오면 미리 뺀 몫을 거둔다 — 두 번 빼지 않는다.
    expect(container.read(trainerPendingNotificationReadsProvider), isEmpty);
    expect(badge.read(), 1);
  });

  test('성공하면 미읽음 수를 다시 읽는다 — 폴링을 기다리지 않는다', () async {
    final int before = repo.unreadReads;
    await NotificationReadTracker(container).markRead('a');
    await _flush();

    expect(repo.unreadReads, greaterThan(before));
    expect(badge.read(), 1);
  });

  test('실패하면 미리 뺀 몫을 돌려 둔다', () async {
    repo.failRead = true;
    await NotificationReadTracker(container).markRead('a');
    await _flush();

    expect(container.read(trainerPendingNotificationReadsProvider), isEmpty);
    expect(badge.read(), 2);
  });

  test('같은 알림을 두 번 눌러도 한 번만 뺀다', () async {
    repo.hold = Completer<void>();
    final NotificationReadTracker tracker = NotificationReadTracker(container);
    unawaited(tracker.markRead('a'));
    unawaited(tracker.markRead('a'));
    await _flush();

    expect(badge.read(), 1);
    repo.hold!.complete();
    await _flush();
    expect(badge.read(), 1);
  });

  test('배지는 0 아래로 내려가지 않는다', () async {
    repo
      ..rows = <TrainerNotification>[_n('a')]
      ..hold = Completer<void>();
    container.invalidate(trainerUnreadNotificationsProvider);
    await _flush();
    final NotificationReadTracker tracker = NotificationReadTracker(container);
    unawaited(tracker.markRead('a'));
    // 서버에서 이미 읽힌 옛 행을 누른 경우.
    unawaited(tracker.markRead('stale'));
    await _flush();

    expect(badge.read(), 0);
    repo.hold!.complete();
    await _flush();
  });

  test('알림 화면이 이어 받은 과거 쪽에도 읽음을 비춘다', () async {
    repo = _Repo(<TrainerNotification>[
      _n('a'),
    ], next: const TrainerNotificationCursor(before: 't', beforeId: 'a'));
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    final ProviderSubscription<TrainerNotificationPaging> paging = c.listen(
      trainerNotificationPagingProvider,
      (_, _) {},
    );
    addTearDown(paging.close);
    await c
        .read(trainerNotificationPagingProvider.notifier)
        .loadMore(await repo.fetch());
    expect(
      paging.read().items.firstWhere((n) => n.id == 'old-1').read,
      isFalse,
    );

    await NotificationReadTracker(c).markRead('old-1');
    await _flush();

    expect(paging.read().items.firstWhere((n) => n.id == 'old-1').read, isTrue);
  });

  test('알림 화면을 떠났으면 이어 받기 상태를 새로 만들지 않는다', () async {
    await NotificationReadTracker(container).markRead('a');
    await _flush();

    expect(container.exists(trainerNotificationPagingProvider), isFalse);
  });

  test('계정이 바뀌면 미리 뺀 몫도 비운다', () async {
    repo.hold = Completer<void>();
    unawaited(NotificationReadTracker(container).markRead('a'));
    await _flush();
    expect(container.read(trainerPendingNotificationReadsProvider), isNotEmpty);

    container.read(accountScopeProvider.notifier).state++;
    await _flush();
    expect(container.read(trainerPendingNotificationReadsProvider), isEmpty);

    repo.hold!.complete();
    await _flush();
  });
}

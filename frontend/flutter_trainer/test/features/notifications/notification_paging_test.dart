/// 트레이너 알림함 쪽 나눔 — 커서·쪽 모델, 이어 받기 컨트롤러, 합치기. (#2293)
///
/// 전에는 첫 쪽(100건)이 전부라, 미읽음 배지는 전체를 세는데 그보다 오래된
/// 미읽음은 목록 어디에서도 볼 수 없었다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

TrainerNotification _n(String id, {bool read = false}) => TrainerNotification(
  id: id,
  title: '알림 $id',
  body: '',
  kind: TrainerNotificationKind.message,
  read: read,
  createdAt: DateTime.utc(2026, 9, 1, 9),
  timeAgo: '',
);

TrainerNotificationCursor _c(String id) => TrainerNotificationCursor(
  before: '2026-09-01T09:00:00+00:00',
  beforeId: id,
);

/// 커서마다 정해 둔 쪽을 돌려주는 저장소. 부른 커서를 기록한다.
class _PagedRepo implements TrainerNotificationRepository {
  _PagedRepo(this.pages);

  /// 커서의 `beforeId` → 그다음 쪽. 첫 쪽은 `''`.
  final Map<String, TrainerNotificationPage> pages;
  final List<TrainerNotificationCursor?> calls = <TrainerNotificationCursor?>[];
  int failuresLeft = 0;
  Completer<void>? gate;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async {
    calls.add(before);
    if (gate != null) await gate!.future;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('network down');
    }
    return pages[before?.beforeId ?? ''] ?? TrainerNotificationPage.empty;
  }

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.fromFuture(fetch());

  @override
  Future<int> unreadCount() async => 0;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.value(0);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

void main() {
  group('TrainerNotificationCursor', () {
    test('두 헤더가 모두 있어야 커서다', () {
      expect(
        TrainerNotificationCursor.fromHeaders('2026-09-01T09:00:00Z', 'n-1'),
        const TrainerNotificationCursor(
          before: '2026-09-01T09:00:00Z',
          beforeId: 'n-1',
        ),
      );
      expect(TrainerNotificationCursor.fromHeaders(null, 'n-1'), isNull);
      expect(TrainerNotificationCursor.fromHeaders('2026', null), isNull);
      expect(TrainerNotificationCursor.fromHeaders('', 'n-1'), isNull);
      expect(TrainerNotificationCursor.fromHeaders('2026', ''), isNull);
      expect(TrainerNotificationCursor.fromHeaders(null, null), isNull);
    });

    test('받은 글자를 그대로 쿼리로 되돌린다 — 시각을 다시 쓰지 않는다', () {
      const cursor = TrainerNotificationCursor(
        before: '2026-09-01T09:00:00.123456+00:00',
        beforeId: 'noti-abc',
      );
      expect(cursor.toQuery(), <String, String>{
        'before': '2026-09-01T09:00:00.123456+00:00',
        'before_id': 'noti-abc',
      });
    });

    test('같은 값이면 같다', () {
      expect(_c('a'), _c('a'));
      expect(_c('a').hashCode, _c('a').hashCode);
      expect(_c('a'), isNot(_c('b')));
    });
  });

  group('TrainerNotificationPage', () {
    test('커서가 있을 때만 더 있다', () {
      expect(TrainerNotificationPage.empty.hasMore, isFalse);
      expect(TrainerNotificationPage.empty.items, isEmpty);
      expect(TrainerNotificationPage(next: _c('x')).hasMore, isTrue);
    });
  });

  group('TrainerNotification.copyWith', () {
    test('읽음만 바꾸고 나머지는 그대로 둔다', () {
      final TrainerNotification original = TrainerNotification(
        id: 'n-1',
        title: '새 예약',
        body: '본문',
        kind: TrainerNotificationKind.reservation,
        read: false,
        createdAt: DateTime.utc(2026, 9, 2),
        timeAgo: '3분 전',
        subjectId: 'member-1',
        template: 'trainer_reservation_booked',
        args: const <String, Object?>{'member_name': '지수'},
        targetDate: '2026-09-02',
      );

      final TrainerNotification read = original.copyWith(read: true);

      expect(read.read, isTrue);
      expect(read.id, original.id);
      expect(read.title, original.title);
      expect(read.body, original.body);
      expect(read.kind, original.kind);
      expect(read.createdAt, original.createdAt);
      expect(read.timeAgo, original.timeAgo);
      expect(read.subjectId, original.subjectId);
      expect(read.template, original.template);
      expect(read.args, original.args);
      expect(read.targetDate, original.targetDate);
      expect(original.copyWith().read, isFalse);
    });
  });

  group('TrainerNotificationPagingController', () {
    late _PagedRepo repo;
    late TrainerNotificationPagingController controller;
    final TrainerNotificationPage first = TrainerNotificationPage(
      items: <TrainerNotification>[_n('a'), _n('b')],
      next: _c('b'),
    );

    setUp(() {
      repo = _PagedRepo(<String, TrainerNotificationPage>{
        'b': TrainerNotificationPage(
          items: <TrainerNotification>[_n('c'), _n('d')],
          next: _c('d'),
        ),
        'd': TrainerNotificationPage(items: <TrainerNotification>[_n('e')]),
      });
      controller = TrainerNotificationPagingController(repo);
    });

    tearDown(() => controller.dispose());

    test('처음에는 아무것도 받지 않았다', () {
      expect(controller.state.started, isFalse);
      expect(controller.state.items, isEmpty);
      expect(controller.state.loading, isFalse);
      expect(controller.state.error, isNull);
    });

    test('첫 이어 받기는 첫 쪽 커서에서 시작하고 첫 쪽을 붙잡아 둔다', () async {
      await controller.loadMore(first);

      expect(repo.calls, <TrainerNotificationCursor?>[_c('b')]);
      expect(controller.state.started, isTrue);
      expect(controller.state.items.map((n) => n.id), <String>[
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(controller.state.next, _c('d'));
    });

    test('다음 이어 받기는 받은 쪽의 커서를 따른다', () async {
      await controller.loadMore(first);
      await controller.loadMore(first);

      expect(repo.calls, <TrainerNotificationCursor?>[_c('b'), _c('d')]);
      expect(controller.state.items.map((n) => n.id), <String>[
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
      expect(controller.state.next, isNull);
    });

    test('끝에 닿으면 더 부르지 않는다', () async {
      await controller.loadMore(first);
      await controller.loadMore(first);
      await controller.loadMore(first);

      expect(repo.calls, hasLength(2));
    });

    test('첫 쪽이 마지막 쪽이면 부르지 않는다', () async {
      await controller.loadMore(
        TrainerNotificationPage(items: <TrainerNotification>[_n('a')]),
      );

      expect(repo.calls, isEmpty);
      expect(controller.state.started, isFalse);
    });

    test('받는 중에 또 불러도 한 번만 부른다', () async {
      repo.gate = Completer<void>();
      final Future<void> firstCall = controller.loadMore(first);
      expect(controller.state.loading, isTrue);
      final Future<void> second = controller.loadMore(first);
      repo.gate!.complete();
      await Future.wait(<Future<void>>[firstCall, second]);

      expect(repo.calls, hasLength(1));
      expect(controller.state.loading, isFalse);
    });

    test('겹쳐 온 알림은 한 번만 붙인다', () async {
      repo.pages['b'] = TrainerNotificationPage(
        items: <TrainerNotification>[_n('b'), _n('c')],
      );

      await controller.loadMore(first);

      expect(controller.state.items.map((n) => n.id), <String>['a', 'b', 'c']);
    });

    test('실패하면 목록은 그대로 두고 오류만 남긴다. 다시 부르면 지운다', () async {
      await controller.loadMore(first);
      repo.failuresLeft = 1;

      await controller.loadMore(first);

      expect(controller.state.error, isA<StateError>());
      expect(controller.state.loading, isFalse);
      expect(controller.state.items, hasLength(4));
      expect(controller.state.next, _c('d'));

      await controller.loadMore(first);

      expect(controller.state.error, isNull);
      expect(controller.state.items, hasLength(5));
      expect(repo.calls, <TrainerNotificationCursor?>[
        _c('b'),
        _c('d'),
        _c('d'),
      ]);
    });

    test('스크롤 이어 받기는 실패한 뒤에 되풀이하지 않는다', () async {
      repo.failuresLeft = 1;

      await controller.autoLoadMore(first);
      await controller.autoLoadMore(first);

      expect(repo.calls, hasLength(1));
      expect(controller.state.error, isNotNull);

      // 재시도 버튼(loadMore)은 부른다. 성공하면 스크롤 이어 받기도 돌아온다.
      await controller.loadMore(first);
      await controller.autoLoadMore(first);

      expect(repo.calls, <TrainerNotificationCursor?>[
        _c('b'),
        _c('b'),
        _c('d'),
      ]);
      expect(controller.state.items, hasLength(5));
    });

    test('첫 이어 받기가 실패해도 시작한 것으로 치지 않는다', () async {
      repo.failuresLeft = 1;

      await controller.loadMore(first);

      expect(controller.state.started, isFalse);
      expect(controller.state.error, isNotNull);
      expect(controller.state.items, isEmpty);
    });

    test('한 건 읽음을 받아 둔 쪽에 비춘다', () async {
      await controller.loadMore(first);

      controller.markRead('c');

      expect(
        controller.state.items.where((n) => n.read).map((n) => n.id),
        <String>['c'],
      );
      expect(controller.state.next, _c('d'));
    });

    test('모두 읽음을 받아 둔 쪽 전체에 비춘다', () async {
      await controller.loadMore(first);

      controller.markAllRead();

      expect(controller.state.items.every((n) => n.read), isTrue);
      expect(controller.state.items, hasLength(4));
      expect(controller.state.started, isTrue);
    });

    test('받아 둔 쪽이 없으면 읽음 처리는 아무것도 바꾸지 않는다', () {
      controller
        ..markRead('a')
        ..markAllRead();

      expect(controller.state.started, isFalse);
      expect(controller.state.items, isEmpty);
    });

    test('dispose 뒤에 끝난 요청은 상태를 건드리지 않는다', () async {
      repo.gate = Completer<void>();
      final TrainerNotificationPagingController short =
          TrainerNotificationPagingController(repo);
      final Future<void> pending = short.loadMore(first);
      short.dispose();
      repo.gate!.complete();

      await expectLater(pending, completes);
    });
  });

  group('mergeTrainerNotifications', () {
    final TrainerNotificationPage first = TrainerNotificationPage(
      items: <TrainerNotification>[_n('a'), _n('b')],
      next: _c('b'),
    );

    test('이어 받기 전에는 첫 쪽이 전부다', () {
      final TrainerNotificationInbox inbox = mergeTrainerNotifications(
        first,
        const TrainerNotificationPaging(),
      );

      expect(inbox.items.map((n) => n.id), <String>['a', 'b']);
      expect(inbox.hasMore, isTrue);
      expect(inbox.reachedEnd, isFalse);
      expect(inbox.loadingMore, isFalse);
      expect(inbox.loadMoreError, isNull);
    });

    test('짧은 알림함은 더 없지만 끝 표시도 없다', () {
      final TrainerNotificationInbox inbox = mergeTrainerNotifications(
        TrainerNotificationPage(items: <TrainerNotification>[_n('a')]),
        const TrainerNotificationPaging(),
      );

      expect(inbox.hasMore, isFalse);
      expect(inbox.reachedEnd, isFalse);
    });

    test('받는 중·실패 상태를 그대로 넘긴다', () {
      final StateError error = StateError('x');
      expect(
        mergeTrainerNotifications(
          first,
          const TrainerNotificationPaging(loading: true),
        ).loadingMore,
        isTrue,
      );
      expect(
        mergeTrainerNotifications(
          first,
          TrainerNotificationPaging(error: error),
        ).loadMoreError,
        same(error),
      );
    });

    test('첫 쪽 뒤에 과거 쪽을 붙인다', () {
      final TrainerNotificationInbox inbox = mergeTrainerNotifications(
        first,
        TrainerNotificationPaging(
          items: <TrainerNotification>[_n('a'), _n('b'), _n('c'), _n('d')],
          next: _c('d'),
          started: true,
        ),
      );

      expect(inbox.items.map((n) => n.id), <String>['a', 'b', 'c', 'd']);
      expect(inbox.hasMore, isTrue);
      expect(inbox.reachedEnd, isFalse);
    });

    test('새 알림에 밀려 첫 쪽에서 빠진 알림도 사라지지 않는다', () {
      // 이어 받은 뒤 새 알림 z 가 들어와 첫 쪽(2건)에서 b 가 밀려났다.
      final TrainerNotificationPage polled = TrainerNotificationPage(
        items: <TrainerNotification>[_n('z'), _n('a')],
        next: _c('a'),
      );
      final TrainerNotificationInbox inbox = mergeTrainerNotifications(
        polled,
        TrainerNotificationPaging(
          items: <TrainerNotification>[_n('a'), _n('b'), _n('c')],
          started: true,
        ),
      );

      expect(inbox.items.map((n) => n.id), <String>['z', 'a', 'b', 'c']);
      expect(inbox.reachedEnd, isTrue);
    });

    test('첫 쪽의 읽음 상태가 더 새 값이다', () {
      final TrainerNotificationInbox inbox = mergeTrainerNotifications(
        TrainerNotificationPage(
          items: <TrainerNotification>[_n('a', read: true)],
          next: _c('a'),
        ),
        TrainerNotificationPaging(
          items: <TrainerNotification>[_n('a'), _n('b')],
          started: true,
        ),
      );

      expect(inbox.items.first.read, isTrue);
      expect(inbox.items.map((n) => n.id), <String>['a', 'b']);
    });
  });

  group('trainerNotificationPagingProvider', () {
    test('저장소를 따라가고 구독이 끊기면 비운다', () async {
      final repo = _PagedRepo(<String, TrainerNotificationPage>{
        'b': TrainerNotificationPage(items: <TrainerNotification>[_n('c')]),
      });
      final container = ProviderContainer(
        overrides: <Override>[
          trainerNotificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        trainerNotificationPagingProvider,
        (_, _) {},
      );
      await container
          .read(trainerNotificationPagingProvider.notifier)
          .loadMore(
            TrainerNotificationPage(
              items: <TrainerNotification>[_n('a'), _n('b')],
              next: _c('b'),
            ),
          );
      expect(sub.read().items.map((n) => n.id), <String>['a', 'b', 'c']);

      sub.close();
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(trainerNotificationPagingProvider).started,
        isFalse,
      );
    });
  });
}

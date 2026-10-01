/// 알림 종 팝오버의 '모두 읽음' — 응답 전에 팝오버가 닫혀도 끝까지 간다. (#2884)
///
/// 전에는 응답을 기다린 뒤 닫힌 팝오버의 `ref` 로 이어 가다 예외가 나, 서버는
/// 모두 읽음인데 배지는 다음 폴링까지 남았다.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

import '../../helpers/pump_app.dart';

TrainerNotification _n(String id) => TrainerNotification(
  id: id,
  title: '알림 $id',
  body: '',
  kind: TrainerNotificationKind.other,
  read: false,
  createdAt: DateTime.utc(2026, 8, 9, 10),
  timeAgo: '3분 전',
);

/// '모두 읽음' 응답을 붙잡아 둘 수 있는 저장소. 쓰지 않는 멤버는 [Fake] 가 맡는다.
class _HeldRepository extends Fake implements TrainerNotificationRepository {
  _HeldRepository(this.rows);

  List<TrainerNotification> rows;
  final Completer<void> hold = Completer<void>();
  bool fail = false;
  int readAllCalls = 0;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async => TrainerNotificationPage(items: rows);

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.fromFuture(fetch());

  @override
  Future<int> unreadCount() async =>
      rows.where((TrainerNotification r) => !r.read).length;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.fromFuture(unreadCount());

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async {
    readAllCalls++;
    await hold.future;
    if (fail) throw StateError('read all failed');
    final int n = rows.length;
    rows = <TrainerNotification>[
      for (final TrainerNotification r in rows) r.copyWith(read: true),
    ];
    return n;
  }
}

void main() {
  final Finder bell = find.byKey(const ValueKey<String>('notification-bell'));
  final Finder badge = find.byKey(
    const ValueKey<String>('notification-bell-badge'),
  );
  final Finder panel = find.byKey(
    const ValueKey<String>('notification-bell-panel'),
  );
  final Finder readAll = find.byKey(
    const ValueKey<String>('notification-bell-read-all'),
  );

  /// 종을 펼쳐 '모두 읽음' 을 누르고, 응답이 오기 전에 종을 다시 눌러 닫는다.
  Future<ProviderContainer> readAllThenClose(
    WidgetTester tester,
    _HeldRepository repo,
  ) async {
    final ProviderContainer container = await pumpTrainerApp(
      tester,
      token: 'demo-token',
      extraOverrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await settle(tester);
    expect(badge, findsOneWidget);

    await tester.tap(bell);
    await settle(tester);
    await tester.tap(readAll);
    await tester.pump();
    await tester.tap(bell);
    await settle(tester);
    expect(panel, findsNothing);
    expect(repo.readAllCalls, 1);
    return container;
  }

  testWidgets('누르고 바로 닫아도 오류 없이 배지가 사라진다', (tester) async {
    await withWideSurface(tester, () async {
      final _HeldRepository repo = _HeldRepository(<TrainerNotification>[
        _n('1'),
        _n('2'),
      ]);
      final ProviderContainer container = await readAllThenClose(tester, repo);
      // 응답 전에도 배지는 이미 0 이다.
      expect(badge, findsNothing);

      repo.hold.complete();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(badge, findsNothing);
      expect(container.read(trainerUnreadBadgeProvider), 0);
      // 알림 화면을 연 적이 없으니 이어 받기 상태를 만들지 않는다.
      expect(container.exists(trainerNotificationPagingProvider), isFalse);
    });
  });

  testWidgets('실패하면 팝오버가 닫혀 있어도 안내가 뜨고 배지가 돌아온다', (tester) async {
    await withWideSurface(tester, () async {
      final _HeldRepository repo = _HeldRepository(<TrainerNotification>[
        _n('1'),
      ])..fail = true;
      await readAllThenClose(tester, repo);

      repo.hold.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('읽음 처리에 실패했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
      await settle(tester);
      expect(badge, findsOneWidget);
    });
  });
}

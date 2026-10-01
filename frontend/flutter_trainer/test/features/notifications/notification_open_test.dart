/// 알림 한 건을 여는 길 — 머리의 알림 종 팝오버와 알림 화면. (#2762)
///
/// 팝오버는 항목을 누르는 순간 닫혀 그 위젯의 `ref`·`context` 가 끝난다.
/// 전에는 읽음 요청을 기다린 뒤 그 `ref` 로 갱신을 이어 가다 예외가 나, 안 읽은
/// 알림만 누르면 팝오버만 닫히고 이동도 배지 갱신도 빠졌다.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

import '../../helpers/pump_app.dart';

TrainerNotification _notification({
  String id = 'noti-1',
  String title = '담당 요청을 거절했어요',
  TrainerNotificationKind kind = TrainerNotificationKind.inviteRejected,
  bool read = false,
  String? targetDate,
}) => TrainerNotification(
  id: id,
  title: title,
  body: '',
  kind: kind,
  read: read,
  createdAt: DateTime.utc(2026, 8, 9, 10),
  timeAgo: '3분 전',
  targetDate: targetDate,
);

/// 실 API 처럼 동작하는 페이크. 읽음 요청을 붙잡아 두거나 실패시킬 수 있다.
class _FakeNotificationRepository implements TrainerNotificationRepository {
  _FakeNotificationRepository(this._rows);

  List<TrainerNotification> _rows;

  /// 읽음 요청에 들어온 id.
  final List<String> readCalls = <String>[];

  /// 채워 두면 읽음 요청이 이 Future 를 기다린다 — 서버가 느린 경우.
  Completer<void>? hold;

  /// 참이면 읽음 요청이 실패한다.
  bool failRead = false;

  @override
  bool get supportsInbox => true;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async => before == null
      ? TrainerNotificationPage(items: _rows)
      : TrainerNotificationPage.empty;

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.fromFuture(fetch());

  @override
  Future<int> unreadCount() async =>
      _rows.where((TrainerNotification r) => !r.read).length;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.fromFuture(unreadCount());

  @override
  Future<void> markRead(String id) async {
    readCalls.add(id);
    final Completer<void>? wait = hold;
    if (wait != null) await wait.future;
    if (failRead) throw StateError('read failed');
    _rows = <TrainerNotification>[
      for (final TrainerNotification r in _rows)
        r.id == id ? r.copyWith(read: true) : r,
    ];
  }

  @override
  Future<int> markAllRead() async => 0;
}

void main() {
  final Finder bell = find.byKey(const ValueKey<String>('notification-bell'));
  final Finder badge = find.byKey(
    const ValueKey<String>('notification-bell-badge'),
  );
  final Finder panel = find.byKey(
    const ValueKey<String>('notification-bell-panel'),
  );

  String location(WidgetTester tester) {
    final BuildContext ctx = tester.element(find.byType(Navigator).first);
    return GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.toString();
  }

  Future<void> openBell(
    WidgetTester tester,
    _FakeNotificationRepository repo,
  ) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-token',
      at: AppRoutes.dashboard,
      extraOverrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.tap(bell);
    await settle(tester);
    expect(panel, findsOneWidget);
  }

  group('알림 종 팝오버', () {
    testWidgets('안 읽은 알림을 누르면 그 자리로 가고 배지가 빠진다', (tester) async {
      await withWideSurface(tester, () async {
        final repo = _FakeNotificationRepository(<TrainerNotification>[
          _notification(),
        ]);
        await openBell(tester, repo);
        expect(badge, findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-1')),
        );
        await settle(tester);

        expect(panel, findsNothing);
        expect(location(tester), AppRoutes.clients);
        expect(repo.readCalls, <String>['noti-1']);
        expect(badge, findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('읽음 요청이 끝나기 전에 이동하고 배지도 먼저 줄인다', (tester) async {
      await withWideSurface(tester, () async {
        final repo = _FakeNotificationRepository(<TrainerNotification>[
          _notification(),
        ])..hold = Completer<void>();
        await openBell(tester, repo);

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-1')),
        );
        await settle(tester);

        // 서버는 아직 답하지 않았다 — 그래도 화면은 이미 옮겨 갔다.
        expect(repo.readCalls, <String>['noti-1']);
        expect(location(tester), AppRoutes.clients);
        expect(badge, findsNothing);

        repo.hold!.complete();
        await settle(tester);
        // 새 숫자(0)가 와도 다시 튀어 오르지 않는다.
        expect(badge, findsNothing);
      });
    });

    testWidgets('읽음 처리가 실패해도 이동은 되고 배지는 되돌아온다', (tester) async {
      await withWideSurface(tester, () async {
        final repo = _FakeNotificationRepository(<TrainerNotification>[
          _notification(),
        ])..failRead = true;
        await openBell(tester, repo);

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-1')),
        );
        await settle(tester);

        expect(location(tester), AppRoutes.clients);
        expect(repo.readCalls, <String>['noti-1']);
        // 서버에는 여전히 미읽음이다 — 숨겨 두지 않는다.
        expect(badge, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('이미 읽은 알림은 읽음 요청 없이 그 자리로 간다', (tester) async {
      await withWideSurface(tester, () async {
        final repo = _FakeNotificationRepository(<TrainerNotification>[
          _notification(read: true),
          _notification(
            id: 'noti-2',
            title: '두 번째 알림',
            kind: TrainerNotificationKind.other,
          ),
        ]);
        await openBell(tester, repo);

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-1')),
        );
        await settle(tester);

        expect(location(tester), AppRoutes.clients);
        expect(repo.readCalls, isEmpty);
        // 남은 미읽음 한 건은 그대로 센다.
        expect(badge, findsOneWidget);
      });
    });

    testWidgets('예약 알림은 그 수업 날짜의 스케줄로 간다', (tester) async {
      await withWideSurface(tester, () async {
        final repo = _FakeNotificationRepository(<TrainerNotification>[
          _notification(
            id: 'noti-r',
            title: '새 예약이 들어왔어요',
            kind: TrainerNotificationKind.reservation,
            targetDate: '2026-08-21',
          ),
        ]);
        await openBell(tester, repo);

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-r')),
        );
        await settle(tester);

        expect(location(tester), AppRoutes.scheduleAt(date: '2026-08-21'));
        expect(repo.readCalls, <String>['noti-r']);
      });
    });
  });

  group('알림 화면', () {
    testWidgets('안 읽은 알림을 누르면 그 자리로 가고 읽음 처리된다', (tester) async {
      final repo = _FakeNotificationRepository(<TrainerNotification>[
        _notification(),
      ]);
      await pumpTrainerApp(
        tester,
        token: 'demo-token',
        at: AppRoutes.notifications,
        extraOverrides: <Override>[
          trainerNotificationRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('notification-noti-1')),
      );
      await settle(tester);

      expect(location(tester), AppRoutes.clients);
      expect(repo.readCalls, <String>['noti-1']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('읽음 처리 중에도 화면 머리 숫자는 미리 줄어 있다', (tester) async {
      final repo = _FakeNotificationRepository(<TrainerNotification>[
        _notification(kind: TrainerNotificationKind.other),
        _notification(id: 'noti-2', kind: TrainerNotificationKind.other),
      ])..hold = Completer<void>();
      final ProviderContainer container = await pumpTrainerApp(
        tester,
        token: 'demo-token',
        at: AppRoutes.notifications,
        extraOverrides: <Override>[
          trainerNotificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      expect(container.read(trainerUnreadBadgeProvider), 2);

      // 갈 곳이 없는 알림 — 알림 화면에 머문다.
      await tester.tap(
        find.byKey(const ValueKey<String>('notification-noti-1')),
      );
      await settle(tester);

      expect(location(tester), AppRoutes.notifications);
      expect(container.read(trainerUnreadBadgeProvider), 1);

      repo.hold!.complete();
      await settle(tester);
      expect(container.read(trainerUnreadBadgeProvider), 1);
      expect(container.read(trainerPendingNotificationReadsProvider), isEmpty);
    });
  });
}

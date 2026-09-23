/// 트레이너 알림함. (#503)
///
/// 데모는 지금 그대로여야 한다 — 알림을 만드는 회원 백엔드가 없어 늘 비어 있을
/// 행을 사이드바에 더하지 않는다(상담 요청과 같은 규칙).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/nav_destinations.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/pump_app.dart';

/// 라벨 기대값은 로케일을 명시해 읽는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();

TrainerNotification _notification({
  String id = 'noti-1',
  String title = '이지수 회원의 메시지',
  String body = '오늘 수업 시간 조정 가능할까요?',
  TrainerNotificationKind kind = TrainerNotificationKind.message,
  bool read = false,
}) => TrainerNotification(
  id: id,
  title: title,
  body: body,
  kind: kind,
  read: read,
  createdAt: DateTime.utc(2026, 8, 9, 10),
  timeAgo: '3분 전',
);

/// 실 API 처럼 동작하는 페이크 — 읽음 처리 호출을 기록한다.
class _FakeNotificationRepository implements TrainerNotificationRepository {
  _FakeNotificationRepository(this._rows, {this.fetchFailures = 0});

  List<TrainerNotification> _rows;
  int fetchFailures;
  int fetchCalls = 0;
  final List<String> readCalls = <String>[];
  int readAllCalls = 0;

  @override
  bool get supportsInbox => true;

  @override
  Future<List<TrainerNotification>> fetch() async {
    fetchCalls++;
    if (fetchFailures > 0) {
      fetchFailures--;
      throw StateError('DioException internal detail');
    }
    return _rows;
  }

  @override
  Stream<List<TrainerNotification>> watch() =>
      Stream<List<TrainerNotification>>.fromFuture(fetch());

  @override
  Future<int> unreadCount() async =>
      _rows.where((TrainerNotification r) => !r.read).length;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.fromFuture(unreadCount());

  @override
  Future<void> markRead(String id) async {
    readCalls.add(id);
    _rows = <TrainerNotification>[
      for (final TrainerNotification r in _rows)
        if (r.id == id)
          _notification(
            id: r.id,
            title: r.title,
            body: r.body,
            kind: r.kind,
            read: true,
          )
        else
          r,
    ];
  }

  @override
  Future<int> markAllRead() async {
    readAllCalls++;
    final int n = _rows.where((TrainerNotification r) => !r.read).length;
    _rows = <TrainerNotification>[
      for (final TrainerNotification r in _rows)
        _notification(
          id: r.id,
          title: r.title,
          body: r.body,
          kind: r.kind,
          read: true,
        ),
    ];
    return n;
  }
}

void main() {
  testWidgets('데모 콘솔에는 알림 행이 없다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(tester, token: 'demo-token');

      expect(
        find.text(navLabel(_ko, notificationsDestination.label)),
        findsNothing,
      );
    });
  });

  testWidgets('실 API 콘솔에는 알림 행이 보인다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-token',
        extraOverrides: <Override>[
          trainerNotificationRepositoryProvider.overrideWithValue(
            _FakeNotificationRepository(<TrainerNotification>[_notification()]),
          ),
        ],
      );

      expect(
        find.text(navLabel(_ko, notificationsDestination.label)),
        findsOneWidget,
      );
    });
  });

  testWidgets('받은 알림이 목록에 그려진다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-token',
      at: AppRoutes.notifications,
      extraOverrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(
          _FakeNotificationRepository(<TrainerNotification>[_notification()]),
        ),
      ],
    );

    expect(find.text('이지수 회원의 메시지'), findsOneWidget);
    expect(find.text('오늘 수업 시간 조정 가능할까요?'), findsOneWidget);
    expect(find.textContaining('읽지 않은 알림'), findsOneWidget);
  });

  testWidgets('알림이 없으면 빈 상태를 보여 준다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-token',
      at: AppRoutes.notifications,
      extraOverrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(
          _FakeNotificationRepository(const <TrainerNotification>[]),
        ),
      ],
    );

    expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('알림 오류는 empty와 구분되고 재시도 후 복구한다', (tester) async {
    final repo = _FakeNotificationRepository(<TrainerNotification>[
      _notification(title: '재시도로 복구된 알림'),
    ], fetchFailures: 1);
    await pumpTrainerApp(
      tester,
      token: 'demo-token',
      at: AppRoutes.notifications,
      extraOverrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(repo),
      ],
    );

    expect(find.text('알림을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('아직 받은 알림이 없어요'), findsNothing);
    expect(find.text('DioException internal detail'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('notifications-retry')));
    await settle(tester);

    expect(repo.fetchCalls, 2);
    expect(find.text('재시도로 복구된 알림'), findsOneWidget);
  });

  testWidgets('알림을 누르면 읽음 처리된다', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey<String>('notification-noti-1')));
    await settle(tester);

    // 갈 곳이 있든 없든 확인한 알림은 배지에서 빠져야 한다.
    expect(repo.readCalls, <String>['noti-1']);
  });

  test('회원이 떠난 알림은 member_left 로 읽고 이동하지 않는다 (#2174)', () {
    final TrainerNotification notice =
        TrainerNotification.fromJson(<String, Object?>{
          'id': 'noti-left',
          'title': '회원 탈퇴',
          'body': '김민수 회원이 탈퇴했어요.',
          'category': 'member_left',
          'read': false,
          'created_at': '2026-09-23T01:00:00Z',
          'time_ago': '방금 전',
        });

    expect(notice.kind, TrainerNotificationKind.memberLeft);
    expect(NotificationsPage.targetOf(notice), isNull);
  });

  testWidgets('회원이 떠난 알림도 목록에 그려지고 누르면 읽음 처리만 된다 (#2174)', (tester) async {
    final repo = _FakeNotificationRepository(<TrainerNotification>[
      _notification(
        id: 'noti-left',
        title: '담당 연결 해제',
        body: '김민수 회원이 담당 연결을 끊었어요.',
        kind: TrainerNotificationKind.memberLeft,
      ),
    ]);
    await pumpTrainerApp(
      tester,
      token: 'demo-token',
      at: AppRoutes.notifications,
      extraOverrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(repo),
      ],
    );

    expect(find.text('담당 연결 해제'), findsOneWidget);
    expect(find.text('김민수 회원이 담당 연결을 끊었어요.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('notification-noti-left')),
    );
    await settle(tester);

    expect(repo.readCalls, <String>['noti-left']);
    // 갈 곳이 없어 알림함에 머문다.
    expect(find.text('담당 연결 해제'), findsOneWidget);
  });

  testWidgets('모두 읽음이 전체를 읽음 처리한다', (tester) async {
    final repo = _FakeNotificationRepository(<TrainerNotification>[
      _notification(),
      _notification(id: 'noti-2', title: '새 예약이 들어왔어요'),
    ]);
    await pumpTrainerApp(
      tester,
      token: 'demo-token',
      at: AppRoutes.notifications,
      extraOverrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(repo),
      ],
    );

    await tester.tap(find.text('모두 읽음'));
    await settle(tester);

    expect(repo.readAllCalls, 1);
    expect(find.text('모두 확인했어요'), findsOneWidget);
  });
}

/// 대화를 읽으면 종 표시도 함께 꺼진다 — #3343.
///
/// 서버는 회원이 대화를 읽을 때 메시지·리포트 알림도 읽음으로 바꾼다. 앱이 그
/// 직후 미읽음 수를 다시 세지 않으면 종 표시는 다음 폴링(15초)까지 켜져 있다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _demoConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

AlertItem _alert(String id, AlertCategory category) => AlertItem(
  id: id,
  title: '알림 $id',
  body: '본문',
  timeAgo: '방금',
  category: category,
  createdAt: '2026-08-20T01:50:00Z',
);

/// 대화 읽음이 서버에서 하는 일을 흉내 낸다 — 읽으면 메시지 알림이 읽음이 된다.
class _ServerLikeNotifications implements NotificationRepository {
  List<AlertItem> items = <AlertItem>[
    _alert('chat-1', AlertCategory.system),
    _alert('chat-2', AlertCategory.system),
  ];
  int unreadCalls = 0;
  int fetchCalls = 0;

  void markCoachAlertsRead() {
    items = items.map((AlertItem i) => i.copyWith(read: true)).toList();
  }

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    fetchCalls += 1;
    return items;
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<int> unreadCount() async {
    unreadCalls += 1;
    return items.where((AlertItem i) => !i.read).length;
  }
}

class _CoachRepository extends MockMemberCoachRepository {
  _CoachRepository(this._notifications, {this.readThrows = false});

  final _ServerLikeNotifications _notifications;
  final bool readThrows;
  int markReadCalls = 0;

  @override
  Future<void> markRead() async {
    markReadCalls += 1;
    if (readThrows) throw StateError('읽음 처리 실패');
    _notifications.markCoachAlertsRead();
  }
}

Widget _app({
  required _CoachRepository coach,
  required _ServerLikeNotifications notifications,
  bool watchList = false,
}) {
  return ProviderScope(
    overrides: <Override>[
      memberCoachRepositoryProvider.overrideWithValue(coach),
      notificationRepositoryProvider.overrideWithValue(notifications),
      appConfigProvider.overrideWithValue(_demoConfig),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) {
          final int bell = ref.watch(notificationUnreadProvider).value ?? 0;
          final int unreadRows = watchList
              ? ref
                    .watch(notificationControllerProvider)
                    .items
                    .where((AlertItem i) => !i.read)
                    .length
              : -1;
          return Scaffold(
            body: Column(
              children: <Widget>[
                Text('종 $bell'),
                Text('목록 $unreadRows'),
                ElevatedButton(
                  onPressed: () =>
                      openTrainerChatPage(context, trainerName: '김트레이너'),
                  child: const Text('채팅 열기'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// 화면을 내려 미읽음 폴링을 멈춘다 — 듣는 곳이 없으면 타이머가 남지 않는다.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('대화를 읽으면 종 표시를 바로 다시 센다', (WidgetTester tester) async {
    final _ServerLikeNotifications notifications = _ServerLikeNotifications();
    final _CoachRepository coach = _CoachRepository(notifications);

    await tester.pumpWidget(_app(coach: coach, notifications: notifications));
    await tester.pumpAndSettle();
    expect(find.text('종 2'), findsOneWidget);
    final int before = notifications.unreadCalls;

    await tester.tap(find.text('채팅 열기'));
    await tester.pumpAndSettle();

    expect(coach.markReadCalls, 1);
    // 폴링 주기(15초)를 기다리지 않고 다시 물었다.
    expect(notifications.unreadCalls, greaterThan(before));
    expect(find.text('종 0', skipOffstage: false), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('읽음 처리가 실패하면 종 표시를 다시 세지 않는다', (WidgetTester tester) async {
    final _ServerLikeNotifications notifications = _ServerLikeNotifications();
    final _CoachRepository coach = _CoachRepository(
      notifications,
      readThrows: true,
    );

    await tester.pumpWidget(_app(coach: coach, notifications: notifications));
    await tester.pumpAndSettle();
    final int before = notifications.unreadCalls;

    await tester.tap(find.text('채팅 열기'));
    await tester.pumpAndSettle();

    expect(coach.markReadCalls, 1);
    expect(notifications.unreadCalls, before);
    expect(find.text('종 2', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('받아 둔 알림 목록도 다시 받아 읽음으로 바뀐다', (WidgetTester tester) async {
    final _ServerLikeNotifications notifications = _ServerLikeNotifications();
    final _CoachRepository coach = _CoachRepository(notifications);

    await tester.pumpWidget(
      _app(coach: coach, notifications: notifications, watchList: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('목록 2'), findsOneWidget);
    final int before = notifications.fetchCalls;

    await tester.tap(find.text('채팅 열기'));
    await tester.pumpAndSettle();

    expect(notifications.fetchCalls, before + 1);
    expect(find.text('목록 0', skipOffstage: false), findsOneWidget);

    await _unmount(tester);
  });

  // 알림 저장소를 세우지 못한 화면(대역을 넣지 않은 셸 테스트 등)에서는 알림함
  // provider 가 실패한 채 남아 있다 — 그걸 읽다가 대화 읽음이 깨지면 안 된다.
  testWidgets('알림함이 서지 못한 상태여도 대화 읽음은 깨지지 않는다', (WidgetTester tester) async {
    final _ServerLikeNotifications notifications = _ServerLikeNotifications();
    final _CoachRepository coach = _CoachRepository(notifications);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(coach),
          notificationRepositoryProvider.overrideWith(
            (ref) => throw StateError('알림 저장소 없음'),
          ),
          appConfigProvider.overrideWithValue(_demoConfig),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              ref.listen<NotificationState>(
                notificationControllerProvider,
                (_, _) {},
                onError: (_, _) {},
              );
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      openTrainerChatPage(context, trainerName: '김트레이너'),
                  child: const Text('채팅 열기'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('채팅 열기'));
    await tester.pumpAndSettle();

    expect(coach.markReadCalls, 1);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('알림함을 연 적이 없으면 목록은 받지 않는다', (WidgetTester tester) async {
    final _ServerLikeNotifications notifications = _ServerLikeNotifications();
    final _CoachRepository coach = _CoachRepository(notifications);

    await tester.pumpWidget(_app(coach: coach, notifications: notifications));
    await tester.pumpAndSettle();

    await tester.tap(find.text('채팅 열기'));
    await tester.pumpAndSettle();

    expect(notifications.fetchCalls, 0);

    await _unmount(tester);
  });
}

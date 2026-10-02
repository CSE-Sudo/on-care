/// 대화를 읽으면 알림 배지도 다시 읽는다. (#2291)
///
/// 서버는 트레이너가 대화를 읽을 때 그 회원의 메시지 알림도 읽음 처리한다.
/// 앱이 알림 수를 다시 받지 않으면, 서버에서는 읽었는데 사이드바 배지는 그대로
/// 남는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

class _FakeChatRepository implements ChatRepository {
  @override
  Future<List<ClientChatMessage>> fetchOlder(
    String clientId, {
    required ClientChatMessage before,
  }) async => const <ClientChatMessage>[];

  _FakeChatRepository({this.failRead = false});

  final bool failRead;
  final List<String> readCalls = <String>[];

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      Stream<List<ClientChatMessage>>.value(<ClientChatMessage>[
        ClientChatMessage(
          id: 'msg-1',
          sender: ChatSender.client,
          body: '안녕하세요',
          timeLabel: '10:00',
          createdAt: DateTime(2026, 9, 27, 10),
        ),
      ]);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {}

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream<Map<String, int>>.value(const <String, int>{});

  @override
  Future<void> markThreadRead(String clientId) async {
    readCalls.add(clientId);
    if (failRead) throw StateError('read receipt failed');
  }
}

/// 서버처럼 대화 읽음 뒤 미읽음 수가 줄어드는 알림 저장소.
class _FakeNotificationRepository implements TrainerNotificationRepository {
  _FakeNotificationRepository(this.chat);

  static const int unreadBefore = 2;

  final _FakeChatRepository chat;
  int listCalls = 0;
  int countCalls = 0;

  int get _unread => chat.readCalls.isEmpty || chat.failRead ? unreadBefore : 0;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async => TrainerNotificationPage.empty;

  @override
  Stream<TrainerNotificationPage> watch() {
    listCalls++;
    return Stream<TrainerNotificationPage>.fromFuture(fetch());
  }

  @override
  Future<int> unreadCount() async => _unread;

  @override
  Stream<int> watchUnreadCount() {
    countCalls++;
    return Stream<int>.fromFuture(unreadCount());
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeChatRepository chat,
  required _FakeNotificationRepository notifications,
  required bool useMockApi,
  Locale locale = const Locale('ko'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost/v1',
            useMockApi: useMockApi,
          ),
        ),
        chatRepositoryProvider.overrideWithValue(chat),
        trainerNotificationRepositoryProvider.overrideWithValue(notifications),
        // 메모는 이 테스트와 무관하다 — 실 API 로 나가지 않게 막는다.
        trainerMemosProvider.overrideWith(
          (ref, clientId) async => const <TrainerMemo>[],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: <Widget>[
              // 사이드바 배지처럼 미읽음 수를 계속 지켜본다.
              Consumer(
                builder: (context, ref, _) {
                  final int? unread = ref
                      .watch(trainerUnreadNotificationsProvider)
                      .valueOrNull;
                  ref.watch(trainerNotificationsProvider);
                  return Text(
                    'badge:${unread ?? '-'}',
                    key: const ValueKey<String>('badge'),
                  );
                },
              ),
              const Expanded(
                child: ChatView(
                  clientId: 'm1',
                  clientAvatar: '김',
                  clientName: '김민수',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final Locale locale in const <Locale>[Locale('ko'), Locale('en')]) {
    testWidgets('실 API: 대화를 열면 알림 목록과 배지를 다시 읽는다 '
        '(${locale.languageCode})', (tester) async {
      final chat = _FakeChatRepository();
      final notifications = _FakeNotificationRepository(chat);
      await _pump(
        tester,
        chat: chat,
        notifications: notifications,
        useMockApi: false,
        locale: locale,
      );

      expect(chat.readCalls, <String>['m1']);
      expect(notifications.countCalls, greaterThanOrEqualTo(2));
      expect(notifications.listCalls, greaterThanOrEqualTo(2));
      expect(find.text('badge:0'), findsOneWidget);
    });
  }

  testWidgets('데모: 알림 저장소를 다시 읽지 않는다', (tester) async {
    final chat = _FakeChatRepository();
    final notifications = _FakeNotificationRepository(chat);
    await _pump(
      tester,
      chat: chat,
      notifications: notifications,
      useMockApi: true,
    );

    expect(chat.readCalls, <String>['m1']);
    expect(notifications.countCalls, 1);
    expect(notifications.listCalls, 1);
  });

  testWidgets('읽음 처리가 실패하면 배지를 다시 읽지 않고 오류도 새지 않는다', (tester) async {
    final chat = _FakeChatRepository(failRead: true);
    final notifications = _FakeNotificationRepository(chat);
    await _pump(
      tester,
      chat: chat,
      notifications: notifications,
      useMockApi: false,
    );

    expect(chat.readCalls, <String>['m1']);
    expect(notifications.countCalls, 1);
    expect(find.text('badge:2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

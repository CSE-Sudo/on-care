import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/domain/repositories/client_data_refresher.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

/// 메시지를 보낸 뒤 로스터를 다시 읽는지(#3011) — 메시지 탭 최신순은 로스터의
/// `last_message_at` 이 정하므로, 다음 폴링까지 기다리면 방금 대화한 회원이
/// 제자리에 남는다.
class _RecordingClientRepository
    implements ClientRepository, ClientDataRefresher {
  final List<String> refreshed = <String>[];

  @override
  void refreshClientData(String clientId) => refreshed.add(clientId);

  @override
  void refreshAllClientData() => refreshed.add('*');

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A [ChatRepository] standing in for the real API: `watchThread` returns
/// a longer thread on its SECOND call (simulating the backend now
/// including the just-sent message once `chatThreadProvider` is
/// invalidated and refetches) — used to prove the view scrolls to the
/// *refetched* thread, not the stale one it had at send-time (review).
class _FakeChatRepository implements ChatRepository {
  @override
  Future<List<ClientChatMessage>> fetchOlder(
    String clientId, {
    required ClientChatMessage before,
  }) async => const <ClientChatMessage>[];

  int watchThreadCalls = 0;

  static List<ClientChatMessage> _seed(int count) => <ClientChatMessage>[
    for (var i = 0; i < count; i++)
      ClientChatMessage(
        id: 'seed-$i',
        sender: i.isEven ? ChatSender.client : ChatSender.trainer,
        body: '메시지 $i',
        timeLabel: '10:0$i',
        createdAt: DateTime(2026, 1, 1, 10, i),
      ),
  ];

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) {
    watchThreadCalls++;
    // First call (initial load): 20 seed messages, enough to overflow the
    // test viewport. Every call after the send (i.e. the post-invalidate
    // refetch) appends the message the trainer just sent.
    final base = _seed(20);
    if (watchThreadCalls == 1) return Stream.value(base);
    return Stream.value(<ClientChatMessage>[
      ...base,
      ClientChatMessage(
        id: 'sent-1',
        sender: ChatSender.trainer,
        body: '방금 보낸 메시지',
        timeLabel: '10:20',
        createdAt: DateTime(2026, 1, 1, 10, 20),
      ),
    ]);
  }

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {
    if (failSend) throw StateError('send failed');
  }

  bool failSend = false;

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream.value(const <String, int>{});

  @override
  Future<void> markThreadRead(String clientId) async {}
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _FakeChatRepository chat,
  required _RecordingClientRepository clients,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost/v1',
            useMockApi: false,
          ),
        ),
        chatRepositoryProvider.overrideWithValue(chat),
        clientRepositoryProvider.overrideWithValue(clients),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ChatView(clientId: 'm1', clientAvatar: '김', clientName: '김민수'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('실서버: 글을 보낸 뒤 그 회원의 로스터를 한 번 다시 읽는다', (tester) async {
    final chat = _FakeChatRepository();
    final clients = _RecordingClientRepository();
    await _pumpChat(tester, chat: chat, clients: clients);
    expect(clients.refreshed, isEmpty);

    await tester.enterText(find.byType(TextField), '방금 보낸 메시지');
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    expect(clients.refreshed, <String>['m1']);
  });

  testWidgets('실서버: 보내기가 실패하면 로스터를 다시 읽지 않는다', (tester) async {
    final chat = _FakeChatRepository()..failSend = true;
    final clients = _RecordingClientRepository();
    await _pumpChat(tester, chat: chat, clients: clients);

    await tester.enterText(find.byType(TextField), '실패할 메시지');
    await tester.tap(find.byIcon(AppIcons.send));
    await tester.pumpAndSettle();

    expect(clients.refreshed, isEmpty);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

/// A [ChatRepository] standing in for the real API: `watchThread` returns
/// a longer thread on its SECOND call (simulating the backend now
/// including the just-sent message once `chatThreadProvider` is
/// invalidated and refetches) — used to prove the view scrolls to the
/// *refetched* thread, not the stale one it had at send-time (review).
class _RealApiFakeChatRepository implements ChatRepository {
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
  }) async {}

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream.value(const <String, int>{});

  @override
  Future<void> markThreadRead(String clientId) async {}
}

void main() {
  testWidgets(
    'real-API send: the view scrolls to the refetched (longer) thread, '
    'not the stale pre-send one (review: invalidate() only starts an '
    'async refetch — scrolling immediately would use the old extent)',
    (tester) async {
      final fake = _RealApiFakeChatRepository();
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
            chatRepositoryProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: ChatView(
                clientId: 'm1',
                clientAvatar: '김',
                clientName: '김민수',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '방금 보낸 메시지');
      await tester.tap(find.byIcon(Icons.send_rounded));
      // Let the send future, the provider invalidation, the refetch, and
      // the resulting scroll animation all settle.
      await tester.pumpAndSettle();

      // The refetched (21-message) thread rendered — not just the 20-message
      // pre-send thread — proving the invalidate -> refetch pipeline landed.
      expect(find.text('방금 보낸 메시지'), findsOneWidget);

      // And the view is scrolled to (within a hair of) the bottom of THAT
      // longer list, not to the shorter pre-send extent.
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      expect(controller.hasClients, isTrue);
      expect(
        controller.position.pixels,
        closeTo(controller.position.maxScrollExtent, 1.0),
      );
    },
  );
}

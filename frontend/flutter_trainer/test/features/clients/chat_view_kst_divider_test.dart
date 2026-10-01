/// 회원 메시지의 날짜 구분선은 KST 로 가른다. (#2751)
///
/// 서버는 시각을 UTC 로 주고, 말풍선 시각은 서버가 KST 로 적은 라벨이다.
/// 구분선만 브라우저 시간대(`toLocal()`)로 가르면 UTC 브라우저에서 KST 아침
/// 메시지가 전날 구분선 아래 "08:10" 으로 놓인다. CI 는 UTC 라서, 고치기 전
/// 코드로는 아래 테스트가 깨진다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

class _ThreadRepository implements ChatRepository {
  @override
  Future<List<ClientChatMessage>> fetchOlder(
    String clientId, {
    required ClientChatMessage before,
  }) async => const <ClientChatMessage>[];

  _ThreadRepository(this.thread);

  final List<ClientChatMessage> thread;

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      Stream<List<ClientChatMessage>>.value(thread);

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
  Future<void> markThreadRead(String clientId) async {}
}

/// 서버가 주는 모양 그대로 — UTC 순간.
ClientChatMessage _server(String id, String iso, String kstLabel) =>
    ClientChatMessage(
      id: id,
      sender: ChatSender.client,
      body: 'body-$id',
      timeLabel: kstLabel,
      createdAt: DateTime.parse(iso),
    );

Future<void> _pump(
  WidgetTester tester,
  List<ClientChatMessage> thread, {
  bool useMockApi = false,
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
        chatRepositoryProvider.overrideWithValue(_ThreadRepository(thread)),
        trainerMemosProvider.overrideWith(
          (ref, clientId) async => const <TrainerMemo>[],
        ),
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

Finder _divider(int y, int m, int d) =>
    find.byKey(ValueKey<String>('trainer-chat-date-$y-$m-$d'));

void main() {
  testWidgets('KST 08:10 메시지는 그날 구분선 아래에 놓인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, <ClientChatMessage>[
      // KST 9/14 23:50
      _server('late', '2026-09-14T14:50:00+00:00', '23:50'),
      // KST 9/15 08:10 — UTC 로는 아직 9/14 다.
      _server('morning', '2026-09-14T23:10:00+00:00', '08:10'),
    ]);

    expect(_divider(2026, 9, 14), findsOneWidget);
    expect(_divider(2026, 9, 15), findsOneWidget);

    final double dividerTop = tester.getTopLeft(_divider(2026, 9, 15)).dy;
    expect(
      tester.getTopLeft(find.text('body-late')).dy,
      lessThan(dividerTop),
      reason: '전날 밤 메시지는 9/15 구분선 위에 있다',
    );
    expect(
      tester.getTopLeft(find.text('body-morning')).dy,
      greaterThan(dividerTop),
      reason: 'KST 아침 메시지는 9/15 구분선 아래에 있다',
    );
  });

  testWidgets('구분선 문구도 KST 날짜다', (tester) async {
    await _pump(tester, <ClientChatMessage>[
      _server('dawn', '2026-09-14T15:30:00+00:00', '00:30'),
    ]);

    expect(_divider(2026, 9, 15), findsOneWidget);
    expect(_divider(2026, 9, 14), findsNothing);
    expect(find.textContaining('9월 15일'), findsOneWidget);
  });

  testWidgets('UTC 로 날이 갈려도 KST 로 같은 날이면 구분선은 하나다', (tester) async {
    await _pump(tester, <ClientChatMessage>[
      // KST 9/15 00:10
      _server('a', '2026-09-14T15:10:00+00:00', '00:10'),
      // KST 9/15 10:00
      _server('b', '2026-09-15T01:00:00+00:00', '10:00'),
    ]);

    expect(_divider(2026, 9, 15), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('trainer-chat-date-'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('데모(로컬 KST 벽시계) 시각은 그대로 날짜가 된다', (tester) async {
    await _pump(tester, useMockApi: true, <ClientChatMessage>[
      ClientChatMessage(
        id: 'chat-1',
        sender: ChatSender.trainer,
        body: '데모 아침',
        timeLabel: '08:10',
        createdAt: DateTime(2026, 9, 15, 8, 10),
      ),
    ]);

    expect(_divider(2026, 9, 15), findsOneWidget);
  });
}

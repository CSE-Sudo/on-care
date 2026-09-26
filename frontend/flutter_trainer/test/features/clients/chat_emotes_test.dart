/// 트레이너가 보내는 채팅 이모티콘. (#2020)
///
/// 트레이너는 **이용권 없이** 보낸다 — 이용권은 회원이 포인트를 쓰는 자리이고,
/// 트레이너에게는 포인트라는 것이 없다. 그래서 고르는 창에 사는 자리가 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 보낸 것을 적어 두는 대역. 데모처럼 쓰면 스레드가 그대로 다시 흐른다.
class _RecordingChatRepository implements ChatRepository {
  _RecordingChatRepository({this.seed = const <ClientChatMessage>[]});

  final List<ClientChatMessage> seed;
  String? sentEmote;
  String? sentText;

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      Stream<List<ClientChatMessage>>.value(seed);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {
    sentText = text;
    sentEmote = emoteId;
  }

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream<Map<String, int>>.value(const <String, int>{});

  @override
  Future<void> markThreadRead(String clientId) async {}
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  _RecordingChatRepository chat,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost/v1',
            useMockApi: true,
          ),
        ),
        chatRepositoryProvider.overrideWithValue(chat),
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
  return AppLocalizations.of(tester.element(find.byType(ChatView)));
}

void main() {
  testWidgets('입력줄에 이모티콘 버튼이 있고, 고르면 이용권 없이 바로 나간다', (
    WidgetTester tester,
  ) async {
    final _RecordingChatRepository chat = _RecordingChatRepository();
    final AppLocalizations l = await _pump(tester, chat);

    final Finder button = find.byTooltip(l.chatEmoteLabel);
    expect(button, findsOneWidget);
    // 보내기 버튼과 한 변이 같다 — 입력줄에서 높이가 어긋나면 줄이 뒤뚱거린다.
    expect(
      tester.getSize(button).height,
      tester.getSize(find.byTooltip(l.a11ySendMessage)).height,
    );

    await tester.tap(button);
    await tester.pumpAndSettle();

    // 트레이너 쪽 창에는 사는 자리가 없다.
    expect(find.byKey(const Key('trainerEmoteSheet')), findsOneWidget);
    expect(find.textContaining('300P'), findsNothing);

    await tester.tap(find.byKey(const Key('trainer-emote-oni_owoon')));
    await tester.pumpAndSettle();

    expect(chat.sentEmote, 'oni_owoon');
    expect(chat.sentText, '');
    expect(find.byKey(const Key('trainerEmoteSheet')), findsNothing);
  });

  testWidgets('받은 이모티콘은 말풍선 없이 그림만 보인다', (WidgetTester tester) async {
    final _RecordingChatRepository chat = _RecordingChatRepository(
      seed: <ClientChatMessage>[
        ClientChatMessage(
          id: 'm-1',
          sender: ChatSender.client,
          body: '(이모티콘)',
          timeLabel: '10:01',
          createdAt: DateTime(2026, 1, 1, 10, 1),
          emoteId: 'dog_love',
        ),
      ],
    );
    await _pump(tester, chat);

    expect(find.byType(AppEmote), findsOneWidget);
    // 본문은 고객 목록의 마지막 메시지가 읽는 글이라 대화에는 나오지 않는다.
    expect(find.text('(이모티콘)'), findsNothing);
    expect(
      tester.widget<AppChatBubble>(find.byType(AppChatBubble)).bare,
      isTrue,
    );
  });
}

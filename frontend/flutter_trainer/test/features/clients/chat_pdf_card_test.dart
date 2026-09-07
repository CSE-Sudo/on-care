import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';

class _PdfChatRepository implements ChatRepository {
  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      Stream.value(<ClientChatMessage>[
        ClientChatMessage(
          id: 'pdf-message',
          sender: ChatSender.trainer,
          body: '이번 주 리포트입니다.',
          timeLabel: '18:20',
          createdAt: DateTime(2026, 8, 16, 18, 20),
          attachment: const ChatAttachment(
            kind: ChatAttachmentKind.pdf,
            fileName: '김회원_2026-08-10_주간리포트.pdf',
            fileId: 'trainer-pdf-file',
            fileSize: 2048,
            downloadPath: '/chat/attachments/trainer-pdf-file',
          ),
        ),
      ]);

  @override
  Future<void> markThreadRead(String clientId) async {}

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) async {}

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream.value(const <String, int>{});
}

class _NoMemoRepository implements TrainerMemoRepository {
  const _NoMemoRepository();

  @override
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
  }) => throw UnimplementedError();

  @override
  Future<void> delete(String clientId, String memoId) =>
      throw UnimplementedError();

  @override
  Future<List<TrainerMemo>> fetch(String clientId) async =>
      const <TrainerMemo>[];

  @override
  Future<TrainerMemo> update(String clientId, String memoId, String body) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('트레이너 채팅도 PDF attachment 카드를 그린다', (tester) async {
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
          chatRepositoryProvider.overrideWithValue(_PdfChatRepository()),
          trainerMemoRepositoryProvider.overrideWithValue(
            const _NoMemoRepository(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatView(
              clientId: 'client-1',
              clientAvatar: '김',
              clientName: '김회원',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('trainer-chat-pdf-trainer-pdf-file')),
      findsOneWidget,
    );
    expect(find.text('김회원_2026-08-10_주간리포트.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });
}

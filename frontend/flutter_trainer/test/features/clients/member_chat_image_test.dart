/// 회원이 보낸 사진이 트레이너 채팅에 보인다. (#1665)
///
/// 회원 앱이 코치 채팅으로 식사·자세·인바디 사진을 보낸다. 트레이너 쪽은 새
/// 화면 없이 트레이너 사진(#921)과 같은 틀로 그리되, 받은 메시지 쪽(왼쪽, 회원
/// 아바타)에 둔다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/clients/data/dtos/chat_dtos.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_image_attachment.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 1×1 투명 PNG.
final Uint8List _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, //
  0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
  13, 10, 45, 180,
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

const String _path = '/chat/attachments/member-photo';

/// 회원이 보낸 사진 한 장만 있는 스레드.
class _MemberPhotoRepository implements ChatRepository {
  @override
  Future<List<ClientChatMessage>> fetchOlder(
    String clientId, {
    required ClientChatMessage before,
  }) async => const <ClientChatMessage>[];

  _MemberPhotoRepository({this.body = ''});

  final String body;

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      Stream.value(<ClientChatMessage>[
        ClientChatMessage(
          id: 'member-photo-message',
          sender: ChatSender.client,
          body: body,
          timeLabel: '12:40',
          createdAt: DateTime(2026, 9, 27, 12, 40),
          attachment: const ChatAttachment(
            kind: ChatAttachmentKind.image,
            fileName: 'photo.png',
            fileId: 'member-photo',
            fileSize: 2048,
            downloadPath: _path,
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
    String? emoteId,
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
    TrainerMemoRef? ref,
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

Future<void> _pumpChat(
  WidgetTester tester, {
  Uint8List? bytes,
  String body = '',
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
        chatRepositoryProvider.overrideWithValue(
          _MemberPhotoRepository(body: body),
        ),
        trainerMemoRepositoryProvider.overrideWithValue(
          const _NoMemoRepository(),
        ),
        chatImageProvider(_path).overrideWith((ref) async => bytes),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
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
}

void main() {
  test('회원이 보낸 사진 메시지를 받은 쪽 이미지 첨부로 읽는다', () {
    final ClientChatMessage parsed = chatMessageFromJson(<String, Object?>{
      'id': 'chat-7',
      'sender': 'client',
      'body': '',
      'time_label': '12:40',
      'created_at': '2026-09-27T03:40:00Z',
      'attachment': <String, Object?>{
        'type': 'image',
        'file_name': 'photo.jpg',
        'file_id': 'file-7',
        'file_size': 4096,
        'download_path': '/chat/attachments/file-7',
      },
    });

    expect(parsed.fromTrainer, isFalse);
    expect(parsed.attachment!.isImage, isTrue);
    expect(parsed.attachment!.downloadPath, '/chat/attachments/file-7');
  });

  testWidgets('회원이 보낸 사진을 받은 말풍선 안에 그린다', (tester) async {
    await _pumpChat(tester, bytes: _png);

    final Finder image = find.byKey(
      const ValueKey<String>('chat-image-member-photo'),
    );
    expect(image, findsOneWidget);
    // PDF 처럼 내려받는 카드로 두지 않는다.
    expect(
      find.byKey(const ValueKey<String>('trainer-chat-pdf-member-photo')),
      findsNothing,
    );
    // 받은 메시지 쪽이다 — 사진 왼쪽에 회원 아바타가 있다.
    final Finder avatar = find.byWidgetPredicate(
      (Widget w) => w is ClientAvatar && w.size == AppAvatarSize.small,
    );
    expect(avatar, findsWidgets);
    expect(
      tester.getCenter(avatar.last).dx,
      lessThan(tester.getCenter(image).dx),
    );
    final AppChatBubble bubble = tester.widget<AppChatBubble>(
      find.ancestor(of: image, matching: find.byType(AppChatBubble)),
    );
    expect(bubble.mine, isFalse);
  });

  testWidgets('사진과 함께 쓴 글도 같은 말풍선에 보인다', (tester) async {
    await _pumpChat(tester, bytes: _png, body: '오늘 점심이에요');

    expect(find.text('오늘 점심이에요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('chat-image-member-photo')),
      findsOneWidget,
    );
  });

  testWidgets('사진을 못 가져와도 대화가 깨지지 않는다', (tester) async {
    await _pumpChat(tester);

    expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
  });
}

/// 데모 트레이너 채팅의 사진 첨부. (#2493)
///
/// 회원앱 데모에서는 사진을 보낼 수 있는데 트레이너 웹 데모에는 버튼이 없어,
/// 두 앱을 나란히 보면 한쪽만 되는 기능으로 읽혔다. 데모는 서버 대신 로컬
/// 대화에 바이트째 붙이고, 다시 불러와도 사진이 남는다.
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/repositories/chat_pdf_repository.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_image_attachment.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/chat_preview.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

/// 1×1 투명 PNG. 파일을 읽어 오지 않고 여기서 만든다.
final Uint8List _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, //
  0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
  13, 10, 45, 180,
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

/// 스레드 하나를 그대로 흘려 주는 대역.
class _StaticChatRepository implements ChatRepository {
  _StaticChatRepository(this.thread);

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

Future<AppLocalizations> _pumpChat(
  WidgetTester tester,
  List<ClientChatMessage> thread,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_demo),
        chatRepositoryProvider.overrideWithValue(_StaticChatRepository(thread)),
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
  group('DriftChatRepository.sendTrainerImage', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test('보낸 사진이 한마디와 함께 트레이너 말풍선 끝에 붙는다', () async {
      final repo = DriftChatRepository(db);
      await repo.sendTrainerImage(
        clientId: 'seed-client-1',
        bytes: _png,
        fileName: 'pose.png',
        message: '  이 자세 참고해 주세요  ',
      );

      final last = (await repo.watchThread('seed-client-1').first).last;
      expect(last.sender, ChatSender.trainer);
      expect(last.body, '이 자세 참고해 주세요');
      expect(last.attachment, isNotNull);
      expect(last.attachment!.isImage, isTrue);
      expect(last.attachment!.fileName, 'pose.png');
      expect(last.attachment!.fileSize, _png.length);
      expect(last.attachment!.localBytes, _png);

      final row = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-1'))).getSingle();
      expect(row.lastMessage, '이 자세 참고해 주세요');
      expect(row.lastTime, ChatPreviewCode.justNow);
    });

    test('사진만 보내면 고객 목록 미리보기가 "사진" 이다', () async {
      await DriftChatRepository(db).sendTrainerImage(
        clientId: 'seed-client-2',
        bytes: _png,
        fileName: 'a.jpg',
      );

      final row = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-2'))).getSingle();
      // 문구가 아니라 코드다 — 화면이 로케일로 옮긴다. 실서버 로스터와 같은 말.
      expect(row.lastMessage, ChatPreviewCode.photo);
      expect(ChatPreviewCode.isCode(row.lastMessage), isTrue);
      expect(chatPreviewMessage(AppLocalizationsKo(), row.lastMessage), '사진');
    });

    test('바이트가 로컬 DB 에 남아 다시 열어도 사진이 그려진다', () async {
      await DriftChatRepository(db).sendTrainerImage(
        clientId: 'seed-client-1',
        bytes: _png,
        fileName: 'pose.png',
      );

      // 새로고침 뒤를 흉내 낸다 — 새 저장소로 같은 DB 를 다시 읽는다.
      final last = (await DriftChatRepository(
        db,
      ).watchThread('seed-client-1').first).last;
      expect(await db.readValue('chat_image_${last.id}'), isNotNull);
      expect(last.attachment?.localBytes, _png);
    });

    test('사진이 없는 메시지에는 첨부가 붙지 않는다', () async {
      final repo = DriftChatRepository(db);
      await repo.sendTrainerMessage(clientId: 'seed-client-1', text: '안녕하세요');

      final last = (await repo.watchThread('seed-client-1').first).last;
      expect(last.attachment, isNull);
    });
  });

  group('trainerChatImageRepositoryProvider', () {
    ProviderContainer containerFor({required bool useMockApi}) {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'http://localhost/v1',
              useMockApi: useMockApi,
            ),
          ),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('데모에서는 로컬 대화에 붙이는 구현을 쓴다', () {
      expect(
        containerFor(useMockApi: true).read(trainerChatImageRepositoryProvider),
        isA<DemoTrainerChatImageRepository>(),
      );
    });

    test('실서버에서는 /chat/image 로 보내는 구현을 그대로 쓴다', () {
      expect(
        containerFor(
          useMockApi: false,
        ).read(trainerChatImageRepositoryProvider),
        isA<DioTrainerChatImageRepository>(),
      );
    });
  });

  testWidgets('데모 입력줄에 사진 첨부 버튼이 있다', (WidgetTester tester) async {
    final l = await _pumpChat(tester, const <ClientChatMessage>[]);

    expect(find.byTooltip(l.chatAttachImage), findsOneWidget);
  });

  testWidgets('데모 사진은 받아 오지 않고 바이트 그대로 말풍선 안에 그린다', (
    WidgetTester tester,
  ) async {
    await _pumpChat(tester, <ClientChatMessage>[
      ClientChatMessage(
        id: 'chat-m1-1',
        sender: ChatSender.trainer,
        body: '이 자세 참고해 주세요',
        timeLabel: '18:10',
        createdAt: DateTime(2026, 9, 29, 18, 10),
        attachment: ChatAttachment(
          kind: ChatAttachmentKind.image,
          fileName: 'pose.png',
          fileId: 'demo-photo-chat-m1-1',
          fileSize: _png.length,
          downloadPath: '/chat/attachments/demo-photo-chat-m1-1',
          localBytes: _png,
        ),
      ),
    ]);

    expect(find.byType(ChatImageAttachment), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('chat-image-demo-photo-chat-m1-1')),
      findsOneWidget,
    );
    expect(find.text('이 자세 참고해 주세요'), findsOneWidget);
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/shared/models/chat_preview.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/pump_app.dart';

/// 목록 미리보기가 한국어 문구를 저장하지 않고, 화면이 로케일로 그리는지
/// 본다 (#2303). 저장소 층은 코드·빈 값을, 화면 층은 그 문구를 확인한다.
void main() {
  group('저장소는 문구 대신 코드를 적는다', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    Future<TrainerClientRow> rowOf(String id) => (db.select(
      db.trainerClients,
    )..where((t) => t.id.equals(id))).getSingle();

    test('글 답장은 그 글과 방금 코드를 남긴다', () async {
      await DriftChatRepository(
        db,
      ).sendTrainerMessage(clientId: 'seed-client-2', text: '  See you!  ');
      final TrainerClientRow row = await rowOf('seed-client-2');
      expect(row.lastMessage, 'See you!');
      expect(row.lastTime, ChatPreviewCode.justNow);
    });

    test('글 없는 이모티콘은 이모티콘 코드를 남기고 본문을 비운다', () async {
      final DriftChatRepository repo = DriftChatRepository(db);
      await repo.sendTrainerMessage(
        clientId: 'seed-client-2',
        text: '',
        emoteId: 'dog_love',
      );
      final TrainerClientRow row = await rowOf('seed-client-2');
      expect(row.lastMessage, ChatPreviewCode.emote);
      expect(row.lastTime, ChatPreviewCode.justNow);

      final thread = await repo.watchThread('seed-client-2').first;
      expect(thread.last.emoteId, 'dog_love');
      // 예전에는 `(이모티콘)` 이 본문으로 저장됐다.
      expect(thread.last.body, isEmpty);
    });

    test('공백만 있는 글과 이모티콘은 이모티콘으로 본다', () async {
      await DriftChatRepository(db).sendTrainerMessage(
        clientId: 'seed-client-3',
        text: '   ',
        emoteId: 'dog_love',
      );
      expect((await rowOf('seed-client-3')).lastMessage, ChatPreviewCode.emote);
    });

    test('글과 이모티콘을 함께 보내면 글이 미리보기다', () async {
      await DriftChatRepository(db).sendTrainerMessage(
        clientId: 'seed-client-3',
        text: '잘했어요',
        emoteId: 'dog_love',
      );
      expect((await rowOf('seed-client-3')).lastMessage, '잘했어요');
    });

    test('빈 글은 아무것도 바꾸지 않는다', () async {
      final TrainerClientRow before = await rowOf('seed-client-4');
      await DriftChatRepository(
        db,
      ).sendTrainerMessage(clientId: 'seed-client-4', text: '  ');
      final TrainerClientRow after = await rowOf('seed-client-4');
      expect(after.lastMessage, before.lastMessage);
      expect(after.lastTime, before.lastTime);
    });

    test('새로 추가한 고객은 미리보기를 비워 둔다', () async {
      final DriftClientRepository repo = DriftClientRepository(db);
      expect(await repo.addClient(name: 'Alex Kim', goal: ''), isTrue);
      final TrainerClientRow row = await (db.select(
        db.trainerClients,
      )..where((t) => t.name.equals('Alex Kim'))).getSingle();
      expect(row.lastMessage, isEmpty);
      expect(row.lastTime, '-');
    });

    test('데모 담당 요청으로 연결한 회원도 미리보기를 비워 둔다', () async {
      final DemoClientInviteRepository demo = DemoClientInviteRepository(db);
      final found = await demo.lookup('user-1c7b93f04a58');
      final invite = await demo.invite(found.memberId);
      final List<TrainerClientRow> rows = await db
          .select(db.trainerClients)
          .get();
      final TrainerClientRow row = rows.firstWhere(
        (TrainerClientRow r) => r.name == invite.memberName,
      );
      expect(row.lastMessage, isEmpty);
      expect(row.lastTime, '-');
    });

    test('저장소 어디에도 한국어 미리보기 문구가 남지 않는다', () async {
      await DriftChatRepository(db).sendTrainerMessage(
        clientId: 'seed-client-2',
        text: '',
        emoteId: 'dog_love',
      );
      await DriftClientRepository(db).addClient(name: 'Sam Lee', goal: '');
      final List<TrainerClientRow> rows = await db
          .select(db.trainerClients)
          .get();
      for (final TrainerClientRow row in rows) {
        expect(row.lastMessage, isNot('아직 대화가 없어요'), reason: row.id);
        expect(row.lastMessage, isNot('(이모티콘)'), reason: row.id);
        expect(row.lastTime, isNot('방금'), reason: row.id);
      }
    });
  });

  group('메시지 목록은 로케일 문구로 그린다', () {
    for (final (Locale locale, String emote, String justNow, String empty)
        in <(Locale, String, String, String)>[
          (const Locale('ko'), '이모티콘을 보냈어요', '방금', '아직 대화가 없어요'),
          (const Locale('en'), 'Sent an emote', 'Just now', 'No messages yet'),
        ]) {
      testWidgets('${locale.languageCode}: 이모티콘·방금·대화 없음', (tester) async {
        await withWideSurface(tester, size: const Size(1440, 2600), () async {
          final container = await pumpTrainerApp(
            tester,
            token: 'demo-trainer-token-existing',
            locale: locale,
          );
          await container
              .read(chatRepositoryProvider)
              .sendTrainerMessage(
                clientId: 'seed-client-2',
                text: '',
                emoteId: 'dog_love',
              );
          await container
              .read(clientRepositoryProvider)
              .addClient(name: 'Jordan Park', goal: '');
          await goTo(tester, AppRoutes.messages);

          final Finder emoteTile = find.byKey(
            const ValueKey<String>('messages-conversation-seed-client-2'),
          );
          expect(emoteTile, findsOneWidget);
          expect(
            find.descendant(of: emoteTile, matching: find.text(emote)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: emoteTile, matching: find.text(justNow)),
            findsOneWidget,
          );

          final AppDatabase db = container.read(appDatabaseProvider);
          final TrainerClientRow added =
              await tester.runAsync(
                    () => (db.select(
                      db.trainerClients,
                    )..where((t) => t.name.equals('Jordan Park'))).getSingle(),
                  )
                  as TrainerClientRow;
          final Finder emptyPreview = find.byKey(
            ValueKey<String>('messages-preview-${added.id}'),
          );
          await tester.scrollUntilVisible(
            emptyPreview,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.descendant(
              of: emptyPreview,
              matching: find.text(empty),
              matchRoot: true,
            ),
            findsOneWidget,
          );

          // 코드가 화면에 그대로 새지 않는다.
          expect(find.textContaining('@emote'), findsNothing);
          expect(find.textContaining('@just_now'), findsNothing);
        });
      });
    }
  });

  group('채팅 감지 배너의 부위 이름도 로케일을 따른다', () {
    for (final (Locale locale, String title) in <(Locale, String)>[
      (const Locale('ko'), '무릎 불편 표현 감지'),
      (const Locale('en'), 'Knee discomfort detected'),
    ]) {
      testWidgets(locale.languageCode, (tester) async {
        await withWideSurface(tester, () async {
          await pumpTrainerApp(
            tester,
            token: 'demo-trainer-token-existing',
            locale: locale,
          );
          await goTo(tester, AppRoutes.messagesFor('seed-client-1'));
          expect(find.text(title), findsOneWidget);
        });
      });
    }
  });
}

/// 회원 앱 데모의 트레이너 대화 — 답장과 트레이너가 보낸 첨부. (#2663)
///
/// 실서버에서는 트레이너가 실제로 답하고, 운동 안내 PDF·예시 사진을 보낸다.
/// 데모에는 답할 사람도 내려받을 서버도 없어, 보내도 대화가 멈춰 있고 첨부
/// 카드는 한 번도 보이지 않았다. 여기서 고정하는 것은 그 빈자리를 메운 모양이다:
///  * 보내면 잠시 뒤 트레이너 답이 붙고, 닫아 둔 동안에는 미읽음으로 센다.
///  * 시드에 트레이너가 보낸 PDF·사진이 있고, 그 경로를 로컬 목업 API 가 번들
///    파일로 답한다.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/member_coach/data/demo_coach_files.dart';
import 'package:oncare/features/member_coach/data/repositories/chat_pdf_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// 답이 붙기를 기다리는 시간 — 답장 지연보다 넉넉히.
const Duration _replyDelay = Duration(milliseconds: 10);
Future<void> _waitReply() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('자동 답장', () {
    test('보내면 잠시 뒤 트레이너 답이 붙고 미읽음이 된다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        replyDelay: _replyDelay,
      );
      addTearDown(repo.dispose);
      await repo.markRead();
      expect(await repo.unreadCount(), 0);

      await repo.sendMessage('오늘 걷기 30분 했어요');
      // 답이 오기 전에는 내 말이 끝이다.
      expect((await repo.fetchChat()).last.sender, CoachSender.me);

      await _waitReply();
      final List<CoachMessage> chat = await repo.fetchChat();
      expect(chat.last.sender, CoachSender.trainer);
      expect(chat.last.body, isNotEmpty);
      expect(await repo.unreadCount(), 1);

      await repo.markRead();
      expect(await repo.unreadCount(), 0);
    });

    test('열어 둔 대화와 배지는 답이 오면 새 값을 받는다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        replyDelay: _replyDelay,
      );
      addTearDown(repo.dispose);
      await repo.markRead();

      final List<List<CoachMessage>> threads = <List<CoachMessage>>[];
      final List<int> badges = <int>[];
      final StreamSubscription<List<CoachMessage>> chatSub = repo
          .watchChat()
          .listen(threads.add);
      final StreamSubscription<int> unreadSub = repo.watchUnread().listen(
        badges.add,
      );
      addTearDown(chatSub.cancel);
      addTearDown(unreadSub.cancel);

      await repo.sendMessage('무릎은 괜찮아졌어요');
      await _waitReply();

      expect(threads.last.last.sender, CoachSender.trainer);
      expect(badges.last, 1);
    });

    test('사진을 보내도 답한다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        replyDelay: _replyDelay,
      );
      addTearDown(repo.dispose);

      await repo.sendPhoto(
        Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]),
        fileName: 'meal.jpg',
        mimeType: 'image/jpeg',
        clientRequestId: 'photo-1',
      );
      await _waitReply();

      expect((await repo.fetchChat()).last.sender, CoachSender.trainer);
    });

    test('지연을 주지 않으면 답하지 않는다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();
      addTearDown(repo.dispose);

      await repo.sendMessage('안녕하세요');
      await _waitReply();

      expect((await repo.fetchChat()).last.sender, CoachSender.me);
    });

    test('기다리는 사이 담당이 끊기면 답하지 않는다', () async {
      bool linked = true;
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        replyDelay: _replyDelay,
        linked: () => linked,
      );
      addTearDown(repo.dispose);

      await repo.sendMessage('안녕하세요');
      linked = false;
      await _waitReply();
      linked = true;

      expect((await repo.fetchChat()).last.sender, CoachSender.me);
    });

    test('저장소를 버리면 기다리던 답을 거둔다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        replyDelay: _replyDelay,
      );

      await repo.sendMessage('안녕하세요');
      repo.dispose();
      await _waitReply();

      expect((await repo.fetchChat()).last.sender, CoachSender.me);
    });
  });

  group('트레이너가 보낸 첨부', () {
    test('시드에 트레이너가 보낸 PDF 와 사진이 하나씩 있다', () async {
      final List<CoachMessage> chat = await MockMemberCoachRepository()
          .fetchChat();
      final List<CoachMessage> withFiles = <CoachMessage>[
        for (final CoachMessage m in chat)
          if (m.attachment != null) m,
      ];

      expect(withFiles, hasLength(2));
      expect(
        withFiles.every((CoachMessage m) => m.sender == CoachSender.trainer),
        isTrue,
      );
      expect(
        <CoachAttachmentKind>[
          for (final CoachMessage m in withFiles) m.attachment!.kind,
        ],
        <CoachAttachmentKind>[
          CoachAttachmentKind.pdf,
          CoachAttachmentKind.image,
        ],
      );
      // 실서버 첨부처럼 내려받을 경로만 든다 — 바이트를 미리 들고 있으면
      // 받아 오는 길이 데모에서 돌지 않는다.
      for (final CoachMessage m in withFiles) {
        expect(m.attachment!.localBytes, isNull);
        expect(m.attachment!.downloadPath, startsWith('/chat/attachments/'));
      }
    });

    test('적어 둔 크기가 번들 파일의 크기와 같다', () {
      for (final DemoCoachFile file in kDemoCoachFiles) {
        expect(
          File(file.asset).lengthSync(),
          file.fileSize,
          reason: '${file.asset} 의 크기가 바뀌었다',
        );
      }
    });

    group('로컬 목업 API', () {
      late AppDatabase db;
      late Dio dio;

      setUp(() {
        db = AppDatabase.forTesting(NativeDatabase.memory());
        dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
        dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
      });

      tearDown(() => db.close());

      test('첨부 경로에 번들 파일 바이트를 준다', () async {
        for (final DemoCoachFile file in kDemoCoachFiles) {
          final Uint8List bytes = await ChatPdfRepository(
            dio,
          ).download(file.downloadPath);
          expect(bytes, File(file.asset).readAsBytesSync());
        }
      });

      test('데모에 없는 첨부는 404 다', () async {
        final Response<List<int>> res = await dio.get<List<int>>(
          '/chat/attachments/nope',
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (_) => true,
          ),
        );
        expect(res.statusCode, 404);
      });
    });
  });
}

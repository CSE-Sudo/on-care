/// 회원이 트레이너에게 사진을 보내는 길 — DTO·저장소·데모·전송 상태. (#1665)
///
/// 화면 없이 확인할 수 있는 층만 여기 둔다. 입력줄 버튼과 말풍선은
/// `coach_photo_chat_test.dart` 가 본다.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/coach_photo_send_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';

class _MockDio extends Mock implements Dio {}

/// PNG 서명 뒤에 아무 바이트. 형식 판정은 앞 8바이트만 본다.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  1, 2, 3, 4,
]);

/// JPEG 서명.
final Uint8List _jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 9]);

Map<String, Object?> _sentJson({String body = ''}) => <String, Object?>{
  'id': 'chat-9',
  'sender': 'me',
  'body': body,
  'time_label': '09:30',
  'created_at': '2026-09-27T00:30:00Z',
  'attachment': <String, Object?>{
    'type': 'image',
    'file_name': 'photo.png',
    'file_id': 'file-9',
    'file_size': 12,
    'download_path': '/chat/attachments/file-9',
  },
};

/// 보낸 사진을 적어 두고, 정해 둔 만큼 실패하는 저장소.
class _PhotoRepository extends MockMemberCoachRepository {
  _PhotoRepository({this.failures = 0});

  int failures;
  final List<String> requestIds = <String>[];
  final List<String> fileNames = <String>[];
  final List<String> mimeTypes = <String>[];
  Completer<void>? gate;

  @override
  Future<CoachMessage> sendPhoto(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String clientRequestId,
    String text = '',
  }) async {
    requestIds.add(clientRequestId);
    fileNames.add(fileName);
    mimeTypes.add(mimeType);
    final Completer<void>? wait = gate;
    if (wait != null) await wait.future;
    if (failures > 0) {
      failures -= 1;
      throw const NetworkError();
    }
    return super.sendPhoto(
      bytes,
      fileName: fileName,
      mimeType: mimeType,
      clientRequestId: clientRequestId,
      text: text,
    );
  }
}

ProviderContainer _container(_PhotoRepository repo) {
  int n = 0;
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      memberCoachRepositoryProvider.overrideWithValue(repo),
      coachPhotoRequestIdProvider.overrideWithValue(() => 'photo-${++n}'),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUpAll(() {
    registerFallbackValue(FormData());
    registerFallbackValue(Options());
  });

  group('DTO', () {
    test('내가 보낸 사진은 내 쪽 메시지의 이미지 첨부로 읽힌다', () {
      final CoachMessage parsed = coachMessageFromJson(_sentJson());

      expect(parsed.fromMe, isTrue);
      expect(parsed.body, isEmpty);
      expect(parsed.attachment!.isImage, isTrue);
      expect(parsed.attachment!.downloadPath, '/chat/attachments/file-9');
      // 서버가 준 첨부는 받아 와서 그린다 — 가진 바이트가 없다.
      expect(parsed.attachment!.localBytes, isNull);
    });

    test('사진과 함께 쓴 글도 그대로 읽힌다', () {
      final CoachMessage parsed = coachMessageFromJson(
        _sentJson(body: '오늘 점심이에요'),
      );

      expect(parsed.body, '오늘 점심이에요');
      expect(parsed.attachment!.fileName, 'photo.png');
    });
  });

  group('Dio 저장소', () {
    late _MockDio dio;
    late DioMemberCoachRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioMemberCoachRepository(dio);
    });

    test('사진 전송 경로에 사진·글·멱등키를 multipart 로 싣는다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/me/coach/chat/image',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: '/me/coach/chat/image'),
          statusCode: 201,
          data: _sentJson(),
        ),
      );

      final CoachMessage sent = await repo.sendPhoto(
        _png,
        fileName: 'photo.png',
        mimeType: 'image/png',
        clientRequestId: 'photo-1',
        text: '  인바디 결과예요  ',
      );

      expect(sent.id, 'chat-9');
      expect(sent.fromMe, isTrue);
      final FormData form =
          verify(
                () => dio.post<Map<String, Object?>>(
                  '/me/coach/chat/image',
                  data: captureAny(named: 'data'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as FormData;
      final Map<String, String> fields = Map<String, String>.fromEntries(
        form.fields,
      );
      expect(fields['message'], '인바디 결과예요');
      expect(fields['client_request_id'], 'photo-1');
      final MultipartFile image = form.files.single.value;
      expect(form.files.single.key, 'image');
      expect(image.filename, 'photo.png');
      expect(image.contentType.toString(), 'image/png');
      expect(image.length, _png.length);
    });

    test('서버 거절은 앱 오류로 바뀐다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/me/coach/chat/image',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/me/coach/chat/image'),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/me/coach/chat/image'),
            statusCode: 415,
          ),
        ),
      );

      await expectLater(
        repo.sendPhoto(
          _png,
          fileName: 'photo.png',
          mimeType: 'image/png',
          clientRequestId: 'photo-1',
        ),
        throwsA(isA<AppError>()),
      );
    });

    test('본문 없는 응답은 조용히 넘기지 않는다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/me/coach/chat/image',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: '/me/coach/chat/image'),
          statusCode: 201,
        ),
      );

      await expectLater(
        repo.sendPhoto(
          _png,
          fileName: 'photo.png',
          mimeType: 'image/png',
          clientRequestId: 'photo-1',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('데모 저장소', () {
    test('보낸 사진이 대화 끝에 내 메시지로 들어가고 바이트를 그대로 가진다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();
      final int before = (await repo.fetchChat()).length;

      final CoachMessage sent = await repo.sendPhoto(
        _png,
        fileName: 'photo.png',
        mimeType: 'image/png',
        clientRequestId: 'photo-1',
      );

      final List<CoachMessage> chat = await repo.fetchChat();
      expect(chat, hasLength(before + 1));
      expect(chat.last.id, sent.id);
      expect(sent.fromMe, isTrue);
      expect(sent.attachment!.isImage, isTrue);
      // 데모에는 내려받을 서버가 없다 — 고른 바이트로 그린다.
      expect(sent.attachment!.localBytes, _png);
    });

    test('같은 멱등키로 다시 보내면 한 장만 남는다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();
      final int before = (await repo.fetchChat()).length;

      final CoachMessage first = await repo.sendPhoto(
        _png,
        fileName: 'photo.png',
        mimeType: 'image/png',
        clientRequestId: 'photo-1',
      );
      final CoachMessage again = await repo.sendPhoto(
        _png,
        fileName: 'photo.png',
        mimeType: 'image/png',
        clientRequestId: 'photo-1',
      );

      expect(again.id, first.id);
      expect(await repo.fetchChat(), hasLength(before + 1));
    });
  });

  group('전송 상태', () {
    test('보내는 동안 대기 사진이 있고, 받으면 서버 메시지로 바뀐다', () async {
      final _PhotoRepository repo = _PhotoRepository()
        ..gate = Completer<void>();
      final ProviderContainer c = _container(repo);
      final CoachPhotoSendController ctrl = c.read(
        coachPhotoSendProvider.notifier,
      );

      final Future<bool> sending = ctrl.send(MealPhoto.fromBytes(_png)!);
      final PendingCoachPhoto pending = c.read(coachPhotoSendProvider).single;
      expect(pending.status, CoachPhotoSendStatus.sending);
      expect(pending.requestId, 'photo-1');
      // 올리는 동안에도 말풍선이 그릴 수 있게 바이트를 가진다.
      expect(pending.attachment.localBytes, _png);
      expect(pending.message, isNull);

      repo.gate!.complete();
      expect(await sending, isTrue);

      final PendingCoachPhoto done = c.read(coachPhotoSendProvider).single;
      expect(done.status, CoachPhotoSendStatus.sent);
      expect(done.message!.fromMe, isTrue);
      expect(done.message!.attachment!.isImage, isTrue);
    });

    test('파일 이름과 형식은 바이트에서 읽은 것이다', () async {
      final _PhotoRepository repo = _PhotoRepository();
      final ProviderContainer c = _container(repo);

      await c
          .read(coachPhotoSendProvider.notifier)
          .send(MealPhoto.fromBytes(_jpeg)!);

      expect(repo.fileNames.single, 'photo.jpg');
      expect(repo.mimeTypes.single, 'image/jpeg');
    });

    test('실패하면 실패로 남고, 다시 보내기는 같은 멱등키를 쓴다', () async {
      final _PhotoRepository repo = _PhotoRepository(failures: 1);
      final ProviderContainer c = _container(repo);
      final CoachPhotoSendController ctrl = c.read(
        coachPhotoSendProvider.notifier,
      );

      expect(await ctrl.send(MealPhoto.fromBytes(_png)!), isFalse);
      expect(
        c.read(coachPhotoSendProvider).single.status,
        CoachPhotoSendStatus.failed,
      );

      expect(await ctrl.retry('photo-1'), isTrue);
      expect(repo.requestIds, <String>['photo-1', 'photo-1']);
      expect(
        c.read(coachPhotoSendProvider).single.status,
        CoachPhotoSendStatus.sent,
      );
    });

    test('보내는 중인 사진은 다시 보내지 않는다', () async {
      final _PhotoRepository repo = _PhotoRepository()
        ..gate = Completer<void>();
      final ProviderContainer c = _container(repo);
      final CoachPhotoSendController ctrl = c.read(
        coachPhotoSendProvider.notifier,
      );

      final Future<bool> sending = ctrl.send(MealPhoto.fromBytes(_png)!);
      expect(await ctrl.retry('photo-1'), isFalse);
      repo.gate!.complete();
      await sending;

      expect(repo.requestIds, hasLength(1));
    });

    test('실패한 사진을 지우면 아무것도 보내지 않고 사라진다', () async {
      final _PhotoRepository repo = _PhotoRepository(failures: 1);
      final ProviderContainer c = _container(repo);
      final CoachPhotoSendController ctrl = c.read(
        coachPhotoSendProvider.notifier,
      );

      await ctrl.send(MealPhoto.fromBytes(_png)!);
      ctrl.discard('photo-1');

      expect(c.read(coachPhotoSendProvider), isEmpty);
      expect(repo.requestIds, hasLength(1));
    });

    test('사진마다 멱등키가 따로다', () async {
      final _PhotoRepository repo = _PhotoRepository();
      final ProviderContainer c = _container(repo);
      final CoachPhotoSendController ctrl = c.read(
        coachPhotoSendProvider.notifier,
      );

      await ctrl.send(MealPhoto.fromBytes(_png)!);
      await ctrl.send(MealPhoto.fromBytes(_jpeg)!);

      expect(repo.requestIds, <String>['photo-1', 'photo-2']);
      expect(c.read(coachPhotoSendProvider), hasLength(2));
    });

    test('담당 저장소가 바뀌면 대기 사진을 비운다', () async {
      final StateProvider<MockMemberCoachRepository> current =
          StateProvider<MockMemberCoachRepository>(
            (ref) => _PhotoRepository(failures: 1),
          );
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWith(
            (ref) => ref.watch(current),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c
          .read(coachPhotoSendProvider.notifier)
          .send(MealPhoto.fromBytes(_png)!);
      expect(c.read(coachPhotoSendProvider), hasLength(1));

      c.read(current.notifier).state = MockMemberCoachRepository();
      expect(c.read(coachPhotoSendProvider), isEmpty);
    });

    test('서버 한도보다 큰 사진은 6MB 기준으로 거른다', () {
      expect(CoachPhotoSendController.maxBytes, 6 * 1024 * 1024);
    });
  });
}

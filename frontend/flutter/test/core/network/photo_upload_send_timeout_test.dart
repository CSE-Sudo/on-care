/// 사진 업로드가 전역 보내기 한도(10초)에 끊기던 문제. (#3141)
///
/// 느린 회선(헬스장 Wi-Fi·지하·약한 LTE)에서 식단 사진·채팅 사진을 올리면
/// 다 보내기도 전에 요청이 끊겨, 회원은 "분석에 실패" 를 보고 다시 찍기를
/// 되풀이했다. 사진을 올리는 두 요청만 보내기 한도를 늘리고, 일반 JSON 요청은
/// 지금 한도를 그대로 둔다.
///
/// 앱과 같은 `dioProvider`(실서버 모드)를 쓰고 어댑터만 바꿔, 전역
/// `BaseOptions` 와 요청 단위 `Options` 가 합쳐진 **실제로 나가는 값**을 본다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/network/request_timeouts.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';

/// JPEG 서명. 형식 판정은 앞 바이트만 본다.
final Uint8List _jpeg = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

MealPhoto get _photo => MealPhoto.fromBytes(_jpeg)!;

const Map<String, Object?> _analyzeResponse = <String, Object?>{
  'entry_id': 'diet-saved',
  'time_label': '12:10',
  'analysis': <String, Object?>{
    'foods': <Object?>[
      <String, Object?>{'name': '현미밥', 'calories': 300},
    ],
    'total_calories': 300,
    'total_sodium_mg': 5,
    'total_sugar_g': 0.5,
    'coach_comment': '',
    'engine': 'stub',
  },
};

const Map<String, Object?> _chatResponse = <String, Object?>{
  'id': 'chat-9',
  'sender': 'me',
  'body': '',
  'time_label': '09:30',
  'created_at': '2026-09-27T00:30:00Z',
  'attachment': <String, Object?>{
    'type': 'image',
    'file_name': 'photo.jpg',
    'file_id': 'file-9',
    'file_size': 6,
    'download_path': '/chat/attachments/file-9',
  },
};

/// 네트워크로 나가지 않고 요청을 받아 두는 어댑터.
///
/// [failWith] 를 주면 그 종류의 Dio 예외로 끊는다 — 실제 어댑터가 보내기
/// 한도를 넘겼을 때 던지는 것과 같은 모양이다.
class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  DioExceptionType? failWith;

  RequestOptions request(String path) =>
      requests.lastWhere((RequestOptions r) => r.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final DioExceptionType? failure = failWith;
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure);
    }
    final Map<String, Object?> body = switch (options.path) {
      '/diet/analyze' => _analyzeResponse,
      '/me/coach/chat/image' => _chatResponse,
      _ => const <String, Object?>{'ok': true},
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(Dio, _CapturingAdapter) _setUp() {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: Environment.prod,
          apiBaseUrl: 'https://api.test/v1',
          useMockApi: false,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final Dio dio = container.read(dioProvider);
  final _CapturingAdapter adapter = _CapturingAdapter();
  dio.httpClientAdapter = adapter;
  return (dio, adapter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('한도 값', () {
    test('사진 업로드 보내기 한도는 1분이고 전역 한도보다 길다', () {
      expect(photoUploadSendTimeout, const Duration(seconds: 60));
      expect(photoUploadSendTimeout, greaterThan(apiSendTimeout));
    });

    test('전역 한도는 지금 값 그대로다 — 연결 10초·응답 15초·보내기 10초', () {
      final (Dio dio, _) = _setUp();

      expect(dio.options.connectTimeout, const Duration(seconds: 10));
      expect(dio.options.receiveTimeout, const Duration(seconds: 15));
      expect(dio.options.sendTimeout, const Duration(seconds: 10));
      expect(dio.options.sendTimeout, apiSendTimeout);
    });
  });

  group('식단 사진 분석 /diet/analyze', () {
    test('보내기 한도는 사진 업로드 한도, 응답 대기는 분석 한도다', () async {
      final (Dio dio, _CapturingAdapter adapter) = _setUp();

      await DioDietRepository(
        dio,
      ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'meal-1');

      final RequestOptions sent = adapter.request('/diet/analyze');
      expect(sent.sendTimeout, photoUploadSendTimeout);
      // #2847 의 응답 대기 연장은 그대로 남는다.
      expect(sent.receiveTimeout, DioDietRepository.analyzeTimeout);
      expect(sent.data, isA<FormData>());
    });

    test('보내다 한도를 넘기면 지금처럼 연결 오류로 떨어진다', () async {
      final (Dio dio, _CapturingAdapter adapter) = _setUp();
      adapter.failWith = DioExceptionType.sendTimeout;

      await expectLater(
        DioDietRepository(
          dio,
        ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'meal-1'),
        throwsA(isA<NetworkError>()),
      );
    });

    test('보내다 끊긴 요청은 다시 보내지 않는다 — 서버가 사진을 다 받지 못했다', () async {
      // 응답 대기에서 끊긴 것(#2847)과 달리, 보내기에서 끊겼으면 서버에 저장된
      // 끼니가 없다. 멱등키가 있어도 같은 요청을 자동으로 한 번 더 올리지 않고
      // 회원에게 실패를 알려 다시 시도를 맡긴다.
      final (Dio dio, _CapturingAdapter adapter) = _setUp();
      adapter.failWith = DioExceptionType.sendTimeout;

      await expectLater(
        DioDietRepository(
          dio,
        ).analyze(photo: _photo, mealType: 'lunch', idempotencyKey: 'meal-1'),
        throwsA(isA<NetworkError>()),
      );
      expect(
        adapter.requests.where((RequestOptions r) => r.path == '/diet/analyze'),
        hasLength(1),
      );
    });
  });

  group('채팅 사진 /me/coach/chat/image', () {
    test('보내기 한도는 사진 업로드 한도, 응답 대기는 전역 한도다', () async {
      final (Dio dio, _CapturingAdapter adapter) = _setUp();

      await DioMemberCoachRepository(dio).sendPhoto(
        _jpeg,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        clientRequestId: 'photo-1',
      );

      final RequestOptions sent = adapter.request('/me/coach/chat/image');
      expect(sent.sendTimeout, photoUploadSendTimeout);
      expect(sent.receiveTimeout, apiReceiveTimeout);
      expect(sent.data, isA<FormData>());
    });

    test('보내다 한도를 넘기면 연결 오류로 떨어진다', () async {
      final (Dio dio, _CapturingAdapter adapter) = _setUp();
      adapter.failWith = DioExceptionType.sendTimeout;

      await expectLater(
        DioMemberCoachRepository(dio).sendPhoto(
          _jpeg,
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
          clientRequestId: 'photo-1',
        ),
        throwsA(isA<NetworkError>()),
      );
    });
  });

  group('일반 JSON 요청', () {
    test('글 메시지·조회는 전역 보내기 한도(10초) 그대로다', () async {
      final (Dio dio, _CapturingAdapter adapter) = _setUp();

      await dio.post<Map<String, Object?>>(
        '/me/coach/chat',
        data: <String, Object?>{'text': '안녕하세요'},
      );
      await dio.get<Map<String, Object?>>('/diet/days/today');

      expect(adapter.request('/me/coach/chat').sendTimeout, apiSendTimeout);
      expect(adapter.request('/diet/days/today').sendTimeout, apiSendTimeout);
      expect(
        adapter.request('/me/coach/chat').sendTimeout,
        const Duration(seconds: 10),
      );
    });

    test('사진 업로드 뒤에도 다음 요청의 한도는 전역 값으로 돌아온다', () async {
      // 요청 단위 Options 가 공유 Dio 의 기본값을 바꾸지 않음을 확인한다.
      final (Dio dio, _CapturingAdapter adapter) = _setUp();

      await DioMemberCoachRepository(dio).sendPhoto(
        _jpeg,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        clientRequestId: 'photo-1',
      );
      await dio.post<Map<String, Object?>>(
        '/me/coach/chat',
        data: <String, Object?>{'text': '방금 보낸 사진이에요'},
      );

      expect(dio.options.sendTimeout, apiSendTimeout);
      expect(adapter.request('/me/coach/chat').sendTimeout, apiSendTimeout);
    });
  });
}

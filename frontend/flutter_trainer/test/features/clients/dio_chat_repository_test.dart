import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_chat_repository.dart';
import 'package:oncare_trainer/features/clients/domain/chat_thread_paging.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body, String path) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: body,
);

DioException _httpError(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late DioChatRepository repo;

  setUp(() {
    dio = _MockDio();
    var requestId = 0;
    repo = DioChatRepository(dio, requestIdFactory: () => 'req-${++requestId}');
  });

  test('watchThread parses the message list (oldest→newest)', () async {
    when(() => dio.get<List<dynamic>>('/trainer/clients/m1/chat')).thenAnswer(
      (_) async => _ok<List<dynamic>>(<dynamic>[
        <String, Object?>{
          'id': 'a',
          'sender': 'client',
          'body': '안녕',
          'time_label': '9:00',
          'created_at': '2026-07-30T09:00:00',
        },
        <String, Object?>{
          'id': 'b',
          'sender': 'trainer',
          'body': '네',
          'time_label': '9:01',
          'created_at': '2026-07-30T09:01:00',
        },
      ], '/trainer/clients/m1/chat'),
    );

    final thread = await repo.watchThread('m1').first;
    expect(thread.map((m) => m.id).toList(), <String>['a', 'b']);
    expect(thread.last.sender, ChatSender.trainer);
  });

  test('watchThread polls until its subscription is cancelled', () async {
    var calls = 0;
    when(() => dio.get<List<dynamic>>('/trainer/clients/m1/chat')).thenAnswer((
      _,
    ) async {
      calls += 1;
      return _ok<List<dynamic>>(<dynamic>[
        <String, Object?>{
          'id': 'm$calls',
          'sender': 'client',
          'body': 'message $calls',
          'time_label': '09:00',
          'created_at': '2026-08-10T09:00:00Z',
        },
      ], '/trainer/clients/m1/chat');
    });

    final emissions = await DioChatRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    ).watchThread('m1').take(2).toList().timeout(const Duration(seconds: 1));

    expect(emissions.map((items) => items.single.id), <String>['m1', 'm2']);
    expect(calls, 2);
  });

  test(
    'watchThread keeps the last value across a transient poll failure',
    () async {
      var calls = 0;
      when(() => dio.get<List<dynamic>>('/trainer/clients/m1/chat')).thenAnswer(
        (_) async {
          calls += 1;
          if (calls == 2) {
            throw _httpError(503, '/trainer/clients/m1/chat');
          }
          return _ok<List<dynamic>>(<dynamic>[
            <String, Object?>{
              'id': calls == 1 ? 'before' : 'after',
              'sender': 'client',
              'body': 'message',
              'time_label': '09:00',
              'created_at': '2026-08-10T09:00:00Z',
            },
          ], '/trainer/clients/m1/chat');
        },
      );

      final emissions = await DioChatRepository(
        dio,
        pollInterval: const Duration(milliseconds: 5),
      ).watchThread('m1').take(2).toList().timeout(const Duration(seconds: 1));

      expect(emissions.map((items) => items.single.id), <String>[
        'before',
        'after',
      ]);
      expect(calls, 3);
    },
  );

  test(
    'watchThread pauses in the background and resumes immediately',
    () async {
      var calls = 0;
      when(() => dio.get<List<dynamic>>('/trainer/clients/m1/chat')).thenAnswer(
        (_) async {
          calls += 1;
          return _ok<List<dynamic>>(
            const <dynamic>[],
            '/trainer/clients/m1/chat',
          );
        },
      );
      final repo = DioChatRepository(
        dio,
        pollInterval: const Duration(milliseconds: 20),
      );
      final first = Completer<void>();
      final subscription = repo.watchThread('m1').listen((_) {
        if (!first.isCompleted) first.complete();
      });
      final binding = TestWidgetsFlutterBinding.instance;
      try {
        await first.future.timeout(const Duration(seconds: 1));

        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(calls, 1);

        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(calls, 2);

        await subscription.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(calls, 2);
      } finally {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await subscription.cancel();
      }
    },
  );

  test('sendTrainerMessage POSTs the trimmed text', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/chat',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'id': 'x',
      }, '/trainer/clients/m1/chat'),
    );

    await repo.sendTrainerMessage(clientId: 'm1', text: '  안녕하세요  ');

    verify(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/chat',
        data: <String, Object?>{'text': '안녕하세요', 'client_request_id': 'req-1'},
      ),
    ).called(1);
  });

  test('a failed send reuses its key; a later send gets a new key', () async {
    var calls = 0;
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/chat',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) throw _httpError(503, '/trainer/clients/m1/chat');
      return _ok<Map<String, Object?>>(<String, Object?>{
        'id': 'x',
      }, '/trainer/clients/m1/chat');
    });

    await expectLater(
      repo.sendTrainerMessage(clientId: 'm1', text: '재시도'),
      throwsA(isA<AppError>()),
    );
    await repo.sendTrainerMessage(clientId: 'm1', text: '재시도');
    await repo.sendTrainerMessage(clientId: 'm1', text: '재시도');

    final bodies = verify(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/chat',
        data: captureAny(named: 'data'),
      ),
    ).captured.cast<Map<String, Object?>>();
    expect(bodies[0]['client_request_id'], bodies[1]['client_request_id']);
    expect(
      bodies[2]['client_request_id'],
      isNot(bodies[1]['client_request_id']),
    );
  });

  test('another message does not replace a failed send request id', () async {
    final firstResponse = Completer<Response<Map<String, Object?>>>();
    var isFirstAttempt = true;
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/chat',
        data: any(named: 'data'),
      ),
    ).thenAnswer((invocation) {
      final data = invocation.namedArguments[#data]! as Map<String, Object?>;
      if (data['text'] == '첫 메시지' && isFirstAttempt) {
        isFirstAttempt = false;
        return firstResponse.future;
      }
      return Future<Response<Map<String, Object?>>>.value(
        _ok<Map<String, Object?>>(<String, Object?>{
          'id': 'x',
        }, '/trainer/clients/m1/chat'),
      );
    });

    final firstSend = repo.sendTrainerMessage(clientId: 'm1', text: '첫 메시지');
    final firstFailure = expectLater(firstSend, throwsA(isA<AppError>()));
    await repo.sendTrainerMessage(clientId: 'm1', text: '두 번째 메시지');
    firstResponse.completeError(_httpError(503, '/trainer/clients/m1/chat'));
    await firstFailure;
    await repo.sendTrainerMessage(clientId: 'm1', text: '첫 메시지');

    final bodies = verify(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/chat',
        data: captureAny(named: 'data'),
      ),
    ).captured.cast<Map<String, Object?>>();
    expect(bodies.map((body) => body['text']), <String>[
      '첫 메시지',
      '두 번째 메시지',
      '첫 메시지',
    ]);
    expect(bodies[0]['client_request_id'], bodies[2]['client_request_id']);
    expect(
      bodies[1]['client_request_id'],
      isNot(bodies[0]['client_request_id']),
    );
  });

  test('sendTrainerMessage skips the network call for blank text', () async {
    await repo.sendTrainerMessage(clientId: 'm1', text: '   ');
    verifyNever(
      () => dio.post<Map<String, Object?>>(any(), data: any(named: 'data')),
    );
  });

  test('sendTrainerMessage surfaces a failure as AppError', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/chat',
        data: any(named: 'data'),
      ),
    ).thenThrow(_httpError(500, '/trainer/clients/m1/chat'));

    await expectLater(
      repo.sendTrainerMessage(clientId: 'm1', text: 'hi'),
      throwsA(isA<AppError>()),
    );
  });

  test('watchUnreadCounts parses the per-client map', () async {
    when(
      () => dio.get<Map<String, Object?>>('/trainer/chat/unread'),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'm1': 2,
        'm2': 0,
      }, '/trainer/chat/unread'),
    );

    final unread = await repo.watchUnreadCounts().first;
    expect(unread['m1'], 2);
    expect(unread['m2'], 0);
  });

  test('watchUnreadCounts keeps counting so a message that arrives while the '
      'trainer is elsewhere reaches the badge (#917)', () async {
    var calls = 0;
    when(
      () => dio.get<Map<String, Object?>>('/trainer/chat/unread'),
    ).thenAnswer((_) async {
      calls += 1;
      return _ok<Map<String, Object?>>(<String, Object?>{
        'm1': calls,
      }, '/trainer/chat/unread');
    });

    final emissions = await DioChatRepository(
      dio,
      unreadPollInterval: const Duration(milliseconds: 5),
    ).watchUnreadCounts().take(2).toList().timeout(const Duration(seconds: 1));

    expect(
      emissions.map((counts) => counts['m1']).toList(),
      <int>[1, 2],
      reason: '한 번 세고 끝나면 배지가 처음 숫자에 멈춘다',
    );
  });

  test('watchUnreadCounts stops counting once nothing listens', () async {
    var calls = 0;
    when(
      () => dio.get<Map<String, Object?>>('/trainer/chat/unread'),
    ).thenAnswer((_) async {
      calls += 1;
      return _ok<Map<String, Object?>>(
        const <String, Object?>{},
        '/trainer/chat/unread',
      );
    });

    final subscription = DioChatRepository(
      dio,
      unreadPollInterval: const Duration(milliseconds: 5),
    ).watchUnreadCounts().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await subscription.cancel();
    final int afterCancel = calls;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(calls, afterCancel);
  });

  test('markThreadRead POSTs to the read endpoint', () async {
    when(
      () => dio.post<Map<String, Object?>>('/trainer/clients/m1/chat/read'),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'marked_read': 2,
      }, '/trainer/clients/m1/chat/read'),
    );

    await repo.markThreadRead('m1');
    verify(
      () => dio.post<Map<String, Object?>>('/trainer/clients/m1/chat/read'),
    ).called(1);
  });

  test('watchThread surfaces a 404 (not this trainer\'s client)', () async {
    when(
      () => dio.get<List<dynamic>>('/trainer/clients/x/chat'),
    ).thenThrow(_httpError(404, '/trainer/clients/x/chat'));

    await expectLater(repo.watchThread('x'), emitsError(isA<NotFoundError>()));
  });

  test('encodes an opaque member id in every client-scoped path', () async {
    const encoded = 'member%2Fwith%3Freserved';
    when(
      () => dio.get<List<dynamic>>('/trainer/clients/$encoded/chat'),
    ).thenAnswer(
      (_) async => _ok<List<dynamic>>(
        const <dynamic>[],
        '/trainer/clients/$encoded/chat',
      ),
    );
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/$encoded/chat',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(
        const <String, Object?>{},
        '/trainer/clients/$encoded/chat',
      ),
    );
    when(
      () =>
          dio.post<Map<String, Object?>>('/trainer/clients/$encoded/chat/read'),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(
        const <String, Object?>{},
        '/trainer/clients/$encoded/chat/read',
      ),
    );

    await repo.watchThread('member/with?reserved').first;
    await repo.sendTrainerMessage(clientId: 'member/with?reserved', text: 'hi');
    await repo.markThreadRead('member/with?reserved');

    verify(
      () => dio.get<List<dynamic>>('/trainer/clients/$encoded/chat'),
    ).called(1);
    verify(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/$encoded/chat',
        data: <String, Object?>{'text': 'hi', 'client_request_id': 'req-1'},
      ),
    ).called(1);
    verify(
      () =>
          dio.post<Map<String, Object?>>('/trainer/clients/$encoded/chat/read'),
    ).called(1);
  });

  test('malformed thread entries fail instead of being dropped', () {
    when(() => dio.get<List<dynamic>>('/trainer/clients/m1/chat')).thenAnswer(
      (_) async => _ok<List<dynamic>>(<dynamic>[
        'not-an-object',
      ], '/trainer/clients/m1/chat'),
    );

    expect(repo.watchThread('m1'), emitsError(isA<FormatException>()));
  });

  group('fetchOlder (#2749)', () {
    ClientChatMessage oldest() => ClientChatMessage(
      id: 'msg-51',
      sender: ChatSender.client,
      body: '가장 오래된 것',
      timeLabel: '08:10',
      createdAt: DateTime.parse('2026-09-14T23:10:00.123456+00:00'),
    );

    Map<String, Object?> row(String id, String createdAt) => <String, Object?>{
      'id': id,
      'sender': 'client',
      'body': id,
      'time_label': '08:00',
      'created_at': createdAt,
    };

    test('보던 쪽의 가장 오래된 메시지를 (before, before_id) 커서로 넘긴다', () async {
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/clients/m1/chat',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _ok<List<dynamic>>(<dynamic>[
          row('msg-1', '2026-09-14T22:00:00+00:00'),
        ], '/trainer/clients/m1/chat'),
      );

      await repo.fetchOlder('m1', before: oldest());

      final captured =
          verify(
                () => dio.get<List<dynamic>>(
                  '/trainer/clients/m1/chat',
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(captured, <String, Object?>{
        'limit': chatPageSize,
        // UTC ISO — 마이크로초까지 그대로라 서버의 복합 커서와 경계가 맞는다.
        'before': '2026-09-14T23:10:00.123456Z',
        'before_id': 'msg-51',
      });
    });

    test('응답을 시각→id 순으로 맞춰 돌려준다', () async {
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/clients/m1/chat',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _ok<List<dynamic>>(<dynamic>[
          row('b', '2026-09-14T22:00:00+00:00'),
          row('c', '2026-09-14T22:30:00+00:00'),
          row('a', '2026-09-14T22:00:00+00:00'),
        ], '/trainer/clients/m1/chat'),
      );

      final page = await repo.fetchOlder('m1', before: oldest());

      expect(page.map((m) => m.id), <String>['a', 'b', 'c']);
    });

    test('폴링은 여전히 커서 없이 최신 쪽만 받는다', () async {
      when(() => dio.get<List<dynamic>>('/trainer/clients/m1/chat')).thenAnswer(
        (_) async => _ok<List<dynamic>>(<dynamic>[
          row('latest', '2026-09-15T01:00:00+00:00'),
        ], '/trainer/clients/m1/chat'),
      );

      await repo.watchThread('m1').first;

      verify(
        () => dio.get<List<dynamic>>('/trainer/clients/m1/chat'),
      ).called(1);
    });

    test('서버 오류는 AppError 로 바꿔 던진다', () {
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/clients/m1/chat',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(_httpError(500, '/trainer/clients/m1/chat'));

      expect(repo.fetchOlder('m1', before: oldest()), throwsA(isA<AppError>()));
    });
  });
}

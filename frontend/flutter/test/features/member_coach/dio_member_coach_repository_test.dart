import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

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
  late DioMemberCoachRepository repo;

  setUp(() {
    dio = _MockDio();
    var requestId = 0;
    repo = DioMemberCoachRepository(
      dio,
      requestIdFactory: () => 'req-${++requestId}',
    );
  });

  test('fetchCoach returns the coach', () async {
    when(() => dio.get<Map<String, Object?>>('/me/coach')).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'trainer_id': 't1',
        'name': '김트레이너',
      }, '/me/coach'),
    );
    final coach = await repo.fetchCoach();
    expect(coach?.name, '김트레이너');
  });

  test('fetchCoach returns null when the member has no coach (404)', () async {
    when(
      () => dio.get<Map<String, Object?>>('/me/coach'),
    ).thenThrow(_httpError(404, '/me/coach'));
    expect(await repo.fetchCoach(), isNull);
  });

  test('fetchRoutines parses the received routines', () async {
    when(() => dio.get<List<dynamic>>('/me/coach/routines')).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/me/coach/routines'),
        statusCode: 200,
        data: <dynamic>[
          <String, Object?>{
            'id': 'r1',
            'name': '저강도 유산소',
            'minutes': 20,
            'type': '유산소',
            'reason': '',
            'source': 'ai',
          },
        ],
      ),
    );
    final routines = await repo.fetchRoutines();
    expect(routines.single.name, '저강도 유산소');
  });

  test(
    'completeRoutine posts the result and returns completion state',
    () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/me/coach/routines/r1/complete',
          data: <String, Object?>{'minutes': 35, 'intensity': 'moderate'},
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'id': 'r1',
          'name': '코어 운동',
          'minutes': 30,
          'type': '근력',
          'reason': '',
          'source': 'trainer',
          'completed': true,
        }, '/me/coach/routines/r1/complete'),
      );

      final CoachRoutine completed = await repo.completeRoutine(
        'r1',
        minutes: 35,
      );

      expect(completed.completed, isTrue);
    },
  );

  test('fetchChat parses and sorts the thread oldest first', () async {
    when(() => dio.get<List<dynamic>>('/me/coach/chat')).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/me/coach/chat'),
        statusCode: 200,
        data: <dynamic>[
          <String, Object?>{
            'id': 'm2',
            'sender': 'me',
            'body': '반가워요',
            'time_label': '13:21',
            'created_at': '2026-08-07T13:21:00Z',
          },
          <String, Object?>{
            'id': 'm1',
            'sender': 'trainer',
            'body': '안녕',
            'time_label': '13:20',
            'created_at': '2026-08-07T13:20:00Z',
          },
        ],
      ),
    );
    final chat = await repo.fetchChat();
    expect(chat.map((CoachMessage message) => message.id), <String>[
      'm1',
      'm2',
    ]);
    expect(chat.first.sender, CoachSender.trainer);
  });

  test(
    'watchChat polls and retries without replacing the last good data',
    () async {
      var calls = 0;
      when(() => dio.get<List<dynamic>>('/me/coach/chat')).thenAnswer((
        _,
      ) async {
        calls += 1;
        if (calls == 2) throw _httpError(503, '/me/coach/chat');
        return _ok<List<dynamic>>(<dynamic>[
          <String, Object?>{
            'id': calls == 1 ? 'before' : 'after',
            'sender': 'trainer',
            'body': 'message',
            'time_label': '09:00',
            'created_at': '2026-08-10T09:00:00Z',
          },
        ], '/me/coach/chat');
      });

      final emissions = await DioMemberCoachRepository(
        dio,
        pollInterval: const Duration(milliseconds: 5),
      ).watchChat().take(2).toList().timeout(const Duration(seconds: 1));

      expect(emissions.map((items) => items.single.id), <String>[
        'before',
        'after',
      ]);
      expect(calls, 3);
    },
  );

  test('fetchChat rejects a malformed list item', () async {
    when(() => dio.get<List<dynamic>>('/me/coach/chat')).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/me/coach/chat'),
        statusCode: 200,
        data: <dynamic>['invalid'],
      ),
    );

    expect(repo.fetchChat(), throwsFormatException);
  });

  test('sendMessage POSTs the trimmed text; skips blank', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        '/me/coach/chat',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'id': 'x',
      }, '/me/coach/chat'),
    );

    await repo.sendMessage('  좋아요  ');
    verify(
      () => dio.post<Map<String, Object?>>(
        '/me/coach/chat',
        data: <String, Object?>{'text': '좋아요', 'client_request_id': 'req-1'},
      ),
    ).called(1);

    await repo.sendMessage('   ');
    verifyNoMoreInteractions(dio);
  });

  test('send retry keeps its request id and success rotates it', () async {
    var calls = 0;
    when(
      () => dio.post<Map<String, Object?>>(
        '/me/coach/chat',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) throw _httpError(503, '/me/coach/chat');
      return _ok<Map<String, Object?>>(<String, Object?>{
        'id': 'x',
      }, '/me/coach/chat');
    });

    await expectLater(repo.sendMessage('재시도'), throwsA(isA<AppError>()));
    await repo.sendMessage('재시도');
    await repo.sendMessage('재시도');

    final bodies = verify(
      () => dio.post<Map<String, Object?>>(
        '/me/coach/chat',
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
        '/me/coach/chat',
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
        }, '/me/coach/chat'),
      );
    });

    final firstSend = repo.sendMessage('첫 메시지');
    final firstFailure = expectLater(firstSend, throwsA(isA<AppError>()));
    await repo.sendMessage('두 번째 메시지');
    firstResponse.completeError(_httpError(503, '/me/coach/chat'));
    await firstFailure;
    await repo.sendMessage('첫 메시지');

    final bodies = verify(
      () => dio.post<Map<String, Object?>>(
        '/me/coach/chat',
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

  test('unreadCount reads the unread field', () async {
    when(
      () => dio.get<Map<String, Object?>>('/me/coach/chat/unread'),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'unread': 3,
      }, '/me/coach/chat/unread'),
    );
    expect(await repo.unreadCount(), 3);
  });

  test('unreadCount rejects a malformed unread field', () async {
    when(
      () => dio.get<Map<String, Object?>>('/me/coach/chat/unread'),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'unread': '3',
      }, '/me/coach/chat/unread'),
    );

    expect(repo.unreadCount(), throwsFormatException);
  });

  test('markRead POSTs the shared thread read endpoint', () async {
    when(
      () => dio.post<Map<String, Object?>>('/me/coach/chat/read'),
    ).thenAnswer(
      (_) async => _ok<Map<String, Object?>>(<String, Object?>{
        'marked_read': 1,
      }, '/me/coach/chat/read'),
    );

    await repo.markRead();

    verify(
      () => dio.post<Map<String, Object?>>('/me/coach/chat/read'),
    ).called(1);
  });
}

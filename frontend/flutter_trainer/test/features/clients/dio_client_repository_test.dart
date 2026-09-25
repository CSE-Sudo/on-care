import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/clients/data/dtos/client_dtos.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

class _MockDio extends Mock implements Dio {}

Response<List<dynamic>> _okList(List<dynamic> body, String path) =>
    Response<List<dynamic>>(
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
  late DioClientRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioClientRepository(dio);
  });

  test('watchClients parses the roster', () async {
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/clients',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _okList(<dynamic>[
        <String, Object?>{'id': 'm1', 'name': '김민수', 'sodium_mg': 2100},
        <String, Object?>{'id': 'm2', 'name': '이지수', 'sodium_mg': 1500},
      ], '/trainer/clients'),
    );

    final clients = await repo.watchClients().first;
    expect(clients.map((c) => c.id).toList(), <String>['m1', 'm2']);
    expect(clients.first.sodiumOverBudget, isTrue);
  });

  test('로스터는 명단이 끝날 때까지 쪽을 이어 받는다 (#980)', () async {
    // 서버가 한 쪽만 준다고 화면의 명단이 잘리면 안 된다 — 사이드바 개수·검색이
    // 모두 전체를 전제로 읽는 자리라, 트레이너는 빠진 회원을 찾아 헤매게 된다.
    final List<Map<String, Object?>> full = <Map<String, Object?>>[
      for (int i = 0; i < rosterPageSize; i++)
        <String, Object?>{'id': 'm$i', 'name': '회원 $i'},
    ];
    final List<Object?> cursors = <Object?>[];
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/clients',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((invocation) async {
      final Map<Object?, Object?> query =
          invocation.namedArguments[#queryParameters] as Map<Object?, Object?>;
      cursors.add(query['after_id']);
      return _okList(
        query['after_id'] == null
            ? full
            : <dynamic>[
                <String, Object?>{'id': 'last', 'name': '마지막 회원'},
              ],
        '/trainer/clients',
      );
    });

    final clients = await repo.watchClients().first;

    // 첫 쪽은 커서 없이, 다음 쪽은 받은 마지막 회원의 id 로 이어 받는다.
    expect(cursors, <Object?>[null, 'm${rosterPageSize - 1}']);
    expect(clients, hasLength(rosterPageSize + 1));
    expect(clients.map((c) => c.id), contains('last'));
  });

  test('the roster ordering puts the flagged client first', () async {
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/clients',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _okList(<dynamic>[
        <String, Object?>{'id': 'ok', 'name': 'A', 'sodium_mg': 2500},
        <String, Object?>{
          'id': 'over',
          'name': 'B',
          'sodium_mg': 1500,
          // 나트륨이 아니라 PT 관리 신호가 순서를 정한다(#2204).
          'signals': <Object?>[
            <String, Object?>{'kind': 'discomfort'},
          ],
        },
      ], '/trainer/clients'),
    );

    // Ordering is one shared pure function now; the API source has no
    // chat-recency signal to feed it.
    final clients = prioritizeClients(await repo.watchClients().first);
    expect(clients.first.id, 'over');
    expect(await repo.watchLastChatAt().first, isEmpty);
  });

  test('watchDiet parses the meals', () async {
    when(() => dio.get<List<dynamic>>('/trainer/clients/m1/diet')).thenAnswer(
      (_) async => _okList(<dynamic>[
        <String, Object?>{
          'meal': '점심',
          'items': '비빔밥',
          'calories': 600,
          'sodium_mg': 1200,
        },
      ], '/trainer/clients/m1/diet'),
    );

    final meals = await repo.watchDiet('m1').first;
    expect(meals.single.meal, '점심');
  });

  test(
    'updateHistoryFeedback writes and parses the shared history row',
    () async {
      const String path =
          '/trainer/clients/member%2F1/history/assigned-ex-r1/feedback';
      when(
        () => dio.put<Map<String, Object?>>(
          path,
          data: <String, Object?>{'feedback': '자세가 좋았어요'},
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: <String, Object?>{
            'id': 'assigned-ex-r1',
            'date_label': '8/13 (오늘)',
            'label': '코어 운동',
            'completion_rate': 100,
            'exercises': <Object?>['코어 운동 · 30분'],
            'client_feedback': '힘들었어요',
            'trainer_note': '자세가 좋았어요',
            'assigned_routine_id': 'r1',
          },
        ),
      );

      final updated = await repo.updateHistoryFeedback(
        'member/1',
        'assigned-ex-r1',
        '  자세가 좋았어요  ',
      );

      expect(updated.id, 'assigned-ex-r1');
      expect(updated.trainerNote, '자세가 좋았어요');
    },
  );

  test('the roster re-reads itself so a change made elsewhere lands without a '
      'manual refresh (#918)', () async {
    var calls = 0;
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/clients',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async {
      calls += 1;
      return _okList(<dynamic>[
        <String, Object?>{'id': 'm$calls', 'name': '김민수'},
      ], '/trainer/clients');
    });

    final emissions = await DioClientRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    ).watchClients().take(2).toList().timeout(const Duration(seconds: 1));

    expect(emissions.map((rows) => rows.single.id).toList(), <String>[
      'm1',
      'm2',
    ]);
  });

  test('a client\'s diet re-reads itself — a meal logged in the member app '
      'appears without the trainer pressing anything (#918)', () async {
    var calls = 0;
    when(() => dio.get<List<dynamic>>('/trainer/clients/m1/diet')).thenAnswer((
      _,
    ) async {
      calls += 1;
      return _okList(<dynamic>[
        for (var i = 0; i < calls; i++)
          <String, Object?>{
            'id': 'meal-$i',
            'meal': '아침',
            'name': '오트밀',
            'kcal': 320,
            'time_label': '08:0$i',
          },
      ], '/trainer/clients/m1/diet');
    });

    final emissions = await DioClientRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    ).watchDiet('m1').take(2).toList().timeout(const Duration(seconds: 1));

    expect(emissions.map((rows) => rows.length).toList(), <int>[1, 2]);
  });

  test('the roster stops re-reading once nothing listens', () async {
    var calls = 0;
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/clients',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async {
      calls += 1;
      return _okList(const <dynamic>[], '/trainer/clients');
    });

    final subscription = DioClientRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    ).watchClients().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await subscription.cancel();
    final int afterCancel = calls;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(calls, afterCancel);
  });

  test('a refresh failure keeps the last successful client data', () async {
    const String path = '/trainer/clients/m1/diet';
    var calls = 0;
    final Completer<void> firstValue = Completer<void>();
    final Completer<void> refreshAttempted = Completer<void>();
    when(() => dio.get<List<dynamic>>(path)).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) {
        return _okList(<dynamic>[
          <String, Object?>{
            'meal': '점심',
            'items': '비빔밥',
            'calories': 600,
            'sodium_mg': 1200,
          },
        ], path);
      }
      if (!refreshAttempted.isCompleted) refreshAttempted.complete();
      throw _httpError(503, path);
    });
    final values = <List<ClientDietEntry>>[];
    final errors = <Object>[];
    final subscription = repo.watchDiet('m1').listen((
      List<ClientDietEntry> value,
    ) {
      values.add(value);
      if (!firstValue.isCompleted) firstValue.complete();
    }, onError: (Object error, StackTrace stackTrace) => errors.add(error));
    try {
      await firstValue.future.timeout(const Duration(seconds: 1));

      repo.refreshClientData('m1');
      await refreshAttempted.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

      expect(calls, 2);
      expect(errors, isEmpty);
      expect(values, hasLength(1));
      expect(values.single.single.items, '비빔밥');
    } finally {
      await subscription.cancel();
    }
  });

  test(
    'an all-client refresh failure keeps the last successful roster',
    () async {
      const String path = '/trainer/clients';
      var calls = 0;
      final Completer<void> firstValue = Completer<void>();
      final Completer<void> refreshAttempted = Completer<void>();
      when(
        () => dio.get<List<dynamic>>(
          path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          return _okList(<dynamic>[
            <String, Object?>{'id': 'm1', 'name': '김민수', 'sodium_mg': 2100},
          ], path);
        }
        if (!refreshAttempted.isCompleted) refreshAttempted.complete();
        throw _httpError(503, path);
      });
      final values = <List<TrainerClient>>[];
      final errors = <Object>[];
      final subscription = repo.watchClients().listen((
        List<TrainerClient> value,
      ) {
        values.add(value);
        if (!firstValue.isCompleted) firstValue.complete();
      }, onError: (Object error, StackTrace stackTrace) => errors.add(error));
      try {
        await firstValue.future.timeout(const Duration(seconds: 1));

        repo.refreshAllClientData();
        await refreshAttempted.future.timeout(const Duration(seconds: 1));
        await Future<void>.delayed(Duration.zero);

        expect(calls, 2);
        expect(errors, isEmpty);
        expect(values, hasLength(1));
        expect(values.single.single.name, '김민수');
      } finally {
        await subscription.cancel();
      }
    },
  );

  test('active client data revalidates when the app regains focus', () async {
    var calls = 0;
    when(() => dio.get<List<dynamic>>('/trainer/clients/m1/diet')).thenAnswer((
      _,
    ) async {
      calls += 1;
      return _okList(<dynamic>[
        <String, Object?>{
          'meal': 'meal $calls',
          'items': 'items',
          'calories': 100,
          'sodium_mg': 100,
        },
      ], '/trainer/clients/m1/diet');
    });
    final first = Completer<void>();
    final subscription = repo.watchDiet('m1').listen((_) {
      if (!first.isCompleted) first.complete();
    });
    final binding = TestWidgetsFlutterBinding.instance;
    try {
      await first.future.timeout(const Duration(seconds: 1));
      expect(calls, 1);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(calls, 2);
    } finally {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await subscription.cancel();
    }
  });

  test('encodes an opaque client id as one path segment', () async {
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/clients/member%2Fwith%3Freserved/diet',
      ),
    ).thenAnswer(
      (_) async => _okList(
        const <dynamic>[],
        '/trainer/clients/member%2Fwith%3Freserved/diet',
      ),
    );

    await repo.watchDiet('member/with?reserved').first;

    verify(
      () => dio.get<List<dynamic>>(
        '/trainer/clients/member%2Fwith%3Freserved/diet',
      ),
    ).called(1);
  });

  test('malformed list entries fail instead of being silently dropped', () {
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/clients',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _okList(<dynamic>[
        <String, Object?>{'id': 'm1'},
        'not-an-object',
      ], '/trainer/clients'),
    );

    expect(repo.watchClients(), emitsError(isA<FormatException>()));
  });

  test(
    'watchHistory surfaces a 404 (not this trainer\'s client) as NotFoundError',
    () async {
      when(
        () => dio.get<List<dynamic>>('/trainer/clients/x/history'),
      ).thenThrow(_httpError(404, '/trainer/clients/x/history'));

      await expectLater(
        repo.watchHistory('x'),
        emitsError(isA<NotFoundError>()),
      );
    },
  );

  group('adding clients stays demo-only against the real API', () {
    test('advertises the roster as closed to additions', () {
      expect(repo.supportsRosterMutations, isFalse);
    });

    test('addClient throws UnsupportedError', () {
      expect(
        () => repo.addClient(name: 'x', goal: 'y'),
        throwsUnsupportedError,
      );
    });
    test('clientNameExists throws UnsupportedError', () {
      expect(() => repo.clientNameExists('x'), throwsUnsupportedError);
    });
  });

  group('활성/휴면 management state (#707)', () {
    const String path = '/trainer/clients/m1/status';

    test('setClientActive PUTs the requested state', () async {
      Map<String, Object?>? sent;
      when(
        () => dio.put<Map<String, Object?>>(path, data: any(named: 'data')),
      ).thenAnswer((invocation) async {
        sent = (invocation.namedArguments[#data] as Map<Object?, Object?>)
            .cast<String, Object?>();
        return Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: <String, Object?>{'member_id': 'm1', 'active': false},
        );
      });

      await repo.setClientActive('m1', false);
      expect(sent, <String, Object?>{'active': false});
    });

    test('a confirmed change re-fetches the roster so the badge follows the '
        'server, not the tap', () async {
      var rosterActive = true;
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/clients',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okList(<dynamic>[
          <String, Object?>{'id': 'm1', 'name': 'A', 'active': rosterActive},
        ], '/trainer/clients'),
      );
      when(
        () => dio.put<Map<String, Object?>>(path, data: any(named: 'data')),
      ).thenAnswer((_) async {
        rosterActive = false;
        return Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: <String, Object?>{'member_id': 'm1', 'active': false},
        );
      });

      final emissions = <bool>[];
      final sub = repo.watchClients().listen(
        (clients) => emissions.add(clients.single.active),
      );
      addTearDown(sub.cancel);
      // 첫 방출(활성)을 받은 뒤 상태를 바꾼다.
      await Future<void>.delayed(Duration.zero);
      await repo.setClientActive('m1', false);
      await Future<void>.delayed(Duration.zero);

      expect(emissions, <bool>[true, false]);
    });

    test('a rejected change surfaces a typed error and does not refresh the '
        'roster — the badge keeps the state the server still has', () async {
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/clients',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okList(<dynamic>[
          <String, Object?>{'id': 'm1', 'name': 'A', 'active': true},
        ], '/trainer/clients'),
      );
      when(
        () => dio.put<Map<String, Object?>>(path, data: any(named: 'data')),
      ).thenThrow(_httpError(409, path));

      final emissions = <bool>[];
      final sub = repo.watchClients().listen(
        (clients) => emissions.add(clients.single.active),
      );
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        repo.setClientActive('m1', false),
        throwsA(isA<AppError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emissions, <bool>[true]);
    });
  });

  test('removeClient DELETEs the assignment endpoint', () async {
    const path = '/trainer/clients/m1';
    when(() => dio.delete<void>(path)).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: path),
        statusCode: 204,
      ),
    );

    await repo.removeClient('m1');

    verify(() => dio.delete<void>(path)).called(1);
  });
}

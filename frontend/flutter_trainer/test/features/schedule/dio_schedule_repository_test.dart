import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_core/clock.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/dio_schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';

class _MockDio extends Mock implements Dio {}

Response<List<dynamic>> _okList(List<dynamic> body, String path) =>
    Response<List<dynamic>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body,
    );

Response<Map<String, dynamic>> _okMap(
  String path, [
  Map<String, dynamic> body = const <String, dynamic>{},
]) => Response<Map<String, dynamic>>(
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

const String _schedulePath = '/trainer/schedule';

Map<String, dynamic> _session({
  String id = 's1',
  String date = '2026-08-06',
  String time = '10:00',
  String clientName = '김민수',
  String? memberId = 'm1',
  String status = '예정',
  List<dynamic> program = const <dynamic>[],
}) => <String, dynamic>{
  'id': id,
  'date': date,
  'time': time,
  'member_id': memberId,
  'client_name': clientName,
  'type': '1:1 PT',
  'duration_minutes': 60,
  'status': status,
  'note': '',
  'program': program,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late DioScheduleRepository repo;

  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  setUp(() {
    dio = _MockDio();
    var requestId = 0;
    repo = DioScheduleRepository(
      dio,
      requestIdFactory: () => 'req-${++requestId}',
    );
    addTearDown(repo.dispose);
  });

  void stubGet(List<dynamic> body) {
    when(
      () => dio.get<List<dynamic>>(
        _schedulePath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => _okList(body, _schedulePath));
  }

  Map<String, dynamic> capturedQuery() {
    return verify(
          () => dio.get<List<dynamic>>(
            _schedulePath,
            queryParameters: captureAny(named: 'queryParameters'),
          ),
        ).captured.last
        as Map<String, dynamic>;
  }

  test('watchDate asks for a single day', () async {
    stubGet(<dynamic>[_session()]);

    final slots = await repo.watchDate('2026-08-06').first;

    expect(slots.single.id, 's1');
    expect(capturedQuery(), <String, String>{'date': '2026-08-06'});
  });

  test('watchRange asks for the whole week in ONE request', () async {
    stubGet(<dynamic>[
      _session(id: 'a', date: '2026-08-03'),
      _session(id: 'b', date: '2026-08-09'),
    ]);

    final slots = await repo.watchRange('2026-08-03', '2026-08-09').first;

    expect(slots.map((s) => s.id), <String>['a', 'b']);
    // A day-at-a-time contract would make this seven round trips.
    final calls = verify(
      () => dio.get<List<dynamic>>(
        _schedulePath,
        queryParameters: captureAny(named: 'queryParameters'),
      ),
    ).captured;
    expect(calls, hasLength(1));
    expect(calls.single, <String, String>{
      'from': '2026-08-03',
      'to': '2026-08-09',
    });
  });

  test('an external reservation is picked up by the active poll', () async {
    var calls = 0;
    when(
      () => dio.get<List<dynamic>>(
        _schedulePath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async {
      calls += 1;
      return _okList(<dynamic>[
        _session(id: 'before'),
        if (calls > 1) _session(id: 'member-reservation'),
      ], _schedulePath);
    });
    final pollingRepo = DioScheduleRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(pollingRepo.dispose);

    final emissions = await pollingRepo
        .watchRange('2026-08-06', '2026-08-12')
        .take(2)
        .toList()
        .timeout(const Duration(seconds: 1));

    expect(emissions.first.map((session) => session.id), <String>['before']);
    expect(emissions.last.map((session) => session.id), <String>[
      'before',
      'member-reservation',
    ]);
    expect(calls, 2);
  });

  test(
    'watchDate picks up an external reservation by polling (#2865)',
    () async {
      var calls = 0;
      when(
        () => dio.get<List<dynamic>>(
          _schedulePath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async {
        calls += 1;
        return _okList(<dynamic>[
          _session(id: 'before'),
          if (calls > 1) _session(id: 'member-reservation', time: '15:00'),
        ], _schedulePath);
      });
      final pollingRepo = DioScheduleRepository(
        dio,
        pollInterval: const Duration(milliseconds: 5),
      );
      addTearDown(pollingRepo.dispose);

      final emissions = await pollingRepo
          .watchDate('2026-08-06')
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 1));

      // 대시보드 오늘 일정은 이 조회를 쓴다 — 회원 앱에서 잡은 오늘 예약이
      // 트레이너가 아무것도 하지 않아도 나타난다.
      expect(emissions.last.map((session) => session.id), <String>[
        'before',
        'member-reservation',
      ]);
      final queries = verify(
        () => dio.get<List<dynamic>>(
          _schedulePath,
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      // 폴링으로 여러 번 읽어도 묻는 날짜는 구독한 그날 하나다. (Map 은 내용이
      // 같아도 Set 에서 서로 다른 원소라 날짜 값으로 모아 비교한다.)
      expect(
        queries.map((dynamic q) => (q as Map<String, String>)['date']).toSet(),
        <String>{'2026-08-06'},
      );
    },
  );

  test('watchToday re-reads the KST date on every poll (#2865)', () async {
    var now = DateTime(2026, 8, 20, 23, 59, 59);
    debugNowKstOverride = () => now;
    addTearDown(() => debugNowKstOverride = null);
    stubGet(<dynamic>[]);
    final pollingRepo = DioScheduleRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(pollingRepo.dispose);

    final sub = pollingRepo.watchToday().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    now = DateTime(2026, 8, 21, 0, 0, 1);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();

    final queries = verify(
      () => dio.get<List<dynamic>>(
        _schedulePath,
        queryParameters: captureAny(named: 'queryParameters'),
      ),
    ).captured.cast<Map<String, String>>();
    expect(queries.first, <String, String>{'date': '2026-08-20'});
    // 자정을 넘긴 뒤의 조회는 새 날짜를 묻는다 — 구독할 때의 날짜에 묶이지
    // 않는다.
    expect(queries.last, <String, String>{'date': '2026-08-21'});
  });

  test(
    'watchClientSessions filters by member id and returns newest first',
    () async {
      stubGet(<dynamic>[
        _session(id: 'old', date: '2026-08-01'),
        _session(id: 'new'),
      ]);

      final slots = await repo.watchClientSessions((
        id: 'm1',
        name: '김민수',
      )).first;

      // Server returns oldest→newest; the drift source is newest-first, so
      // both sources agree for the 루틴 tab.
      expect(slots.map((s) => s.id), <String>['new', 'old']);

      final query = capturedQuery();
      expect(query['member_id'], 'm1');
      // No date bounds: a range would silently drop sessions outside it,
      // and the 루틴 tab reads a missing row as "no record".
      expect(query.containsKey('from'), isFalse);
      expect(query.containsKey('to'), isFalse);
      expect(query.containsKey('date'), isFalse);
    },
  );

  test('a mutation makes live readers re-fetch', () async {
    stubGet(<dynamic>[_session(id: 'before')]);
    when(
      () => dio.post<Map<String, dynamic>>(
        _schedulePath,
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _okMap(_schedulePath));

    final emissions = <List<ScheduleSession>>[];
    final sub = repo.watchDate('2026-08-06').listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions, hasLength(1));

    stubGet(<dynamic>[_session(id: 'before'), _session(id: 'after')]);
    await repo.addSession(
      date: '2026-08-06',
      clientName: '김민수',
      time: '15:00',
      type: '1:1 PT',
      durationMinutes: 60,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // drift keeps screens in sync by watching a table; over HTTP the
    // write has to tell the readers itself.
    expect(emissions, hasLength(2));
    expect(emissions.last.map((s) => s.id), <String>['before', 'after']);
    await sub.cancel();
  });

  test('add retry reuses its request id; next create rotates it', () async {
    var calls = 0;
    when(
      () => dio.post<Map<String, dynamic>>(
        _schedulePath,
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) throw _httpError(503, _schedulePath);
      return _okMap(_schedulePath);
    });

    Future<void> add() => repo.addSession(
      date: '2026-08-06',
      clientName: '김민수',
      time: '15:00',
      type: '1:1 PT',
      durationMinutes: 60,
    );

    await expectLater(add(), throwsA(isA<AppError>()));
    await add();
    await add();

    final bodies = verify(
      () => dio.post<Map<String, dynamic>>(
        _schedulePath,
        data: captureAny(named: 'data'),
      ),
    ).captured.cast<Map<String, dynamic>>();
    expect(bodies[0]['client_request_id'], bodies[1]['client_request_id']);
    expect(
      bodies[2]['client_request_id'],
      isNot(bodies[1]['client_request_id']),
    );
  });

  test('another create does not replace a failed request id', () async {
    final firstResponse = Completer<Response<Map<String, dynamic>>>();
    var isFirstAttempt = true;
    when(
      () => dio.post<Map<String, dynamic>>(
        _schedulePath,
        data: any(named: 'data'),
      ),
    ).thenAnswer((invocation) {
      final data = invocation.namedArguments[#data]! as Map<String, dynamic>;
      if (data['note'] == '첫 일정' && isFirstAttempt) {
        isFirstAttempt = false;
        return firstResponse.future;
      }
      return Future<Response<Map<String, dynamic>>>.value(
        _okMap(_schedulePath),
      );
    });

    Future<void> add(String note) => repo.addSession(
      date: '2026-08-06',
      clientName: '김민수',
      time: '15:00',
      type: '1:1 PT',
      durationMinutes: 60,
      note: note,
    );

    final firstCreate = add('첫 일정');
    final firstFailure = expectLater(firstCreate, throwsA(isA<AppError>()));
    await add('두 번째 일정');
    firstResponse.completeError(_httpError(503, _schedulePath));
    await firstFailure;
    await add('첫 일정');

    final bodies = verify(
      () => dio.post<Map<String, dynamic>>(
        _schedulePath,
        data: captureAny(named: 'data'),
      ),
    ).captured.cast<Map<String, dynamic>>();
    expect(bodies.map((body) => body['note']), <String>[
      '첫 일정',
      '두 번째 일정',
      '첫 일정',
    ]);
    expect(bodies[0]['client_request_id'], bodies[2]['client_request_id']);
    expect(
      bodies[1]['client_request_id'],
      isNot(bodies[0]['client_request_id']),
    );
  });

  test('a FAILED mutation does not make readers re-fetch', () async {
    stubGet(<dynamic>[_session()]);
    when(
      () => dio.delete<Map<String, dynamic>>(any()),
    ).thenThrow(_httpError(500, _schedulePath));

    final emissions = <List<ScheduleSession>>[];
    final sub = repo.watchDate('2026-08-06').listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await expectLater(repo.deleteSession('s1'), throwsA(isA<ServerError>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Re-emitting here would flicker the timeline as if something had
    // changed when nothing did.
    expect(emissions, hasLength(1));
    await sub.cancel();
  });

  test(
    'updateProgram sends only the program and note (partial update)',
    () async {
      when(
        () => dio.put<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _okMap('$_schedulePath/s1'));

      await repo.updateProgram(
        's1',
        program: const <ProgramItem>[
          ProgramItem(name: '스쿼트', sets: 3, reps: 12, weight: 60),
        ],
        note: '무릎 주의',
      );

      final body =
          verify(
                () => dio.put<Map<String, dynamic>>(
                  any(),
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      // Omitting the booking fields is what leaves time/client/duration
      // untouched — sending them would silently rewrite the booking.
      expect(body.keys.toSet(), <String>{'program', 'note'});
      expect((body['program'] as List<dynamic>).single, <String, Object?>{
        'name': '스쿼트',
        'type': '근력',
        'date': null,
        // 근력은 세트·횟수·중량으로만 잰다 — 시간은 싣지 않는다
        // (#1276, #1310).
        'duration': null,
        'duration_seconds': null,
        'sets': 3,
        'reps': 12,
        // 회로 재는 운동이라 홀드 초는 비어 있다(#1969).
        'hold_seconds': null,
        'weight': 60.0,
        'intensity': 'moderate',
        // 세션 구분은 항상 실린다 — 단일 세션 프로그램은 빈 문자열(#709).
        'session': '',
      });
    },
  );

  test(
    'registerProgramSchedule sends assignment and schedule as one command',
    () async {
      const path = '/trainer/clients/m1/program-schedule';
      when(
        () => dio.post<Map<String, dynamic>>(path, data: any(named: 'data')),
      ).thenAnswer(
        (_) async =>
            _okMap(path, <String, dynamic>{'attached_to_existing': false}),
      );

      final attached = await repo.registerProgramSchedule(
        date: '2026-08-06',
        clientId: 'm1',
        clientName: '김민수',
        time: '16:00',
        durationMinutes: 75,
        assignment: const <String, Object?>{
          'name': '하체',
          'sessions': <Object?>[],
          'client_request_id': 'req-a',
        },
        program: const <ProgramItem>[ProgramItem(name: '스쿼트', sets: 1)],
      );

      expect(attached, isFalse);
      final body =
          verify(
                () => dio.post<Map<String, dynamic>>(
                  path,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      // 일정 항목은 서버가 세션에서 펼친다 — 두 벌로 싣지 않는다.
      expect(body, <String, Object?>{
        'name': '하체',
        'sessions': <Object?>[],
        'client_request_id': 'req-a',
        'date': '2026-08-06',
        'time': '16:00',
        'duration_minutes': 75,
        'client_name': '김민수',
      });
    },
  );

  test(
    'registerProgramSchedule carries the trainer feedback as note',
    () async {
      // 편집기 하단의 트레이너 피드백(#2374) — 앞뒤 공백은 떼고 싣는다.
      const path = '/trainer/clients/m1/program-schedule';
      when(
        () => dio.post<Map<String, dynamic>>(path, data: any(named: 'data')),
      ).thenAnswer(
        (_) async =>
            _okMap(path, <String, dynamic>{'attached_to_existing': true}),
      );

      await repo.registerProgramSchedule(
        date: '2026-08-06',
        clientId: 'm1',
        clientName: '김민수',
        time: '16:00',
        durationMinutes: 75,
        assignment: const <String, Object?>{'name': '하체'},
        program: const <ProgramItem>[ProgramItem(name: '스쿼트', sets: 1)],
        note: '  하체 위주로 짰어요 ',
      );

      final body =
          verify(
                () => dio.post<Map<String, dynamic>>(
                  path,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(body['note'], '하체 위주로 짰어요');
    },
  );

  test('booked dates come from their own endpoint', () async {
    when(
      () => dio.get<List<dynamic>>('$_schedulePath/booked-dates'),
    ).thenAnswer(
      (_) async => _okList(<dynamic>[
        '2026-08-03',
        '2026-08-06',
      ], '$_schedulePath/booked-dates'),
    );

    expect(await repo.watchBookedDates().first, <String>{
      '2026-08-03',
      '2026-08-06',
    });
  });

  test('an HTTP failure surfaces as a typed AppError', () async {
    when(
      () => dio.get<List<dynamic>>(
        _schedulePath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenThrow(_httpError(403, _schedulePath));

    expect(
      () => repo.watchDate('2026-08-06').first,
      throwsA(isA<ForbiddenError>()),
    );
  });

  test('JSON numbers that decode as double survive (web)', () async {
    stubGet(<dynamic>[
      <String, dynamic>{
        'id': 's1',
        'date': '2026-08-06',
        'time': '10:00',
        'client_name': '김민수',
        'type': '1:1 PT',
        'duration_minutes': 60.0,
        'status': '예정',
        'note': '',
        'program': <dynamic>[
          <String, dynamic>{'name': '스쿼트', 'sets': 3.0, 'weight': '60kg'},
        ],
      },
    ]);

    final slot = (await repo.watchDate('2026-08-06').first).single;
    expect(slot.durationMinutes, 60);
    expect(slot.program.single.sets, 3);
  });

  test('a malformed row does not blank the whole timeline', () async {
    stubGet(<dynamic>[
      <String, dynamic>{'id': 's1'}, // every other field missing
      _session(id: 's2'),
    ]);

    final slots = await repo.watchDate('2026-08-06').first;
    expect(slots, hasLength(2));
    expect(slots.first.clientName, isEmpty);
    expect(slots.last.id, 's2');
  });

  // 서버는 보낸 개인운동을 배열로 돌려준다. 받는 형을 `Map` 으로 적어 두면
  // 200 을 받고도 형이 어긋나 던지고, 부른 쪽은 전송이 실패한 줄 안다 —
  // 실제로는 갔는데 화면만 그대로 남는다. (#2225)
  test('개인운동 전송은 배열 응답을 받고도 던지지 않는다', () async {
    const String path = '/trainer/schedule/s1/routines/send';
    when(
      () => dio.post<List<dynamic>>(path, data: any(named: 'data')),
    ).thenAnswer((_) async => _okList(<dynamic>[], path));

    await expectLater(repo.sendScheduledRoutines('s1'), completes);
  });

  group('이미 있는 PT 에 개인운동 붙이기 (#2747)', () {
    const String path = '/trainer/schedule/s1/routines';

    Future<Map<String, Object?>> put(List<RoutineExercise> items) async {
      when(
        () => dio.put<List<dynamic>>(path, data: any(named: 'data')),
      ).thenAnswer((_) async => _okList(<dynamic>[], path));

      await repo.updateScheduledRoutines('s1', items);

      return verify(
            () => dio.put<List<dynamic>>(path, data: captureAny(named: 'data')),
          ).captured.single
          as Map<String, Object?>;
    }

    test('개인운동을 채운 AI 제안 id 를 함께 싣는다', () async {
      final body = await put(const <RoutineExercise>[
        RoutineExercise(
          name: '걷기',
          minutes: 30,
          type: '유산소',
          source: 'ai',
          suggestionId: 'sug-walk',
        ),
        RoutineExercise(name: '계단 오르기', minutes: 15, type: '유산소'),
      ]);

      expect(body['suggestion_ids'], <String>['sug-walk']);
      expect(body['personal_routines'], hasLength(2));
    });

    test('일정 상세에서 고친 줄처럼 제안이 없으면 옛 본문 그대로다', () async {
      final body = await put(const <RoutineExercise>[
        RoutineExercise(name: '걷기', minutes: 30, type: '유산소'),
      ]);

      expect(body.containsKey('suggestion_ids'), isFalse);
      expect(body['personal_routines'], hasLength(1));
    });
  });
}

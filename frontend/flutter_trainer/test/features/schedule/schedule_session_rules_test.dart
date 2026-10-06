/// 트레이너 일정 세션 규칙 — 마무리된 세션의 메모(#2754), 회원 예약 일정의
/// 잠금(#2756), 완료 되돌리기의 겹침 검사 순서(#2757), 시작 시각 기준의
/// 완료·노쇼(#2760). 판정 함수와 응답 읽기, 실서버 요청 본문, 데모 저장소의
/// 같은 규칙까지 층별로 본다.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/dio_schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

import '../../helpers/fixed_clock.dart';

class _MockDio extends Mock implements Dio {}

/// 판정 기준 시각 — 2026-10-01(목) 13:00 KST.
final DateTime _now = DateTime(2026, 10, 1, 13);
const String _today = '2026-10-01';

Map<String, dynamic> _json({
  String id = 'sched-1',
  String date = _today,
  String time = '20:00',
  String status = '예정',
  Object? isReservation,
}) => <String, dynamic>{
  'id': id,
  'date': date,
  'time': time,
  'member_id': 'm1',
  'client_name': '김민수',
  'type': '1:1 PT',
  'duration_minutes': 50,
  'status': status,
  'note': '',
  'program': const <dynamic>[],
  'is_reservation': ?isReservation,
};

Response<Map<String, dynamic>> _ok(String path) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const <String, dynamic>{},
    );

DioException _error(String path, int status, Object? body) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
    data: body,
  ),
);

void main() {
  group('sessionHasStarted (#2760)', () {
    ScheduleSession at(String date, String time) =>
        scheduleSessionFromJson(_json(date: date, time: time));

    test('오늘이라도 시작 시각 전이면 시작하지 않았다', () {
      expect(sessionHasStarted(at(_today, '20:00'), _now), isFalse);
      expect(sessionHasStarted(at(_today, '13:01'), _now), isFalse);
    });

    test('시작 시각 정각부터 시작한 것이다', () {
      expect(sessionHasStarted(at(_today, '13:00'), _now), isTrue);
      expect(sessionHasStarted(at(_today, '09:30'), _now), isTrue);
    });

    test('지난 날은 시각과 상관없이 시작했고, 앞날은 시작하지 않았다', () {
      expect(sessionHasStarted(at('2026-09-30', '23:30'), _now), isTrue);
      expect(sessionHasStarted(at('2026-10-02', '00:00'), _now), isFalse);
    });

    test('시각 형식이 깨졌으면 날짜만으로 판정한다', () {
      expect(hasStartedAt(_today, '', _now), isTrue);
      expect(hasStartedAt(_today, '저녁', _now), isTrue);
      expect(hasStartedAt('2026-10-02', '', _now), isFalse);
    });
  });

  // 다가오는 세션의 기준 — 대시보드 배너(#2865)와 같은 끝나는 시각(#3261).
  group('sessionHasEnded (#3261)', () {
    // 길이는 [_json] 의 50분이다.
    ScheduleSession at(String date, String time) =>
        scheduleSessionFromJson(_json(date: date, time: time));

    test('시작했어도 끝나는 시각 전이면 끝나지 않았다', () {
      expect(sessionHasEnded(at(_today, '12:30'), _now), isFalse);
      expect(sessionHasEnded(at(_today, '20:00'), _now), isFalse);
    });

    test('끝나는 시각 정각부터 끝난 것이다', () {
      expect(sessionHasEnded(at(_today, '12:10'), _now), isTrue);
      expect(sessionHasEnded(at(_today, '09:00'), _now), isTrue);
    });

    test('지난 날은 끝났고, 앞날은 끝나지 않았다', () {
      expect(sessionHasEnded(at('2026-09-30', '23:30'), _now), isTrue);
      expect(sessionHasEnded(at('2026-10-02', '00:00'), _now), isFalse);
    });

    test('시각 형식이 깨진 오늘 세션은 끝난 것으로 본다', () {
      expect(sessionHasEnded(at(_today, '저녁'), _now), isTrue);
      expect(sessionHasEnded(at('2026-10-02', ''), _now), isFalse);
    });
  });

  group('is_reservation 읽기 (#2756)', () {
    test('예약 일정 표시를 읽는다', () {
      expect(
        scheduleSessionFromJson(_json(isReservation: true)).isReservation,
        isTrue,
      );
      expect(
        scheduleSessionFromJson(_json(isReservation: false)).isReservation,
        isFalse,
      );
    });

    test('칸이 없는 옛 응답은 일반 일정이다', () {
      expect(scheduleSessionFromJson(_json()).isReservation, isFalse);
    });
  });

  group('DioScheduleRepository 요청 본문', () {
    late _MockDio dio;
    late DioScheduleRepository repo;

    setUpAll(() => registerFallbackValue(<String, dynamic>{}));

    setUp(() {
      dio = _MockDio();
      repo = DioScheduleRepository(dio);
      addTearDown(repo.dispose);
    });

    Map<String, Object?> capturedPut(String path) =>
        verify(
              () => dio.put<Map<String, dynamic>>(
                path,
                data: captureAny(named: 'data'),
              ),
            ).captured.single
            as Map<String, Object?>;

    test('메모만 고치면 메모만 보낸다 (#2754)', () async {
      const path = '/trainer/schedule/sched-1';
      when(
        () => dio.put<Map<String, dynamic>>(path, data: any(named: 'data')),
      ).thenAnswer((_) async => _ok(path));

      await repo.updateSession('sched-1', note: '스쿼트 깊이 좋아짐');

      expect(capturedPut(path), <String, Object?>{'note': '스쿼트 깊이 좋아짐'});
    });

    test('넘긴 칸은 모두 보내고 넘기지 않은 칸은 빼 둔다', () async {
      const path = '/trainer/schedule/sched-1';
      when(
        () => dio.put<Map<String, dynamic>>(path, data: any(named: 'data')),
      ).thenAnswer((_) async => _ok(path));

      await repo.updateSession('sched-1', time: '18:30', durationMinutes: 60);

      expect(capturedPut(path), <String, Object?>{
        'time': '18:30',
        'duration_minutes': 60,
      });
    });

    test('마무리된 세션 거절(409)은 서버 사유를 담은 ServerError 다', () async {
      const path = '/trainer/schedule/sched-1';
      const reason = '완료·취소·노쇼로 마무리된 PT는 피드백·프로그램만 수정할 수 있어요.';
      when(
        () => dio.put<Map<String, dynamic>>(path, data: any(named: 'data')),
      ).thenThrow(_error(path, 409, <String, dynamic>{'detail': reason}));

      await expectLater(
        repo.updateSession('sched-1', time: '18:30'),
        throwsA(
          isA<ServerError>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', reason),
        ),
      );
    });

    test('예약 일정 삭제 거절(409)도 사유를 잃지 않는다 (#2756)', () async {
      const path = '/trainer/schedule/sched-1';
      const reason = '예약으로 생성된 일정은 일반 일정 화면에서 삭제할 수 없어요.';
      when(
        () => dio.delete<Map<String, dynamic>>(path),
      ).thenThrow(_error(path, 409, <String, dynamic>{'detail': reason}));

      await expectLater(
        repo.deleteSession('sched-1'),
        throwsA(isA<ServerError>().having((e) => e.message, 'message', reason)),
      );
    });

    test('되돌리기는 옮길 시각·길이를 같은 요청에 싣는다 (#2757)', () async {
      const path = '/trainer/schedule/sched-1/reopen';
      when(
        () => dio.post<Map<String, dynamic>>(path, data: any(named: 'data')),
      ).thenAnswer((_) async => _ok(path));

      await repo.reopenSession(
        'sched-1',
        date: '2026-10-08',
        time: '07:00',
        durationMinutes: 40,
      );

      final body =
          verify(
                () => dio.post<Map<String, dynamic>>(
                  path,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(body, <String, Object?>{
        'date': '2026-10-08',
        'time': '07:00',
        'duration_minutes': 40,
      });
    });

    test('시각을 바꾸지 않은 되돌리기는 날짜만 보낸다', () async {
      const path = '/trainer/schedule/sched-1/reopen';
      when(
        () => dio.post<Map<String, dynamic>>(path, data: any(named: 'data')),
      ).thenAnswer((_) async => _ok(path));

      await repo.reopenSession('sched-1', date: '2026-10-08');

      final body =
          verify(
                () => dio.post<Map<String, dynamic>>(
                  path,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(body, <String, Object?>{'date': '2026-10-08'});
    });

    test('되돌릴 자리가 겹치면 ScheduleOverlapError 다', () async {
      const path = '/trainer/schedule/sched-1/reopen';
      when(
        () => dio.post<Map<String, dynamic>>(path, data: any(named: 'data')),
      ).thenThrow(
        _error(path, 409, <String, dynamic>{
          'detail': <String, dynamic>{
            'code': scheduleOverlapCode,
            'message': '같은 시간에 이미 다른 일정이 있어요.',
            'conflicts': <dynamic>[_json(id: 'other', date: '2026-10-08')],
          },
        }),
      );

      await expectLater(
        repo.reopenSession('sched-1', date: '2026-10-08', time: '20:00'),
        throwsA(isA<ScheduleOverlapError>()),
      );
    });
  });

  group('DriftScheduleRepository 세션 규칙', () {
    late AppDatabase db;
    late DriftScheduleRepository repo;

    setUp(() {
      useFixedKstDate(_now);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftScheduleRepository(db);
    });
    tearDown(() => db.close());

    Future<void> insert({
      String id = 'sched-1',
      String date = _today,
      String time = '10:00',
      int duration = 50,
      String status = ScheduleStatus.upcoming,
      String note = '',
      String programJson = '[]',
      bool programSent = false,
    }) => db
        .into(db.trainerScheduleEntries)
        .insert(
          TrainerScheduleEntriesCompanion.insert(
            id: id,
            date: date,
            time: time,
            status: status,
            clientName: const Value('김민수'),
            type: const Value('1:1 PT'),
            durationMinutes: Value(duration),
            note: Value(note),
            programJson: Value(programJson),
            programSent: Value(programSent),
          ),
        );

    Future<TrainerScheduleRow> row(String id) => (db.select(
      db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).getSingle();

    group('마무리된 세션 (#2754)', () {
      for (final status in <String>[
        ScheduleStatus.done,
        ScheduleStatus.cancelled,
        ScheduleStatus.noShow,
      ]) {
        test('$status 세션도 메모는 고친다', () async {
          await insert(status: status);

          await repo.updateSession('sched-1', note: '다음엔 스트레칭 먼저');

          final stored = await row('sched-1');
          expect(stored.note, '다음엔 스트레칭 먼저');
          expect(stored.status, status);
        });

        test('$status 세션의 시각은 바꾸지 못하고 그대로 둔다', () async {
          await insert(status: status);

          await expectLater(
            repo.updateSession('sched-1', time: '11:00', note: '옮김'),
            throwsA(
              isA<ServerError>()
                  .having((e) => e.statusCode, 'statusCode', 409)
                  .having(
                    (e) => e.message,
                    'message',
                    demoFinishedEditRejected,
                  ),
            ),
          );
          final stored = await row('sched-1');
          expect(stored.time, '10:00');
          expect(stored.note, isEmpty);
        });
      }

      test('지금 값과 같은 칸은 바꾸는 것이 아니다', () async {
        await insert(status: ScheduleStatus.done);

        await repo.updateSession(
          'sched-1',
          time: '10:00',
          durationMinutes: 50,
          note: '같은 시각',
        );

        expect((await row('sched-1')).note, '같은 시각');
      });

      test('아직 보내지 않은 프로그램은 완료 뒤에도 고친다', () async {
        await insert(status: ScheduleStatus.done);

        await repo.updateProgram(
          'sched-1',
          program: const <ProgramItem>[
            ProgramItem(name: '스쿼트', sets: 3, reps: 10),
          ],
          note: '기록 남김',
        );

        final stored = await row('sched-1');
        expect(stored.programJson, contains('스쿼트'));
        expect(stored.note, '기록 남김');
      });

      test('이미 보낸 프로그램은 바꾸지 못하지만 메모는 고친다', () async {
        await insert(status: ScheduleStatus.done);
        const sent = <ProgramItem>[ProgramItem(name: '런지', sets: 3, reps: 12)];
        await repo.updateProgram('sched-1', program: sent, note: '');
        await (db.update(
          db.trainerScheduleEntries,
        )..where((t) => t.id.equals('sched-1'))).write(
          const TrainerScheduleEntriesCompanion(programSent: Value(true)),
        );

        await expectLater(
          repo.updateProgram(
            'sched-1',
            program: const <ProgramItem>[
              ProgramItem(name: '데드리프트', sets: 3, reps: 5),
            ],
            note: '',
          ),
          throwsA(
            isA<ServerError>().having(
              (e) => e.message,
              'message',
              demoSentProgramEditRejected,
            ),
          ),
        );
        expect((await row('sched-1')).programJson, contains('런지'));

        await repo.updateProgram('sched-1', program: sent, note: '무릎 정렬 좋음');
        expect((await row('sched-1')).note, '무릎 정렬 좋음');
      });
    });

    group('회원 예약 일정 (#2756)', () {
      const String resvId = '${demoReservationScheduleIdPrefix}1';

      test('예약 일정 id 를 알아본다', () {
        expect(isDemoReservationScheduleId(resvId), isTrue);
        expect(isDemoReservationScheduleId('seed-resv-2'), isTrue);
        expect(isDemoReservationScheduleId('sched-1'), isFalse);
        expect(isDemoReservationScheduleId('seed-schedule-1'), isFalse);
      });

      test('읽으면 예약 일정으로 표시된다', () async {
        await insert(id: resvId);
        await insert(id: 'sched-2', time: '15:00');

        final sessions = await repo.watchDate(_today).first;
        expect(
          sessions.firstWhere((s) => s.id == resvId).isReservation,
          isTrue,
        );
        expect(
          sessions.firstWhere((s) => s.id == 'sched-2').isReservation,
          isFalse,
        );
      });

      test('시각을 바꾸지 못하고 서버와 같은 사유로 거절한다', () async {
        await insert(id: resvId);

        await expectLater(
          repo.updateSession(resvId, time: '11:00'),
          throwsA(
            isA<ServerError>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.message,
                  'message',
                  demoReservationEditRejected,
                ),
          ),
        );
        expect((await row(resvId)).time, '10:00');
      });

      test('메모는 고친다', () async {
        await insert(id: resvId);

        await repo.updateSession(resvId, note: '첫 방문');

        expect((await row(resvId)).note, '첫 방문');
      });

      test('지우지 못하고 행이 남는다', () async {
        await insert(id: resvId);

        await expectLater(
          repo.deleteSession(resvId),
          throwsA(
            isA<ServerError>().having(
              (e) => e.message,
              'message',
              demoReservationDeleteRejected,
            ),
          ),
        );
        expect(await row(resvId), isNotNull);
      });

      test('취소는 그대로 된다 — 약속을 거두는 길이다', () async {
        await insert(id: resvId, time: '20:00');

        await repo.cancelSession(resvId, source: 'member');

        expect((await row(resvId)).status, ScheduleStatus.cancelled);
      });
    });

    group('완료 되돌리기 (#2757)', () {
      const String future = '2026-10-08';

      test('옮길 자리가 겹치면 아무것도 바꾸지 않는다', () async {
        await insert(status: ScheduleStatus.done);
        await insert(id: 'other', date: future, time: '07:00', duration: 60);

        await expectLater(
          repo.reopenSession('sched-1', date: future, time: '07:30'),
          throwsA(isA<ScheduleOverlapError>()),
        );

        final stored = await row('sched-1');
        expect(stored.status, ScheduleStatus.done);
        expect(stored.date, _today);
        expect(stored.time, '10:00');
      });

      test('시각을 넘기지 않으면 지금 시각 자리로 겹침을 본다', () async {
        await insert(status: ScheduleStatus.done);
        await insert(id: 'other', date: future, time: '10:20');

        await expectLater(
          repo.reopenSession('sched-1', date: future),
          throwsA(isA<ScheduleOverlapError>()),
        );
        expect((await row('sched-1')).status, ScheduleStatus.done);
      });

      test('빈 자리면 날짜·시각·길이를 함께 옮기고 예정으로 되돌린다', () async {
        await insert(status: ScheduleStatus.done);
        await insert(id: 'other', date: future, time: '07:00', duration: 60);

        await repo.reopenSession(
          'sched-1',
          date: future,
          time: '18:00',
          durationMinutes: 40,
        );

        final stored = await row('sched-1');
        expect(stored.status, ScheduleStatus.upcoming);
        expect(stored.date, future);
        expect(stored.time, '18:00');
        expect(stored.durationMinutes, 40);
      });

      test('회원 예약 일정은 되돌리지 않는다', () async {
        const String resvId = '${demoReservationScheduleIdPrefix}9';
        await insert(id: resvId, status: ScheduleStatus.done);

        await expectLater(
          repo.reopenSession(resvId, date: future),
          throwsA(isA<ServerError>()),
        );
        expect((await row(resvId)).status, ScheduleStatus.done);
      });
    });

    group('시작 시각 기준 완료·노쇼 (#2760)', () {
      test('오늘이라도 시작 전 PT 는 완료되지 않고 기록도 남지 않는다', () async {
        await insert(time: '20:00');

        await repo.completeSession('sched-1', note: '미리 완료');

        expect((await row('sched-1')).status, ScheduleStatus.upcoming);
        final history = await db.select(db.clientRoutineHistory).get();
        expect(history, isEmpty);
      });

      test('시작 시각이 지나면 완료된다', () async {
        await insert(time: '12:30');

        await repo.completeSession('sched-1');

        expect((await row('sched-1')).status, ScheduleStatus.done);
      });

      test('시작 시각 정각에 완료된다', () async {
        await insert(time: '13:00');

        await repo.completeSession('sched-1');

        expect((await row('sched-1')).status, ScheduleStatus.done);
      });

      test('시작 전 PT 는 노쇼로 적히지 않는다', () async {
        await insert(time: '20:00');

        await repo.markNoShow('sched-1');

        final stored = await row('sched-1');
        expect(stored.status, ScheduleStatus.upcoming);
        expect(stored.noShowAt, isNull);
      });

      test('시작 시각이 지나면 노쇼로 적힌다', () async {
        await insert(time: '09:00');

        await repo.markNoShow('sched-1');

        expect((await row('sched-1')).status, ScheduleStatus.noShow);
      });

      test('취소는 시작 전에도 된다', () async {
        await insert(time: '20:00');

        await repo.cancelSession('sched-1', source: 'trainer');

        expect((await row('sched-1')).status, ScheduleStatus.cancelled);
      });
    });
  });
}

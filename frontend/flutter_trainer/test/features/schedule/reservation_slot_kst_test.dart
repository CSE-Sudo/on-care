/// 예약 자리 시각을 브라우저 시간대가 아니라 KST 로 읽고 쓰는지 (#2759),
/// 일정과 겹친 자리를 빈 자리로 세지 않는지 (#2761), 데모 상담이 잡은 자리에
/// 회원 이름이 실리는지 (#2758).
///
/// 이 앱은 `nowKst()` 처럼 **필드가 KST 벽시계인 로컬 DateTime** 을 쓴다. 테스트
/// 기기 시간대가 무엇이든 같은 결과가 나와야 하므로, 기대값은 전부 필드로 적는다.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/consultations/data/dtos/consultation_dtos.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

import '../../helpers/fixed_clock.dart';

class _MockDio extends Mock implements Dio {}

Map<String, dynamic> _slotJson({
  String startsAt = '2031-04-13T22:00:00Z',
  int remaining = 1,
  bool isClosed = false,
  Object? overlapped,
}) => <String, dynamic>{
  'id': 'slot-1',
  'trainer_id': 'trainer-1',
  'starts_at': startsAt,
  'duration_minutes': 60,
  'capacity': 1,
  'remaining': remaining,
  'is_closed': isClosed,
  'session_type': '1:1 PT',
  'overlapped': ?overlapped,
};

/// 2031-04-14(월) 07:00 KST 에 여는 한 시간짜리 자리.
ReservationSlot _openSlot({
  int hour = 7,
  int minute = 0,
  int durationMinutes = 60,
  bool booked = false,
  bool isClosed = false,
}) => ReservationSlot(
  id: 'slot-1',
  startsAt: DateTime(2031, 4, 14, hour, minute),
  durationMinutes: durationMinutes,
  booked: booked,
  isClosed: isClosed,
  sessionType: SessionType.consultation,
);

DemoSlotSession _session({
  String date = '2031-04-14',
  String time = '07:00',
  int durationMinutes = 60,
  String type = SessionType.personalTraining,
  String clientName = '박성호',
}) => (
  date: date,
  time: time,
  durationMinutes: durationMinutes,
  type: type,
  clientName: clientName,
);

void main() {
  group('KST 벽시계 변환 (#2759)', () {
    test('kstWallToUtc 는 KST 벽시계를 9시간 앞선 UTC 순간으로 바꾼다', () {
      final DateTime utc = kstWallToUtc(DateTime(2031, 4, 14, 7));

      expect(utc.isUtc, isTrue);
      expect(utc, DateTime.utc(2031, 4, 13, 22));
    });

    test('자정 직후 KST 는 UTC 전날로 넘어간다', () {
      expect(
        kstWallToUtc(DateTime(2031, 4, 15, 0, 30)),
        DateTime.utc(2031, 4, 14, 15, 30),
      );
    });

    test('이미 UTC 순간인 값은 그대로 둔다', () {
      final DateTime instant = DateTime.utc(2031, 4, 13, 22);

      expect(kstWallToUtc(instant), instant);
    });

    test('toKst 는 UTC 순간을 KST 벽시계 필드로 읽는다', () {
      final DateTime wall = toKst(DateTime.utc(2031, 4, 13, 22));

      expect(wall.isUtc, isFalse);
      expect(
        (wall.year, wall.month, wall.day, wall.hour, wall.minute),
        (2031, 4, 14, 7, 0),
      );
    });

    test('오프셋이 붙은 문자열도 같은 KST 벽시계가 된다', () {
      final DateTime wall = toKst(DateTime.parse('2031-04-14T07:00:00+09:00'));

      expect((wall.day, wall.hour), (14, 7));
    });

    test('두 변환은 서로 되돌린다', () {
      final DateTime wall = DateTime(2031, 12, 31, 23, 45);

      expect(toKst(kstWallToUtc(wall)), wall);
    });
  });

  group('ReservationSlot.fromJson', () {
    test('서버 UTC 시각을 KST 벽시계로 읽는다 (#2759)', () {
      final slot = ReservationSlot.fromJson(_slotJson());

      expect(slot.startsAt, DateTime(2031, 4, 14, 7));
    });

    test('overlapped 가 오면 열린 자리가 아니다 (#2761)', () {
      final slot = ReservationSlot.fromJson(_slotJson(overlapped: true));

      expect(slot.overlapped, isTrue);
      expect(slot.booked, isFalse);
      expect(slot.open, isFalse);
    });

    test('overlapped 가 없으면 겹치지 않은 빈 자리다', () {
      final slot = ReservationSlot.fromJson(_slotJson());

      expect(slot.overlapped, isFalse);
      expect(slot.open, isTrue);
    });

    test('예약됐거나 닫힌 자리는 열린 자리가 아니다', () {
      expect(ReservationSlot.fromJson(_slotJson(remaining: 0)).open, isFalse);
      expect(ReservationSlot.fromJson(_slotJson(isClosed: true)).open, isFalse);
    });
  });

  group('DioReservationSlotRepository 쓰기 (#2759)', () {
    late _MockDio dio;
    late DioReservationSlotRepository repository;

    setUpAll(() => registerFallbackValue(<String, dynamic>{}));

    setUp(() {
      dio = _MockDio();
      repository = DioReservationSlotRepository(dio);
    });

    test('create 는 폼에서 고른 KST 벽시계를 UTC 로 보낸다', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/trainer/reservation-slots',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/trainer/reservation-slots'),
          statusCode: 201,
          data: _slotJson(),
        ),
      );

      final created = await repository.create(
        startsAt: DateTime(2031, 4, 14, 7),
        sessionType: '1:1 PT',
      );

      final data =
          verify(
                () => dio.post<Map<String, dynamic>>(
                  '/trainer/reservation-slots',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      // 기기 시간대를 거치면 KST 가 아닌 브라우저에서 다른 순간이 저장됐다.
      expect(data['starts_at'], '2031-04-13T22:00:00.000Z');
      // 응답도 같은 벽시계로 돌아온다.
      expect(created.startsAt, DateTime(2031, 4, 14, 7));
    });

    test('update 도 KST 벽시계를 UTC 로 보낸다', () async {
      when(
        () => dio.put<Map<String, dynamic>>(
          '/trainer/reservation-slots/slot-1',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(
            path: '/trainer/reservation-slots/slot-1',
          ),
          statusCode: 200,
          data: _slotJson(startsAt: '2031-04-14T15:30:00Z'),
        ),
      );

      await repository.update('slot-1', startsAt: DateTime(2031, 4, 15, 0, 30));

      final data =
          verify(
                () => dio.put<Map<String, dynamic>>(
                  '/trainer/reservation-slots/slot-1',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(data['starts_at'], '2031-04-14T15:30:00.000Z');
    });
  });

  group('상담 신청의 slot_starts_at (#2759)', () {
    Map<String, Object?> consultJson(Object? slotStartsAt) => <String, Object?>{
      'id': 'consult-1',
      'member_id': 'user-1',
      'member_name': '이서윤',
      'exercise_goal': 'weight_loss',
      'health_purpose_type': 'chronic',
      'preferred_date': '2031-04-14',
      'preferred_time_slot': 'morning',
      'status': 'accepted',
      'slot_starts_at': slotStartsAt,
      'slot_duration_minutes': 30,
    };

    test('UTC 시각을 슬롯 창과 같은 KST 벽시계로 읽는다', () {
      final request = consultationRequestFromJson(
        consultJson('2031-04-13T22:00:00Z'),
      );

      expect(request.slotStartsAt, DateTime(2031, 4, 14, 7));
    });

    test('시각이 없으면 비워 둔다', () {
      expect(
        consultationRequestFromJson(consultJson(null)).slotStartsAt,
        isNull,
      );
    });
  });

  group('judgeDemoSlot', () {
    test('겹치는 일정이 없으면 자리를 그대로 둔다', () {
      final slot = _openSlot();

      expect(
        identical(
          judgeDemoSlot(slot, <DemoSlotSession>[_session(time: '09:00')]),
          slot,
        ),
        isTrue,
      );
    });

    test('시간이 겹치는 PT 일정이 있으면 겹친 자리다 (#2761)', () {
      final judged = judgeDemoSlot(_openSlot(), <DemoSlotSession>[
        _session(time: '07:30'),
      ]);

      expect(judged.overlapped, isTrue);
      expect(judged.booked, isFalse);
      expect(judged.open, isFalse);
    });

    test('끝과 시작이 맞닿기만 하면 겹치지 않는다', () {
      final judged = judgeDemoSlot(_openSlot(), <DemoSlotSession>[
        _session(time: '06:00'),
        _session(time: '08:00'),
      ]);

      expect(judged.open, isTrue);
    });

    test('다른 날 일정은 보지 않는다', () {
      final judged = judgeDemoSlot(_openSlot(), <DemoSlotSession>[
        _session(date: '2031-04-15'),
      ]);

      expect(judged.open, isTrue);
    });

    test('같은 시각에 시작하는 상담 일정은 그 회원이 잡은 자리다 (#2758)', () {
      final judged = judgeDemoSlot(_openSlot(), <DemoSlotSession>[
        _session(type: SessionType.consultation, clientName: '이서윤'),
      ]);

      expect(judged.booked, isTrue);
      expect(judged.bookedByName, '이서윤');
      expect(judged.overlapped, isFalse);
    });

    test('시작 시각이 다른 상담 일정은 겹친 일정으로 본다', () {
      final judged = judgeDemoSlot(_openSlot(), <DemoSlotSession>[
        _session(type: SessionType.consultation, time: '07:30'),
      ]);

      expect(judged.booked, isFalse);
      expect(judged.overlapped, isTrue);
    });

    test('닫혔거나 이미 예약된 자리는 그대로 둔다', () {
      final closed = _openSlot(isClosed: true);
      final booked = _openSlot(booked: true);
      final sessions = <DemoSlotSession>[_session()];

      expect(identical(judgeDemoSlot(closed, sessions), closed), isTrue);
      expect(identical(judgeDemoSlot(booked, sessions), booked), isTrue);
    });
  });

  group('MockReservationSlotRepository', () {
    late AppDatabase db;

    setUp(() async {
      useFixedKstDate(DateTime(2031, 4, 13, 9));
      db = AppDatabase.forTesting(NativeDatabase.memory());
      // 시드 일정이 판정에 섞이지 않도록 비우고 이 테스트의 일정만 둔다.
      await db.delete(db.trainerScheduleEntries).go();
    });

    tearDown(() => db.close());

    Future<void> addSession({
      required String id,
      String time = '07:00',
      String type = SessionType.personalTraining,
      String status = ScheduleStatus.upcoming,
      String clientName = '박성호',
    }) => db
        .into(db.trainerScheduleEntries)
        .insert(
          TrainerScheduleEntriesCompanion.insert(
            id: id,
            date: '2031-04-14',
            time: time,
            status: status,
            clientName: Value(clientName),
            type: Value(type),
            durationMinutes: const Value(60),
          ),
        );

    Future<MockReservationSlotRepository> repositoryWithSlot() async {
      final repository = MockReservationSlotRepository(db: db);
      await repository.create(
        startsAt: DateTime(2031, 4, 14, 7),
        sessionType: SessionType.consultation,
      );
      return repository;
    }

    test('같은 시간에 예정 일정이 있으면 겹친 자리로 읽는다 (#2761)', () async {
      final repository = await repositoryWithSlot();
      await addSession(id: 'pt-1', time: '07:30');

      final slot = (await repository.list()).single;
      expect(slot.overlapped, isTrue);
      expect(slot.open, isFalse);
    });

    test('겹친 일정을 취소하면 다음 조회에서 다시 빈 자리다 (#2761)', () async {
      final repository = await repositoryWithSlot();
      await addSession(id: 'pt-1');
      expect((await repository.list()).single.overlapped, isTrue);

      await (db.update(
        db.trainerScheduleEntries,
      )..where((t) => t.id.equals('pt-1'))).write(
        const TrainerScheduleEntriesCompanion(
          status: Value(ScheduleStatus.cancelled),
        ),
      );

      expect((await repository.list()).single.open, isTrue);
    });

    test('그 자리로 잡힌 상담 일정은 회원 이름이 실린 예약 자리다 (#2758)', () async {
      final repository = await repositoryWithSlot();
      await addSession(
        id: 'consult-1',
        type: SessionType.consultation,
        clientName: '이서윤',
      );

      final slot = (await repository.list()).single;
      expect(slot.booked, isTrue);
      expect(slot.bookedByName, '이서윤');
    });

    test('상담 일정을 다른 시간으로 옮기면 자리가 다시 빈다 (#2758)', () async {
      final repository = await repositoryWithSlot();
      await addSession(
        id: 'consult-1',
        type: SessionType.consultation,
        clientName: '이서윤',
      );
      expect((await repository.list()).single.booked, isTrue);

      await (db.update(db.trainerScheduleEntries)
            ..where((t) => t.id.equals('consult-1')))
          .write(const TrainerScheduleEntriesCompanion(time: Value('10:00')));

      final slot = (await repository.list()).single;
      expect(slot.booked, isFalse);
      expect(slot.open, isTrue);
    });

    test('일정 저장소가 없으면 자리를 판정 없이 그대로 돌려준다', () async {
      final repository = MockReservationSlotRepository();

      final created = await repository.create(
        startsAt: DateTime(2031, 4, 14, 7),
        sessionType: '1:1 PT',
      );

      final listed = await repository.list();
      expect(listed.single.id, created.id);
      expect(listed.single.startsAt, DateTime(2031, 4, 14, 7));
      expect(listed.single.open, isTrue);
    });
  });
}

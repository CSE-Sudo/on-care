/// 트레이너 데모에서 상담 일정을 취소·삭제·이동하면 상담함의 신청도 실서버와
/// 같은 규칙으로 바뀌는지 (#2758).
///
/// - 취소·삭제 → `cancelled` + 트레이너 철회 표시
/// - 이동 → 신청의 시각이 옮긴 일정을 따른다(예전 자리는 다시 빈다)
/// - 이미 치른(노쇼·완료) 상담을 지우면 신청은 수락된 채로 남는다
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

import '../../helpers/fixed_clock.dart';

/// 2031-04-14(월) 07:00 KST 상담 자리.
final DateTime _slotAt = DateTime(2031, 4, 14, 7);
final String _day = ymd(_slotAt);

ConsultationRequest _pending({String id = 'c-1', DateTime? slotStartsAt}) =>
    ConsultationRequest(
      id: id,
      memberId: 'member-$id',
      memberName: '이서윤',
      goalCode: 'fitness',
      purposeCode: 'general',
      preferredDate: _slotAt,
      preferredTimeCode: '07:00',
      slotStartsAt: slotStartsAt ?? _slotAt,
      slotDurationMinutes: 30,
      status: 'pending',
      createdAt: DateTime(2031, 4, 10, 9),
    );

void main() {
  late AppDatabase db;
  late DriftScheduleRepository schedule;
  late DemoConsultationRepository consultations;

  setUp(() {
    useFixedKstDate(DateTime(2031, 4, 13, 9));
    demoScheduleConsultations.clear();
    addTearDown(demoScheduleConsultations.clear);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    schedule = DriftScheduleRepository(db);
    consultations = DemoConsultationRepository(
      requests: <ConsultationRequest>[_pending()],
      scheduleRepository: () => schedule,
      db: db,
    );
  });

  /// 신청을 수락해 상담 일정을 잡고, 그 일정을 돌려준다.
  Future<ScheduleSession> acceptAndFindSession() async {
    await consultations.accept('c-1');
    final List<ScheduleSession> day = await schedule.watchDate(_day).first;
    return day.singleWhere((s) => s.type == SessionType.consultation);
  }

  Future<ConsultationRequest> current() async =>
      (await consultations.fetch(status: 'all')).single;

  test('수락한 신청은 일정이 그대로면 수락된 채다', () async {
    final ScheduleSession session = await acceptAndFindSession();

    expect(session.consultation?.id, 'c-1');
    final ConsultationRequest request = await current();
    expect(request.status, 'accepted');
    expect(request.cancelledByTrainer, isFalse);
    expect(request.slotStartsAt, _slotAt);
  });

  test('상담 일정을 취소하면 신청이 트레이너 철회가 된다', () async {
    final ScheduleSession session = await acceptAndFindSession();

    await schedule.cancelSession(session.id, source: 'trainer');

    final ConsultationRequest request = await current();
    expect(request.status, 'cancelled');
    expect(request.cancelledByTrainer, isTrue);
    // 대기 목록에도, 수락 목록에도 남지 않는다.
    expect(await consultations.fetch(status: 'accepted'), isEmpty);
    expect(await consultations.fetch(status: 'cancelled'), hasLength(1));
    expect(await consultations.pendingCount(), 0);
  });

  test('예정인 상담 일정을 지우면 신청이 트레이너 철회가 된다', () async {
    final ScheduleSession session = await acceptAndFindSession();

    await schedule.deleteSession(session.id);

    final ConsultationRequest request = await current();
    expect(request.status, 'cancelled');
    expect(request.cancelledByTrainer, isTrue);
  });

  test('취소한 상담 일정을 지워도 철회 상태가 그대로다', () async {
    final ScheduleSession session = await acceptAndFindSession();
    await schedule.cancelSession(session.id, source: 'trainer');

    await schedule.deleteSession(session.id);

    final ConsultationRequest request = await current();
    expect(request.status, 'cancelled');
    expect(request.cancelledByTrainer, isTrue);
  });

  test('이미 치른(노쇼) 상담 일정을 지우면 신청은 수락된 채다', () async {
    final ScheduleSession session = await acceptAndFindSession();
    // 노쇼는 시작 시각이 지나야 기록된다(#2760) — 상담이 끝난 뒤로 옮긴다.
    useFixedKstDate(DateTime(2031, 4, 14, 9));
    await schedule.markNoShow(session.id);

    await schedule.deleteSession(session.id);

    final ConsultationRequest request = await current();
    expect(request.status, 'accepted');
    expect(request.cancelledByTrainer, isFalse);
  });

  test('상담 일정을 옮기면 신청의 시각이 옮긴 일정을 따른다', () async {
    final ScheduleSession session = await acceptAndFindSession();

    await schedule.updateSession(
      session.id,
      date: '2031-04-15',
      clientName: session.clientName,
      clientId: session.clientId,
      time: '10:30',
      type: session.type,
      durationMinutes: session.durationMinutes,
      note: session.note,
    );

    final ConsultationRequest request = await current();
    expect(request.status, 'accepted');
    expect(request.slotStartsAt, DateTime(2031, 4, 15, 10, 30));
    // 옮긴 일정도 상담 요청 내용을 잃지 않는다.
    final List<ScheduleSession> moved = await schedule
        .watchDate('2031-04-15')
        .first;
    expect(moved.single.consultation?.id, 'c-1');
  });

  test('옮긴 상담 일정을 다시 취소해도 철회가 된다', () async {
    final ScheduleSession session = await acceptAndFindSession();
    await schedule.updateSession(
      session.id,
      date: _day,
      clientName: session.clientName,
      clientId: session.clientId,
      time: '09:00',
      type: session.type,
      durationMinutes: session.durationMinutes,
      note: session.note,
    );

    await schedule.cancelSession(session.id, source: 'trainer');

    final ConsultationRequest request = await current();
    expect(request.status, 'cancelled');
    expect(request.cancelledByTrainer, isTrue);
  });

  test('메모만 고치면 신청은 그대로다', () async {
    final ScheduleSession session = await acceptAndFindSession();

    await schedule.updateSession(
      session.id,
      clientName: session.clientName,
      clientId: session.clientId,
      time: session.time,
      type: session.type,
      durationMinutes: session.durationMinutes,
      note: '첫 상담 준비물 안내',
    );

    final ConsultationRequest request = await current();
    expect(request.status, 'accepted');
    expect(request.slotStartsAt, _slotAt);
  });

  test('상담을 옮기거나 취소하면 데모 상담 자리가 다시 빈다', () async {
    final slots = MockReservationSlotRepository(db: db);
    await slots.create(
      startsAt: _slotAt,
      sessionType: SessionType.consultation,
    );
    final ScheduleSession session = await acceptAndFindSession();
    final held = (await slots.list()).single;
    expect(held.booked, isTrue);
    expect(held.bookedByName, '이서윤');

    await schedule.cancelSession(session.id, source: 'trainer');

    expect((await slots.list()).single.open, isTrue);
  });

  group('judgeDemoConsultation', () {
    final ConsultationRequest accepted = _pending().copyWith(
      status: 'accepted',
    );

    test('연결된 일정이 없던 신청은 그대로 둔다', () {
      expect(
        identical(
          judgeDemoConsultation(accepted, linked: false, session: null),
          accepted,
        ),
        isTrue,
      );
    });

    test('수락되지 않은 신청은 일정과 견주지 않는다', () {
      final ConsultationRequest pending = _pending();

      expect(
        identical(
          judgeDemoConsultation(pending, linked: true, session: null),
          pending,
        ),
        isTrue,
      );
    });

    test('일정이 사라졌으면 트레이너 철회다', () {
      final ConsultationRequest judged = judgeDemoConsultation(
        accepted,
        linked: true,
        session: null,
      );

      expect(judged.status, 'cancelled');
      expect(judged.cancelledByTrainer, isTrue);
    });

    test('일정이 취소됐으면 트레이너 철회다', () {
      final ConsultationRequest judged = judgeDemoConsultation(
        accepted,
        linked: true,
        session: (date: _day, time: '07:00', status: ScheduleStatus.cancelled),
      );

      expect(judged.status, 'cancelled');
      expect(judged.cancelledByTrainer, isTrue);
    });

    test('완료된 일정은 수락된 채로 둔다', () {
      final ConsultationRequest judged = judgeDemoConsultation(
        accepted,
        linked: true,
        session: (date: _day, time: '07:00', status: ScheduleStatus.done),
      );

      expect(judged.status, 'accepted');
      expect(judged.slotStartsAt, _slotAt);
    });

    test('일정 시각이 다르면 그 시각으로 고친다', () {
      final ConsultationRequest judged = judgeDemoConsultation(
        accepted,
        linked: true,
        session: (
          date: '2031-04-16',
          time: '18:00',
          status: ScheduleStatus.upcoming,
        ),
      );

      expect(judged.status, 'accepted');
      expect(judged.slotStartsAt, DateTime(2031, 4, 16, 18));
      expect(judged.cancelledByTrainer, isFalse);
    });
  });
}

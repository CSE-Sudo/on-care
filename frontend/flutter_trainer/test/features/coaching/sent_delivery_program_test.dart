import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

ScheduleSession _session({
  required String status,
  required bool programSent,
  List<ProgramItem> program = const <ProgramItem>[ProgramItem(name: '덤벨컬')],
}) => ScheduleSession(
  id: 's1',
  date: '2026-09-28',
  time: '22:00',
  clientName: '이지수',
  type: '1:1 PT',
  durationMinutes: 50,
  status: status,
  note: '',
  program: program,
  programSent: programSent,
);

void main() {
  // 전송 이력은 **간 것**을 적는다. 일정에 프로그램이 짜여 있다는 사실과
  // 그것이 회원에게 갔다는 사실은 다르다 — 둘을 섞으면 스케줄 탭은 안 갔다고
  // 하고 전송 이력은 갔다고 하는 두 말이 선다. (#2225)
  test('PT 를 취소하면 짜 둔 프로그램은 전송 이력에 남지 않는다', () {
    const delivery = SentDelivery(kind: DeliveryKinds.cancelledRoutineOnly);
    final cancelled = SentDelivery(
      kind: delivery.kind,
      session: _session(status: ScheduleStatus.cancelled, programSent: false),
    );

    expect(cancelled.hasProgram, isFalse);
    expect(cancelled.program, isEmpty);
  });

  test('PT 와 함께 보낸 전송은 그 프로그램을 적는다', () {
    final sent = SentDelivery(
      kind: DeliveryKinds.ptWithRoutine,
      session: _session(status: ScheduleStatus.done, programSent: true),
    );

    expect(sent.hasProgram, isTrue);
    expect(sent.program.single.name, '덤벨컬');
  });

  test('프로그램 없이 개인운동만 보낸 전송은 붙일 프로그램이 없다', () {
    final routineOnly = SentDelivery(
      kind: DeliveryKinds.routineOnly,
      session: _session(
        status: ScheduleStatus.done,
        programSent: true,
        program: const <ProgramItem>[],
      ),
    );

    expect(routineOnly.hasProgram, isFalse);
    expect(routineOnly.program, isEmpty);
  });
}

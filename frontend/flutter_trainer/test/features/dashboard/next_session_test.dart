/// 대시보드 배너의 다음 수업 선정 규칙. (#2865)
///
/// 저장된 상태가 `예정` 이어도 끝난 시각이 지났으면 다음 수업이 아니다 — 완료
/// 처리를 잊은 것이다. 시작했지만 끝나지 않은 수업은 진행 중이다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/dashboard/domain/next_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

const String _today = '2026-08-20';

ScheduleSession _s(
  String id,
  String time, {
  String date = _today,
  int minutes = 50,
  String status = ScheduleStatus.upcoming,
  bool detached = false,
}) => ScheduleSession(
  id: id,
  date: date,
  time: time,
  clientName: '회원 $id',
  type: SessionType.personalTraining,
  durationMinutes: minutes,
  status: status,
  note: '',
  program: const <ProgramItem>[],
  memberDetached: detached,
);

DateTime _at(int hour, int minute) => DateTime(2026, 8, 20, hour, minute);

void main() {
  test('끝난 시각이 지난 예정 세션은 고르지 않는다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('morning', '10:00'),
      _s('evening', '17:00'),
    ], _at(15, 0));

    expect(next?.session.id, 'evening');
    expect(next?.phase, NextSessionPhase.upcoming);
    expect(next?.minutesLeft, 120);
  });

  test('시작했지만 끝나지 않은 세션은 진행 중이고 남은 분은 끝까지다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('now', '14:30'),
      _s('later', '17:00'),
    ], _at(15, 0));

    expect(next?.session.id, 'now');
    expect(next?.phase, NextSessionPhase.inProgress);
    expect(next?.minutesLeft, 20);
  });

  test('끝나는 분과 지금이 같으면 지난 수업이다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('ended', '14:10'),
    ], _at(15, 0));

    expect(next, isNull);
  });

  test('시작하는 분과 지금이 같으면 진행 중이다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('starting', '15:00'),
    ], _at(15, 0));

    expect(next?.phase, NextSessionPhase.inProgress);
    expect(next?.minutesLeft, 50);
  });

  test('마지막 수업이 끝난 뒤에는 고를 수업이 없다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('a', '09:00'),
      _s('b', '11:00'),
    ], _at(20, 0));

    expect(next, isNull);
  });

  test('목록 순서가 아니라 시작 시각이 이른 쪽을 고른다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('late', '18:00'),
      _s('early', '16:00'),
    ], _at(15, 0));

    expect(next?.session.id, 'early');
  });

  test('완료·취소·노쇼·빈 시간·해제 회원 일정은 뺀다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('done', '16:00', status: ScheduleStatus.done),
      _s('cancelled', '16:10', status: ScheduleStatus.cancelled),
      _s('noshow', '16:20', status: ScheduleStatus.noShow),
      _s('gap', '16:30', status: ScheduleStatus.gap),
      _s('detached', '16:40', detached: true),
      _s('real', '17:00'),
    ], _at(15, 0));

    expect(next?.session.id, 'real');
  });

  test('오늘이 아닌 날의 세션은 고르지 않는다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('yesterday', '23:00', date: '2026-08-19'),
    ], DateTime(2026, 8, 20, 0, 5));

    expect(next, isNull);
  });

  test('시각 형식이 깨진 세션은 고르지 않는다', () {
    final NextSession? next = pickNextSession(<ScheduleSession>[
      _s('broken', '오후 3시'),
    ], _at(10, 0));

    expect(next, isNull);
  });

  test('길이가 0 인 세션은 시작 1분으로 본다', () {
    expect(
      pickNextSession(<ScheduleSession>[
        _s('zero', '15:00', minutes: 0),
      ], _at(15, 0))?.minutesLeft,
      1,
    );
    expect(
      pickNextSession(<ScheduleSession>[
        _s('zero', '15:00', minutes: 0),
      ], _at(15, 1)),
      isNull,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/search/domain/client_search_facts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

ScheduleSession session({
  required String date,
  required String time,
  String? clientId,
  String clientName = '',
  String status = ScheduleStatus.upcoming,
}) => ScheduleSession(
  id: '$date-$time',
  date: date,
  time: time,
  clientId: clientId,
  clientName: clientName,
  type: SessionType.personalTraining,
  durationMinutes: 60,
  status: status,
  note: '',
  program: const <ProgramItem>[],
);

void main() {
  final minsu = makeClient(name: '김민수');
  final jisu = makeClient(id: 'c2', name: '이지수');

  group('nextSessionsByClient', () {
    test('회원별 가장 이른 예정 예약을 반환한다', () {
      final map = nextSessionsByClient(
        <TrainerClient>[minsu, jisu],
        <ScheduleSession>[
          session(date: '2026-08-20', time: '10:00', clientId: 'c1'),
          session(date: '2026-08-13', time: '15:00', clientId: 'c1'),
          session(date: '2026-08-13', time: '09:00', clientId: 'c2'),
        ],
      );

      expect(map['c1']!.date, '2026-08-13');
      expect(map['c1']!.time, '15:00');
      expect(map['c2']!.time, '09:00');
    });

    test('완료 예약과 공백 슬롯은 제외한다', () {
      final map = nextSessionsByClient(
        <TrainerClient>[minsu],
        <ScheduleSession>[
          session(
            date: '2026-08-11',
            time: '10:00',
            clientId: 'c1',
            status: ScheduleStatus.done,
          ),
          session(
            date: '2026-08-11',
            time: '12:00',
            status: ScheduleStatus.gap,
          ),
        ],
      );

      expect(map, isEmpty);
    });

    test('clientId가 없는 과거 예약은 유일한 이름으로 연결한다', () {
      final map = nextSessionsByClient(
        <TrainerClient>[minsu],
        <ScheduleSession>[
          session(date: '2026-08-13', time: '11:00', clientName: ' 김민수 '),
        ],
      );

      expect(map['c1']!.time, '11:00');
    });

    test('동명이인에게 clientId 없는 예약을 임의 연결하지 않는다', () {
      final anotherMinsu = makeClient(id: 'c3', name: ' 김민수 ');
      final map = nextSessionsByClient(
        <TrainerClient>[minsu, anotherMinsu],
        <ScheduleSession>[
          session(date: '2026-08-13', time: '11:00', clientName: '김민수'),
        ],
      );

      expect(map, isEmpty);
    });
  });

  test('기본 선택 경로는 현재 탭의 회원 화면을 유지한다', () {
    final facts = ClientSearchFacts(
      nextSession: <String, ScheduleSession>{
        minsu.id: session(
          date: '2026-08-20',
          time: '10:00',
          clientId: minsu.id,
        ),
      },
    );

    expect(
      clientSearchDestination(Uri.parse('/clients/c2/workout'), minsu, facts),
      '/clients/c1/workout',
    );
    expect(
      clientSearchDestination(Uri.parse('/messages?f=unread'), minsu, facts),
      '/messages?client=c1&f=unread',
    );
    expect(
      clientSearchDestination(Uri.parse('/coaching'), minsu, facts),
      '/coaching?client=c1',
    );
    expect(
      clientSearchDestination(Uri.parse('/reports'), minsu, facts),
      '/reports?client=c1',
    );
    expect(
      clientSearchDestination(Uri.parse('/schedule'), minsu, facts),
      '/schedule?d=2026-08-20',
    );
    expect(
      clientSearchDestination(Uri.parse('/dashboard'), minsu, facts),
      '/clients/c1/diet',
    );
  });
}

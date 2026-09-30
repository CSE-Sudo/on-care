/// 다음 PT 는 **지금 이후** 가장 이른 일정이다. (#2636)
///
/// 예전 규칙은 트레이너 일정을 날짜만 오늘과 견줘, 오늘 오전에 끝난 PT 가 오후에도
/// 다음 PT 로 남고 내일 일정을 가렸다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/presentation/utils/next_pt.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// 2026-08-20(목) 14:00 KST.
final DateTime _now = DateTime(2026, 8, 20, 14);

CoachSession _session(
  String id,
  DateTime? date,
  String time, {
  String status = '예정',
}) => CoachSession(
  id: id,
  date: date,
  time: time,
  type: '1:1 PT',
  durationMinutes: 50,
  status: status,
);

MyReservation _reservation(DateTime at, {bool cancellable = true}) =>
    MyReservation(
      id: 'res-${at.toIso8601String()}',
      slotId: 'slot',
      trainerId: 'trainer',
      startsAt: at,
      cancellable: cancellable,
    );

DateTime? _next({
  List<CoachSession> sessions = const <CoachSession>[],
  List<MyReservation> reservations = const <MyReservation>[],
  DateTime? now,
}) =>
    nextPtAt(sessions: sessions, reservations: reservations, now: now ?? _now);

void main() {
  group('트레이너 일정', () {
    test('오늘 이미 지난 시각의 일정은 다음 PT 가 아니다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('am', DateTime(2026, 8, 20), '10:00'),
          ],
        ),
        isNull,
      );
    });

    test('오늘 지난 일정이 내일 일정을 가리지 않는다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('am', DateTime(2026, 8, 20), '10:00'),
            _session('tomorrow', DateTime(2026, 8, 21), '19:00'),
          ],
        ),
        DateTime(2026, 8, 21, 19),
      );
    });

    test('오늘 아직 오지 않은 시각의 일정은 그대로 다음 PT 다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('pm', DateTime(2026, 8, 20), '19:30'),
            _session('tomorrow', DateTime(2026, 8, 21), '09:00'),
          ],
        ),
        DateTime(2026, 8, 20, 19, 30),
      );
    });

    test('지금 막 시작하는 일정은 남긴다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('now', DateTime(2026, 8, 20), '14:00'),
          ],
        ),
        DateTime(2026, 8, 20, 14),
      );
    });

    test('1분 전에 시작한 일정은 빠진다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('now', DateTime(2026, 8, 20), '14:00'),
          ],
          now: DateTime(2026, 8, 20, 14, 1),
        ),
        isNull,
      );
    });

    test('시각이 비어 있는 오늘 일정은 오늘 일정으로 남는다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('allday', DateTime(2026, 8, 20), ''),
          ],
        ),
        DateTime(2026, 8, 20),
      );
    });

    test('시각을 읽을 수 없는 오늘 일정도 지났다고 단정하지 않는다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('odd', DateTime(2026, 8, 20), '저녁'),
          ],
        ),
        DateTime(2026, 8, 20),
      );
    });

    test('어제 일정은 시각과 상관없이 빠진다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('yesterday', DateTime(2026, 8, 19), '23:00'),
            _session('yesterday-allday', DateTime(2026, 8, 19), ''),
          ],
        ),
        isNull,
      );
    });

    test('완료·취소·노쇼 일정은 빠진다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('done', DateTime(2026, 8, 21), '10:00', status: '완료'),
            _session('cancel', DateTime(2026, 8, 21), '11:00', status: '취소'),
            _session('noshow', DateTime(2026, 8, 21), '12:00', status: '노쇼'),
          ],
        ),
        isNull,
      );
    });

    test('날짜가 없는 일정은 빠진다', () {
      expect(
        _next(sessions: <CoachSession>[_session('nodate', null, '19:00')]),
        isNull,
      );
    });
  });

  group('예약', () {
    test('취소할 수 있는 예약은 다음 PT 후보다', () {
      expect(
        _next(
          reservations: <MyReservation>[
            _reservation(DateTime(2026, 8, 22, 18)),
          ],
        ),
        DateTime(2026, 8, 22, 18),
      );
    });

    test('취소할 수 없는 예약(서버가 지났다고 본 자리)은 빠진다', () {
      expect(
        _next(
          reservations: <MyReservation>[
            _reservation(DateTime(2026, 8, 22, 18), cancellable: false),
          ],
        ),
        isNull,
      );
    });
  });

  group('둘을 합친다', () {
    test('트레이너 일정과 예약 중 가장 이른 것을 고른다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('s', DateTime(2026, 8, 23), '10:00'),
          ],
          reservations: <MyReservation>[_reservation(DateTime(2026, 8, 21, 7))],
        ),
        DateTime(2026, 8, 21, 7),
      );
    });

    test('지난 오늘 일정은 합칠 때도 빠져 예약이 선다', () {
      expect(
        _next(
          sessions: <CoachSession>[
            _session('am', DateTime(2026, 8, 20), '09:00'),
          ],
          reservations: <MyReservation>[
            _reservation(DateTime(2026, 8, 25, 20)),
          ],
        ),
        DateTime(2026, 8, 25, 20),
      );
    });

    test('아무것도 없으면 null', () {
      expect(_next(), isNull);
    });
  });

  group('시각 읽기', () {
    test('HH:MM 을 읽는다', () {
      expect(parseSessionTime('07:05'), (hour: 7, minute: 5));
      expect(parseSessionTime(' 19:30 '), (hour: 19, minute: 30));
      expect(parseSessionTime('19:30:00'), (hour: 19, minute: 30));
    });

    test('비었거나 형식이 다르면 null', () {
      expect(parseSessionTime(''), isNull);
      expect(parseSessionTime('19'), isNull);
      expect(parseSessionTime('저녁:반'), isNull);
      expect(parseSessionTime('25:00'), isNull);
      expect(parseSessionTime('10:75'), isNull);
    });
  });
}

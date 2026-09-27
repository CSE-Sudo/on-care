import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/dashboard/domain/churn_risk.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

// 서버 `_daily_week`·데모 시드 `_onWeekdays` 는 이번 주 월→일 고정 창을 주고
// 아직 오지 않은 요일을 0 으로 채운다. 이탈 위험 규칙이 그 0 을 "최근 끊김"
// 으로 읽지 않는지 요일마다 확인한다(#2282).

/// 2026-08-17(월) … 2026-08-23(일), 낮 12시(KST 벽시계).
final List<DateTime> _week = <DateTime>[
  for (var i = 0; i < 7; i++) DateTime(2026, 8, 17 + i, 12),
];

const List<String> _dayNames = <String>['월', '화', '수', '목', '금', '토', '일'];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 서버 모양의 주간 계열 — 월→오늘은 [pick], 미래 요일은 0.
List<int> _series(DateTime now, int Function(int index) pick) => <int>[
  for (var i = 0; i < 7; i++) i < now.weekday ? pick(i) : 0,
];

/// 지난 날을 모두 기록한 회원의 월→일 계열.
List<int> _fullUpToToday(DateTime now, int value) => _series(now, (_) => value);

ScheduleSession _doneWithNote(DateTime now) => ScheduleSession(
  id: 's-done',
  date: _ymd(now),
  time: '09:00',
  clientId: 'c1',
  clientName: '테스트회원',
  type: 'PT',
  durationMinutes: 50,
  status: ScheduleStatus.done,
  note: '스쿼트 자세 좋아짐',
  program: const <ProgramItem>[],
);

void main() {
  group('elapsedWeekDays', () {
    test('월=1 … 일=7, 오늘을 포함한다', () {
      for (var i = 0; i < 7; i++) {
        expect(elapsedWeekDays(_week[i]), i + 1, reason: _dayNames[i]);
      }
    });

    test('KST 자정 경계 — 일요일 23:59 는 7, 다음 월요일 00:00 은 1', () {
      expect(elapsedWeekDays(DateTime(2026, 8, 23, 23, 59)), 7);
      expect(elapsedWeekDays(DateTime(2026, 8, 24)), 1);
    });

    test('월이 바뀌는 주에도 요일로만 센다', () {
      // 2026-09-30(수) → 10-01(목)
      expect(elapsedWeekDays(DateTime(2026, 9, 30, 8)), 3);
      expect(elapsedWeekDays(DateTime(2026, 10, 1, 8)), 4);
    });
  });

  group('dietRecentlyStopped — 요일별', () {
    for (var i = 0; i < 7; i++) {
      final now = _week[i];
      final day = _dayNames[i];

      test('$day: 월→오늘을 모두 기록한 회원은 미래 0 때문에 걸리지 않는다', () {
        final client = makeClient(
          caloriesWeek: _fullUpToToday(now, 1800),
          sodiumWeek: _fullUpToToday(now, 1500),
        );
        expect(dietRecentlyStopped(client, now: now), isFalse);
      });

      test('$day: 처음부터 기록이 없던 회원은 끊김이 아니다', () {
        final client = makeClient(
          caloriesWeek: List<int>.filled(7, 0),
          sodiumWeek: List<int>.filled(7, 0),
        );
        expect(dietRecentlyStopped(client, now: now), isFalse);
      });

      test('$day: 오늘 기록이 있으면 끊김이 아니다', () {
        final client = makeClient(
          caloriesWeek: _series(now, (d) => d == now.weekday - 1 ? 1700 : 0),
          sodiumWeek: _series(now, (d) => d == now.weekday - 1 ? 1400 : 0),
        );
        expect(dietRecentlyStopped(client, now: now), isFalse);
      });
    }

    for (final i in <int>[0, 1, 2]) {
      final now = _week[i];
      test('${_dayNames[i]}: 비교할 앞쪽 날이 없어 판단하지 않는다', () {
        // 월요일에만 기록하고 그 뒤 0 — 목요일 이후라면 끊김이지만, 주 초에는
        // 최근 3일 앞에 볼 날이 없다.
        final client = makeClient(
          caloriesWeek: <int>[1800, 0, 0, 0, 0, 0, 0],
          sodiumWeek: <int>[1500, 0, 0, 0, 0, 0, 0],
        );
        expect(dietRecentlyStopped(client, now: now), isFalse);
      });
    }

    for (final i in <int>[3, 4, 5, 6]) {
      final now = _week[i];
      final day = _dayNames[i];
      final earlier = now.weekday - dietStopRecentDays;

      test('$day: 앞쪽 $earlier일 기록 뒤 최근 3일이 비면 끊김이다', () {
        final client = makeClient(
          caloriesWeek: _series(now, (d) => d < earlier ? 1800 : 0),
          sodiumWeek: _series(now, (d) => d < earlier ? 1500 : 0),
        );
        expect(dietRecentlyStopped(client, now: now), isTrue);
      });

      test('$day: 최근 3일 중 하루라도 기록이 있으면 끊김이 아니다', () {
        for (var r = earlier; r < now.weekday; r++) {
          final client = makeClient(
            caloriesWeek: _series(now, (d) => d < earlier || d == r ? 1800 : 0),
            sodiumWeek: _series(now, (d) => d < earlier || d == r ? 1500 : 0),
          );
          expect(
            dietRecentlyStopped(client, now: now),
            isFalse,
            reason: '$day, 인덱스 $r 에 기록',
          );
        }
      });

      test('$day: 앞쪽 구간 첫날만 기록해도 끊김으로 본다', () {
        final client = makeClient(
          caloriesWeek: _series(now, (d) => d == 0 ? 1800 : 0),
          sodiumWeek: _series(now, (d) => d == 0 ? 1500 : 0),
        );
        expect(dietRecentlyStopped(client, now: now), isTrue);
      });
    }

    test('일요일 판정은 예전 롤링 창 판정(앞 4일·뒤 3일)과 같다', () {
      final sunday = _week[6];
      final client = makeClient(
        caloriesWeek: <int>[1800, 1700, 0, 1600, 0, 0, 0],
        sodiumWeek: <int>[1500, 1400, 0, 1300, 0, 0, 0],
      );
      expect(dietRecentlyStopped(client, now: sunday), isTrue);
    });

    test('나트륨만 앞쪽에 있어도 기록이 있던 회원이다', () {
      final client = makeClient(
        caloriesWeek: List<int>.filled(7, 0),
        sodiumWeek: <int>[1500, 1500, 0, 0, 0, 0, 0],
      );
      expect(dietRecentlyStopped(client, now: _week[4]), isTrue);
    });

    test('최근 3일에 칼로리만 있어도 끊김이 아니다', () {
      final client = makeClient(
        caloriesWeek: <int>[1800, 1800, 0, 1200, 0, 0, 0],
        sodiumWeek: <int>[1500, 1500, 0, 0, 0, 0, 0],
      );
      expect(dietRecentlyStopped(client, now: _week[4]), isFalse);
    });

    test('미래 요일에 값이 섞여 와도 지난 날만 본다', () {
      // 목요일: 월 기록, 화~목 0. 금요일 칸의 값은 아직 오지 않은 날이라
      // 판정에 들어가면 안 된다.
      final client = makeClient(
        caloriesWeek: <int>[1800, 0, 0, 0, 1900, 0, 0],
        sodiumWeek: <int>[1500, 0, 0, 0, 1600, 0, 0],
      );
      expect(dietRecentlyStopped(client, now: _week[3]), isTrue);
    });

    test('계열 길이가 7이 아니면 판단하지 않는다', () {
      final now = _week[6];
      expect(
        dietRecentlyStopped(
          makeClient(sodiumWeek: <int>[1500, 1500, 0, 0, 0, 0, 0]),
          now: now,
        ),
        isFalse,
        reason: '칼로리 계열이 비어 있는 예전 행',
      );
      expect(
        dietRecentlyStopped(
          makeClient(
            caloriesWeek: <int>[1800, 1800, 0, 0, 0, 0],
            sodiumWeek: <int>[1500, 1500, 0, 0, 0, 0],
          ),
          now: now,
        ),
        isFalse,
        reason: '6일치',
      );
    });
  });

  group('goalStagnant — 요일별', () {
    for (var i = 0; i < 7; i++) {
      final now = _week[i];
      final day = _dayNames[i];

      test('$day: 지난 날이 모두 40% 면 3일째부터 정체다', () {
        final client = makeClient(weekCompletion: _fullUpToToday(now, 40));
        expect(goalStagnant(client, now: now), now.weekday >= 3);
      });

      test('$day: 이행률이 높으면 정체가 아니다', () {
        final client = makeClient(weekCompletion: _fullUpToToday(now, 90));
        expect(goalStagnant(client, now: now), isFalse);
      });
    }

    test('미래 요일의 값은 기록 수에 넣지 않는다', () {
      // 화요일: 지난 날 기록은 이틀뿐이다. 수~일 칸 값이 섞여 오더라도
      // 3일 기준을 채우지 못한다.
      final client = makeClient(
        weekCompletion: <int>[40, 40, 40, 40, 40, 0, 0],
      );
      expect(goalStagnant(client, now: _week[1]), isFalse);
      expect(goalStagnant(client, now: _week[2]), isTrue);
    });

    test('0 은 기록 없음이라 빼고 센다', () {
      final client = makeClient(weekCompletion: <int>[40, 0, 45, 0, 35, 0, 0]);
      expect(goalStagnant(client, now: _week[4]), isTrue);
      expect(goalStagnant(client, now: _week[3]), isFalse, reason: '목: 2일뿐');
    });

    test('평균 50% 경계와 폭 15%p 경계', () {
      final sunday = _week[6];
      expect(
        goalStagnant(
          makeClient(weekCompletion: <int>[50, 50, 50, 0, 0, 0, 0]),
          now: sunday,
        ),
        isFalse,
        reason: '평균 50 은 정체 아님',
      );
      expect(
        goalStagnant(
          makeClient(weekCompletion: <int>[30, 45, 40, 0, 0, 0, 0]),
          now: sunday,
        ),
        isTrue,
        reason: '폭 15 는 정체',
      );
      expect(
        goalStagnant(
          makeClient(weekCompletion: <int>[30, 46, 40, 0, 0, 0, 0]),
          now: sunday,
        ),
        isFalse,
        reason: '폭 16 은 변화',
      );
    });
  });

  group('noRecentWorkout — 요일별', () {
    for (var i = 0; i < 7; i++) {
      final now = _week[i];
      final day = _dayNames[i];

      test('$day: 이번 주 기록이 없을 때 3일째부터 켜진다', () {
        final signals = computeChurnSignals(
          makeClient(weekCompletion: List<int>.filled(7, 0)),
          recentSessions: <ScheduleSession>[_doneWithNote(now)],
          unreadCount: 0,
          now: now,
        );
        expect(
          signals.contains(ChurnSignal.noRecentWorkout),
          now.weekday >= churnMinElapsedDays,
        );
      });

      test('$day: 오늘 하루라도 기록하면 켜지지 않는다', () {
        final signals = computeChurnSignals(
          makeClient(
            weekCompletion: _series(now, (d) => d == now.weekday - 1 ? 80 : 0),
          ),
          recentSessions: <ScheduleSession>[_doneWithNote(now)],
          unreadCount: 0,
          now: now,
        );
        expect(signals, isNot(contains(ChurnSignal.noRecentWorkout)));
      });
    }
  });

  group('buildChurnRisk — 주 초 오탐 회귀', () {
    for (var i = 0; i < 7; i++) {
      final now = _week[i];
      final day = _dayNames[i];

      test('$day: 꾸준히 기록하는 회원은 어떤 신호도 받지 않는다', () {
        final client = makeClient(
          weekCompletion: _fullUpToToday(now, 80),
          caloriesWeek: _fullUpToToday(now, 1800),
          sodiumWeek: _fullUpToToday(now, 1500),
        );
        expect(
          computeChurnSignals(
            client,
            recentSessions: <ScheduleSession>[_doneWithNote(now)],
            unreadCount: 0,
            now: now,
          ),
          isEmpty,
        );
      });

      test('$day: 피드백만 밀린 기록 회원은 이탈 위험이 아니다', () {
        // 예전에는 월~목에 미래 0 이 식단 끊김으로 읽혀, 피드백 없음과 겹쳐
        // 이탈 위험으로 잡혔다.
        final client = makeClient(
          weekCompletion: _fullUpToToday(now, 80),
          caloriesWeek: _fullUpToToday(now, 1800),
          sodiumWeek: _fullUpToToday(now, 1500),
        );
        final result = buildChurnRisk(
          clients: <TrainerClient>[client],
          recentSessionsByClient: const <String, List<ScheduleSession>>{},
          unread: const <String, int>{},
          now: now,
        );
        expect(result, isEmpty);
      });
    }

    test('목요일: 월요일 뒤 식단이 끊기고 피드백도 없으면 이탈 위험이다', () {
      final thursday = _week[3];
      final client = makeClient(
        weekCompletion: _fullUpToToday(thursday, 80),
        caloriesWeek: <int>[1800, 0, 0, 0, 0, 0, 0],
        sodiumWeek: <int>[1500, 0, 0, 0, 0, 0, 0],
      );
      final result = buildChurnRisk(
        clients: <TrainerClient>[client],
        recentSessionsByClient: const <String, List<ScheduleSession>>{},
        unread: const <String, int>{},
        now: thursday,
      );
      expect(result, hasLength(1));
      expect(result.single.signals, <ChurnSignal>{
        ChurnSignal.dietStopped,
        ChurnSignal.noRecentFeedback,
      });
    });

    test('월요일 00:00(KST) — 지난주 기록이 보이지 않아도 오탐하지 않는다', () {
      final mondayMidnight = DateTime(2026, 8, 24);
      final client = makeClient(
        weekCompletion: List<int>.filled(7, 0),
        caloriesWeek: List<int>.filled(7, 0),
        sodiumWeek: List<int>.filled(7, 0),
      );
      final signals = computeChurnSignals(
        client,
        recentSessions: const <ScheduleSession>[],
        unreadCount: 0,
        now: mondayMidnight,
      );
      expect(signals, <ChurnSignal>{ChurnSignal.noRecentFeedback});
      expect(isChurnRisk(signals), isFalse);
    });
  });
}

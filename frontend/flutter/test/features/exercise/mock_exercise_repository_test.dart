import 'dart:io';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

/// 기대값은 여기에 적지 않고 **원본 픽스처 파일**에서 뽑는다. 숫자를 적어 두면
/// 픽스처와 두 벌이 되어, 한쪽만 고쳤을 때 조용히 갈린다(#757).
///
/// 앱에 심긴 상수(`kimMinsuFixtureJson`)가 아니라 원본 파일을 읽는 이유: 목업은
/// 심긴 상수를 쓰므로, 둘이 어긋나면 이 테스트가 그것까지 잡는다.
final DemoFixture _fixture = DemoFixture.parse(
  File('../../shared/demo_fixture/assets/kim_minsu.json').readAsStringSync(),
);

/// 시드는 날짜에 상대적이라 오늘이 언제냐에 따라 값이 달라진다. 결정적 검증을
/// 위해 고정 금요일(2024-01-05, weekday=금 → index 4)을 주입한다.
final DateTime _friday = DateTime(2024, 1, 5);

MockExerciseRepository _repo({DateTime? today}) =>
    MockExerciseRepository(today: today ?? _friday);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [today] 기준 [weeksAgo] 주 전의 픽스처 하루들.
List<FixtureDay> _weekDays(DateTime today, {int weeksAgo = 0}) {
  final DateTime monday = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - 1) - 7 * weeksAgo,
  );
  return _fixture
      .daysFor(today)
      .where((FixtureDay d) => d.weekStart == _ymd(monday))
      .toList();
}

/// 그 주의 요일별(월→일) **한** 운동 분.
List<double> _minutesByWeekday(DateTime today, {int weeksAgo = 0}) {
  final List<double> out = List<double>.filled(7, 0);
  for (final FixtureDay day in _weekDays(today, weeksAgo: weeksAgo)) {
    out[DateTime.parse(day.date).weekday - 1] = day.doneExercises
        .fold<int>(0, (int sum, FixtureExercise e) => sum + e.minutes)
        .toDouble();
  }
  return out;
}

void main() {
  group('이번 주는 공유 픽스처에서 온다 (#771)', () {
    test('세션·시간·칼로리가 픽스처의 한 운동과 같다', () async {
      final ExerciseWeek w = await _repo().fetchThisWeek();
      final List<FixtureDay> days = _weekDays(_friday);

      // 운동 하나가 세션 하나다 — 실서버와 같은 모양이다(#1902). 예전에는
      // 하루·종류당 하나로 합쳐, 종목별 세트·중량을 담을 칸이 없어 픽스처가 그
      // 수를 이름 문자열에 적어 넣어야 했다.
      final int expectedSessions = days.fold<int>(
        0,
        (int sum, FixtureDay d) => sum + d.doneExercises.length,
      );
      expect(w.sessions.length, expectedSessions);
      expect(w.dailyMinutes, _minutesByWeekday(_friday));
      expect(
        w.totalMinutes,
        days.fold<int>(
          0,
          (int sum, FixtureDay d) =>
              sum +
              d.doneExercises.fold<int>(
                0,
                (int s, FixtureExercise e) => s + e.minutes,
              ),
        ),
      );
      expect(
        w.totalCalories,
        days.fold<int>(
          0,
          (int sum, FixtureDay d) =>
              sum +
              d.doneExercises.fold<int>(
                0,
                (int s, FixtureExercise e) => s + e.calories,
              ),
        ),
      );
      expect(w.streakDays, longestActiveStreak(w.dailyMinutes));
    });

    test('운동 일수는 트레이너웹의 이행률 기록일과 같은 날을 센다', () async {
      // 트레이너웹은 같은 픽스처에서 나온 일별 이행률이 0 보다 큰 날을 센다.
      // 두 앱이 같은 사람을 다른 횟수로 말하지 않으려면 이 둘이 같아야 한다 —
      // 예전에는 목업이 '오늘 + 직전 3일'을 스스로 박아 6회 vs 4회로 갈렸다.
      final ExerciseWeek w = await _repo().fetchThisWeek();
      final int loggedDays = _weekDays(
        _friday,
      ).where((FixtureDay d) => d.completion > 0).length;

      expect(loggedDays, greaterThan(0), reason: '픽스처에 이번 주 기록이 없다');
      expect(w.workoutCount, loggedDays);
    });

    test('주 시작 전으로 넘어가는 날은 이번 주 뷰에 들어오지 않는다', () async {
      // 월요일(2024-01-01)이면 이번 주에 남는 날은 오늘 하루뿐이다.
      final DateTime monday = DateTime(2024);
      final ExerciseWeek w = await _repo(today: monday).fetchThisWeek();

      expect(w.dailyMinutes, _minutesByWeekday(monday));
      expect(w.dailyMinutes.skip(1), everyElement(0.0));
      expect(w.workoutCount, 1);
    });

    test(
      'daily == cardio + strength + stretching + other for every day',
      () async {
        final ExerciseWeek w = await _repo().fetchThisWeek();
        for (int i = 0; i < w.dailyMinutes.length; i++) {
          expect(
            w.cardioMinutes[i] +
                w.strengthMinutes[i] +
                w.stretchingMinutes[i] +
                w.otherMinutes[i],
            w.dailyMinutes[i],
            reason: '요일 index $i 유형 합이 일별 총합과 어긋납니다.',
          );
        }
      },
    );

    test('오늘 기록에는 오늘 라벨과 픽스처의 종목 이름이 붙는다', () async {
      final ExerciseWeek w = await _repo().fetchThisWeek();
      final FixtureDay today = _weekDays(_friday).last;
      final Iterable<ExerciseSession> todaySessions = w.sessions.where(
        (ExerciseSession s) => s.dateLabel == '오늘',
      );

      expect(todaySessions, isNotEmpty);
      expect(
        todaySessions.expand((ExerciseSession s) => s.items).toSet(),
        today.doneExercises.map((FixtureExercise e) => e.name).toSet(),
      );
    });
  });

  group('CRUD keeps derived totals/chart in memory (#294)', () {
    test('addSession persists and updates totals/chart/count', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek before = await r.fetchThisWeek();
      // 아직 기록이 없는 요일을 골라 새 활성일이 하나 느는 것을 본다.
      final int restDay = before.dailyMinutes.indexOf(0);
      expect(restDay, greaterThanOrEqualTo(0), reason: '이번 주가 이미 꽉 찼다');

      final DateTime monday = _friday.subtract(
        Duration(days: _friday.weekday - 1),
      );
      final ExerciseSession added = await r.addSession(
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 200,
        date: monday.add(Duration(days: restDay)),
      );

      final ExerciseWeek after = await r.fetchThisWeek();
      expect(after.sessions.length, before.sessions.length + 1);
      expect(
        after.sessions.map((ExerciseSession s) => s.id),
        contains(added.id),
      );
      expect(after.totalMinutes, before.totalMinutes + 30);
      expect(after.totalCalories, before.totalCalories + 200);
      expect(after.dailyMinutes[restDay], 30);
      expect(after.dailyCalories[restDay], 200);
      expect(after.cardioMinutes[restDay], 30);
      expect(after.workoutCount, before.workoutCount + 1);
    });

    test('deleteSession removes it and restores the totals', () async {
      final MockExerciseRepository r = _repo();
      // 지울 수 있는 것은 회원이 적은 기록뿐이다 — 픽스처 기록은 PT·배정
      // 루틴에서 온 파생 기록이라 이 경로로 사라지지 않는다.
      final DateTime monday = _friday.subtract(
        Duration(days: _friday.weekday - 1),
      );
      final int day = (await r.fetchThisWeek()).dailyMinutes.indexOf(0);
      final ExerciseSession target = await r.addSession(
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 200,
        date: monday.add(Duration(days: day)),
      );
      final ExerciseWeek before = await r.fetchThisWeek();

      await r.deleteSession(target.id!);

      final ExerciseWeek after = await r.fetchThisWeek();
      expect(after.sessions.length, before.sessions.length - 1);
      expect(
        after.sessions.map((ExerciseSession s) => s.id),
        isNot(contains(target.id)),
      );
      expect(after.totalMinutes, before.totalMinutes - target.minutes);
      expect(after.totalCalories, before.totalCalories - target.calories);
      expect(
        after.dailyMinutes[day],
        before.dailyMinutes[day] - target.minutes,
      );
      expect(
        after.cardioMinutes[day],
        before.cardioMinutes[day] - target.minutes,
      );
    });

    test('deleting an unknown id is a no-op', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek before = await r.fetchThisWeek();
      await r.deleteSession('does-not-exist');
      final ExerciseWeek after = await r.fetchThisWeek();
      expect(after.sessions.length, before.sessions.length);
      expect(after.totalMinutes, before.totalMinutes);
    });

    test('updateSession edits a session and re-derives totals', () async {
      final MockExerciseRepository r = _repo();
      final DateTime monday = _friday.subtract(
        Duration(days: _friday.weekday - 1),
      );
      final int day = (await r.fetchThisWeek()).dailyMinutes.indexOf(0);
      final ExerciseSession target = await r.addSession(
        type: ExerciseType.strength,
        minutes: 20,
        calories: 120,
        date: monday.add(Duration(days: day)),
      );
      final ExerciseWeek before = await r.fetchThisWeek();

      await r.updateSession(
        id: target.id!,
        type: ExerciseType.strength,
        minutes: target.minutes + 30,
        calories: target.calories + 180,
        date: monday.add(Duration(days: day)),
      );

      final ExerciseWeek after = await r.fetchThisWeek();
      expect(after.sessions.length, before.sessions.length); // 개수 불변
      expect(after.totalMinutes, before.totalMinutes + 30);
      expect(after.totalCalories, before.totalCalories + 180);
      expect(after.strengthMinutes[day], before.strengthMinutes[day] + 30);
      expect(after.dailyMinutes[day], before.dailyMinutes[day] + 30);
    });
  });

  group('픽스처 기록의 출처는 PT·배정 루틴이다 (#499, #638)', () {
    test('PT 날은 trainer_pt, 나머지 날은 assigned_routine 이다', () async {
      final ExerciseWeek w = await _repo().fetchThisWeek();
      for (final FixtureDay day in _weekDays(_friday)) {
        final Iterable<ExerciseSession> ofDay = w.sessions.where(
          (ExerciseSession s) => s.dayLabel == day.dayLabel,
        );
        expect(ofDay, isNotEmpty, reason: '${day.date} 기록이 통째로 비었다');
        expect(
          ofDay.map((ExerciseSession s) => s.source).toSet(),
          <ExerciseSource>{
            day.isPt
                ? ExerciseSource.trainerPt
                : ExerciseSource.assignedRoutine,
          },
        );
      }
    });

    test('회원이 직접 적은 기록은 하나도 없다 — `직접 추가한 운동` 은 비어 있다', () async {
      final ExerciseWeek w = await _repo().fetchThisWeek();
      expect(w.sessions.where((ExerciseSession s) => s.isEditable), isEmpty);
    });

    test('파생 기록은 회원이 고치거나 지우지 못한다 — 서버의 409 와 같다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek before = await r.fetchThisWeek();
      final ExerciseSession pt = before.sessions.firstWhere(
        (ExerciseSession s) => s.source == ExerciseSource.trainerPt,
      );

      await r.deleteSession(pt.id!);
      await r.updateSession(
        id: pt.id!,
        type: ExerciseType.cardio,
        minutes: 5,
        calories: 5,
        date: _friday,
      );

      final ExerciseWeek after = await r.fetchThisWeek();
      expect(after.sessions.length, before.sessions.length);
      expect(after.totalMinutes, before.totalMinutes);
      expect(after.totalCalories, before.totalCalories);
      expect(after.strengthSets, before.strengthSets);
      expect(after.dailyCalories, before.dailyCalories);
    });
  });

  group('fetchWeek 로 지난 주를 조회한다 (#671)', () {
    test('이번 주 월요일을 주면 fetchThisWeek 과 같다', () async {
      final MockExerciseRepository r = _repo();
      // 2024-01-05 는 금요일 → 그 주 월요일은 2024-01-01.
      final ExerciseWeek week = await r.fetchWeek(DateTime(2024));
      final ExerciseWeek current = await r.fetchThisWeek();
      expect(week.dailyMinutes, current.dailyMinutes);
      expect(week.totalMinutes, current.totalMinutes);
    });

    test('지난 주도 같은 픽스처에서 오고, 이번 주와 다르다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek last = await r.fetchWeek(DateTime(2023, 12, 25));
      final ExerciseWeek current = await r.fetchThisWeek();

      expect(last.dailyMinutes, _minutesByWeekday(_friday, weeksAgo: 1));
      expect(last.totalMinutes, greaterThan(0));
      expect(last.sessions, isNotEmpty);
      expect(
        last.dailyMinutes,
        isNot(current.dailyMinutes),
        reason: '지난 주가 이번 주 복사본이면 주간 비교가 뜻이 없다',
      );
      // 하루 합 = 유형별 합 (이번 주와 같은 규칙).
      for (int i = 0; i < last.dailyMinutes.length; i++) {
        expect(
          last.dailyMinutes[i],
          closeTo(
            last.cardioMinutes[i] +
                last.strengthMinutes[i] +
                last.stretchingMinutes[i],
            0.001,
          ),
        );
      }
      // 지난 주 세션에는 '오늘' 라벨이 붙지 않는다.
      expect(
        last.sessions.every((ExerciseSession s) => s.dateLabel != '오늘'),
        isTrue,
      );
    });

    test('픽스처가 덮지 않는 옛 주는 빈 주다', () async {
      // 없는 기록을 지어내면 트레이너웹과 다시 갈린다. 화면은 빈 주를
      // "기록이 없어요" 로 그린다.
      final MockExerciseRepository r = _repo();
      final DateTime tooOld = DateTime(
        2024,
        1,
        1 - 7 * (_fixture.historyWeeks + 1),
      );
      final ExerciseWeek week = await r.fetchWeek(tooOld);

      expect(week.sessions, isEmpty);
      expect(week.totalMinutes, 0);
      expect(week.dailyMinutes, everyElement(0.0));
    });
  });

  group('기간별 조언은 그 기간의 기록만 본다 (#1574)', () {
    test('오늘 / 이번 주 / 전체가 서로 다른 말을 한다', () async {
      final MockExerciseRepository r = _repo();
      final String today = (await r.fetchAdvice('today')).message;
      final String week = (await r.fetchAdvice('week')).message;
      final String all = (await r.fetchAdvice('all')).message;

      expect(<String>{today, week, all}.length, 3);
      // 오늘은 그날 한 것을, 이번 주는 며칠 움직였는지를 말한다.
      expect(today, contains('오늘'));
      expect(week, contains('이번 주'));
    });

    test('오늘 조언은 오늘 기록만 센다', () async {
      final MockExerciseRepository r = _repo();
      final List<FixtureDay> days = _weekDays(_friday);
      final FixtureDay? todayFixture = days
          .where((FixtureDay d) => d.date == _ymd(_friday))
          .firstOrNull;
      final int minutes =
          todayFixture?.doneExercises.fold<int>(
            0,
            (int sum, FixtureExercise e) => sum + e.minutes,
          ) ??
          0;

      final String advice = (await r.fetchAdvice('today')).message;
      if (minutes == 0) {
        // 없는 기록으로 조언을 지어내지 않는다.
        expect(advice, contains('기록이 아직 없어요'));
      } else {
        expect(advice, contains('$minutes분'));
      }
    });

    test('직접 적은 기록이 그날 조언에 바로 반영된다', () async {
      final MockExerciseRepository r = _repo();
      final String before = (await r.fetchAdvice('today')).message;
      await r.addSession(
        type: ExerciseType.cardio,
        minutes: 25,
        calories: 220,
        date: _friday,
        name: '저녁 걷기',
      );
      expect((await r.fetchAdvice('today')).message, isNot(before));
    });
  });
}

/// 데모에서 지난 주 날짜로 적은 운동은 **그 주**에 들어간다. (#2637)
///
/// 예전 목업 저장소는 날짜와 상관없이 이번 주 목록에 넣어, 지난 주 목요일로
/// 적은 30분이 이번 주 목요일 막대에 쌓이고 정작 지난 주에는 없었다. 실서버
/// (`_placement`)와 로컬 목업 API 는 날짜로 주를 정한다 — 목업도 같아야 한다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

/// 고정 금요일 — 이번 주 월요일은 2024-01-01, 지난 주 월요일은 2023-12-25.
final DateTime _friday = DateTime(2024, 1, 5);
final DateTime _thisMonday = DateTime(2024);
final DateTime _lastMonday = DateTime(2023, 12, 25);

/// 지난 주 목요일(인덱스 3).
final DateTime _lastThursday = DateTime(2023, 12, 28);
const int _thu = 3;

MockExerciseRepository _repo() => MockExerciseRepository(today: _friday);

Future<ExerciseSession> _add(
  MockExerciseRepository r,
  DateTime date, {
  int minutes = 30,
  int calories = 200,
  ExerciseType type = ExerciseType.cardio,
}) async => (await r.addSessions(<ExerciseSessionDraft>[
  ExerciseSessionDraft(
    type: type,
    minutes: minutes,
    calories: calories,
    date: date,
    name: '데모 기록',
  ),
])).sessions.single;

bool _has(ExerciseWeek w, String? id) =>
    w.sessions.any((ExerciseSession s) => s.id == id);

void main() {
  group('추가', () {
    test('지난 주 날짜로 적은 기록은 이번 주 합계·그래프에 더해지지 않는다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek before = await r.fetchThisWeek();

      final ExerciseSession added = await _add(r, _lastThursday);

      final ExerciseWeek after = await r.fetchThisWeek();
      expect(_has(after, added.id), isFalse);
      expect(after.sessions.length, before.sessions.length);
      expect(after.totalMinutes, before.totalMinutes);
      expect(after.totalCalories, before.totalCalories);
      expect(after.dailyMinutes, before.dailyMinutes);
    });

    test('지난 주를 조회하면 그 기록이 그 요일에 있다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek before = await r.fetchWeek(_lastMonday);

      final ExerciseSession added = await _add(r, _lastThursday, minutes: 40);

      final ExerciseWeek after = await r.fetchWeek(_lastMonday);
      expect(_has(after, added.id), isTrue);
      expect(after.sessions.length, before.sessions.length + 1);
      expect(after.dailyMinutes[_thu], before.dailyMinutes[_thu] + 40);
      expect(after.cardioMinutes[_thu], before.cardioMinutes[_thu] + 40);
      expect(after.totalMinutes, before.totalMinutes + 40);
    });

    test('두 주 전 날짜는 두 주 전에만 들어간다', () async {
      final MockExerciseRepository r = _repo();
      final DateTime twoWeeksAgo = DateTime(2023, 12, 20);
      final ExerciseSession added = await _add(r, twoWeeksAgo);

      expect(_has(await r.fetchWeek(DateTime(2023, 12, 18)), added.id), isTrue);
      expect(_has(await r.fetchWeek(_lastMonday), added.id), isFalse);
      expect(_has(await r.fetchThisWeek(), added.id), isFalse);
    });

    test('이번 주 날짜는 지금처럼 이번 주에 들어간다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek before = await r.fetchThisWeek();
      final ExerciseSession added = await _add(r, _thisMonday, calories: 150);

      final ExerciseWeek after = await r.fetchThisWeek();
      expect(_has(after, added.id), isTrue);
      expect(after.totalCalories, before.totalCalories + 150);
      expect(_has(await r.fetchWeek(_lastMonday), added.id), isFalse);
    });
  });

  group('수정으로 주를 옮긴다', () {
    test('이번 주 기록을 지난 주로 옮기면 이번 주에서 빠지고 지난 주에 들어간다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek thisBefore = await r.fetchThisWeek();
      final ExerciseWeek lastBefore = await r.fetchWeek(_lastMonday);
      final ExerciseSession added = await _add(r, _thisMonday, minutes: 25);

      await r.updateSession(
        id: added.id!,
        type: ExerciseType.cardio,
        minutes: 25,
        calories: 200,
        date: _lastThursday,
        name: '데모 기록',
      );

      final ExerciseWeek thisAfter = await r.fetchThisWeek();
      final ExerciseWeek lastAfter = await r.fetchWeek(_lastMonday);
      expect(_has(thisAfter, added.id), isFalse);
      expect(thisAfter.totalMinutes, thisBefore.totalMinutes);
      expect(thisAfter.totalCalories, thisBefore.totalCalories);
      expect(_has(lastAfter, added.id), isTrue);
      expect(lastAfter.dailyMinutes[_thu], lastBefore.dailyMinutes[_thu] + 25);
    });

    test('지난 주 기록을 이번 주로 옮기면 반대로 움직인다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek thisBefore = await r.fetchThisWeek();
      final ExerciseSession added = await _add(r, _lastThursday, calories: 90);

      await r.updateSession(
        id: added.id!,
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 90,
        date: _thisMonday,
        name: '데모 기록',
      );

      final ExerciseWeek thisAfter = await r.fetchThisWeek();
      expect(_has(thisAfter, added.id), isTrue);
      expect(thisAfter.totalCalories, thisBefore.totalCalories + 90);
      expect(_has(await r.fetchWeek(_lastMonday), added.id), isFalse);
    });

    test('같은 지난 주 안에서 고치면 제자리에서 바뀐다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseSession added = await _add(r, _lastThursday, minutes: 20);
      final ExerciseWeek before = await r.fetchWeek(_lastMonday);

      await r.updateSession(
        id: added.id!,
        type: ExerciseType.cardio,
        minutes: 50,
        calories: 300,
        date: _lastThursday,
        name: '데모 기록',
      );

      final ExerciseWeek after = await r.fetchWeek(_lastMonday);
      expect(after.sessions.length, before.sessions.length);
      expect(after.dailyMinutes[_thu], before.dailyMinutes[_thu] + 30);
    });
  });

  group('삭제', () {
    test('지난 주 날짜로 적은 기록도 지울 수 있다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek before = await r.fetchWeek(_lastMonday);
      final ExerciseSession added = await _add(r, _lastThursday);

      await r.deleteSession(added.id!);

      final ExerciseWeek after = await r.fetchWeek(_lastMonday);
      expect(_has(after, added.id), isFalse);
      expect(after.dailyMinutes, before.dailyMinutes);
    });

    test('지난 주 기록을 지워도 이번 주 헤드라인 칼로리는 그대로다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseWeek before = await r.fetchThisWeek();
      final ExerciseSession added = await _add(r, _lastThursday);
      await r.deleteSession(added.id!);

      expect((await r.fetchThisWeek()).totalCalories, before.totalCalories);
    });
  });

  group('지난 주를 읽는 다른 자리들', () {
    test('fetchPeriod 의 지난 주 칸에도 들어간다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseSession added = await _add(r, _lastThursday);

      final List<ExercisePeriodWeek> period = await r.fetchPeriod(
        from: _lastMonday,
        to: _friday,
      );
      final ExercisePeriodWeek last = period.firstWhere(
        (ExercisePeriodWeek w) => w.weekStart == _lastMonday,
      );
      expect(_has(last.week, added.id), isTrue);
    });

    test('주간 챌린지가 세는 운동한 날에 지난 주 날짜가 잡힌다', () async {
      final MockExerciseRepository r = _repo();
      await _add(r, _lastThursday);

      expect(r.recordedDaysOfWeek(_lastMonday), contains(_lastThursday));
      expect(r.recordedDaysOfWeek(_thisMonday), isNot(contains(_lastThursday)));
    });

    test('배정 루틴 완료를 지난 날짜로 남겨도 그 주에 들어가고 되돌리면 빠진다', () async {
      final MockExerciseRepository r = _repo();
      final ExerciseSession done = await r.addAssignedRoutineSession(
        type: ExerciseType.stretching,
        minutes: 10,
        calories: 30,
        date: _lastThursday,
        routineId: 'routine-1',
        name: '폼롤러',
      );
      expect(_has(await r.fetchWeek(_lastMonday), done.id), isTrue);
      expect(_has(await r.fetchThisWeek(), done.id), isFalse);

      await r.removeAssignedRoutineSession(done.id!);
      expect(_has(await r.fetchWeek(_lastMonday), done.id), isFalse);
    });
  });
}

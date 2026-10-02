/// 데모에서 지난 주 날짜로 적은 운동은 **그 주**에 들어간다. (#2637)
///
/// 예전 메모리 목업 저장소는 날짜와 상관없이 이번 주 목록에 넣어, 지난 주
/// 목요일로 적은 30분이 이번 주 목요일 막대에 쌓이고 정작 지난 주에는 없었다.
/// 실서버(`_placement`)와 로컬 목업 API 는 날짜로 주를 정한다. 데모는 이제
/// 로컬 목업 API 를 타므로(#2662) 그 위에서 같은 규칙을 본다(#2724).
///
/// 칼로리는 저장된 기록의 값으로 본다 — 서버처럼 로컬 목업 API 도 앱이 보낸
/// 값을 쓰지 않고 다시 계산한다(#1312).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';

import '../../helpers/demo_exercise.dart';
import '../../helpers/fixed_clock.dart';

/// 고정 금요일 — 이번 주 월요일은 2024-01-01, 지난 주 월요일은 2023-12-25.
final DateTime _friday = DateTime(2024, 1, 5);
final DateTime _thisMonday = DateTime(2024);
final DateTime _lastMonday = DateTime(2023, 12, 25);

/// 지난 주 목요일(인덱스 3).
final DateTime _lastThursday = DateTime(2023, 12, 28);
const int _thu = 3;

/// 고정 금요일을 오늘로 두고, 픽스처로 시드한 데모 DB 위의 저장소.
Future<ExerciseRepository> _repo() async => (await _demo()).repository;

Future<({LocalApiInterceptor api, ExerciseRepository repository})>
_demo() async {
  useFixedKstDate(_friday);
  final backend = demoExerciseBackend(await seededDemoDatabase());
  return (api: backend.api, repository: backend.repository);
}

Future<ExerciseSession> _add(
  ExerciseRepository r,
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
      final ExerciseRepository r = await _repo();
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
      final ExerciseRepository r = await _repo();
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
      final ExerciseRepository r = await _repo();
      final DateTime twoWeeksAgo = DateTime(2023, 12, 20);
      final ExerciseSession added = await _add(r, twoWeeksAgo);

      expect(_has(await r.fetchWeek(DateTime(2023, 12, 18)), added.id), isTrue);
      expect(_has(await r.fetchWeek(_lastMonday), added.id), isFalse);
      expect(_has(await r.fetchThisWeek(), added.id), isFalse);
    });

    test('이번 주 날짜는 지금처럼 이번 주에 들어간다', () async {
      final ExerciseRepository r = await _repo();
      final ExerciseWeek before = await r.fetchThisWeek();
      final ExerciseSession added = await _add(r, _thisMonday);

      final ExerciseWeek after = await r.fetchThisWeek();
      expect(_has(after, added.id), isTrue);
      expect(after.totalCalories, before.totalCalories + added.calories);
      expect(_has(await r.fetchWeek(_lastMonday), added.id), isFalse);
    });
  });

  group('수정으로 주를 옮긴다', () {
    test('이번 주 기록을 지난 주로 옮기면 이번 주에서 빠지고 지난 주에 들어간다', () async {
      final ExerciseRepository r = await _repo();
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
      final ExerciseRepository r = await _repo();
      final ExerciseWeek thisBefore = await r.fetchThisWeek();
      final ExerciseSession added = await _add(r, _lastThursday);

      final ExerciseSession moved = await r.updateSession(
        id: added.id!,
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 90,
        date: _thisMonday,
        name: '데모 기록',
      );

      final ExerciseWeek thisAfter = await r.fetchThisWeek();
      expect(_has(thisAfter, added.id), isTrue);
      expect(
        thisAfter.totalCalories,
        thisBefore.totalCalories + moved.calories,
      );
      expect(_has(await r.fetchWeek(_lastMonday), added.id), isFalse);
    });

    test('같은 지난 주 안에서 고치면 제자리에서 바뀐다', () async {
      final ExerciseRepository r = await _repo();
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
      final ExerciseRepository r = await _repo();
      final ExerciseWeek before = await r.fetchWeek(_lastMonday);
      final ExerciseSession added = await _add(r, _lastThursday);

      await r.deleteSession(added.id!);

      final ExerciseWeek after = await r.fetchWeek(_lastMonday);
      expect(_has(after, added.id), isFalse);
      expect(after.dailyMinutes, before.dailyMinutes);
    });

    test('지난 주 기록을 지워도 이번 주 헤드라인 칼로리는 그대로다', () async {
      final ExerciseRepository r = await _repo();
      final ExerciseWeek before = await r.fetchThisWeek();
      final ExerciseSession added = await _add(r, _lastThursday);
      await r.deleteSession(added.id!);

      expect((await r.fetchThisWeek()).totalCalories, before.totalCalories);
    });
  });

  group('지난 주를 읽는 다른 자리들', () {
    test('fetchPeriod 의 지난 주 칸에도 들어간다', () async {
      final ExerciseRepository r = await _repo();
      // 기간 조회는 그래프용 요약만 싣는다(실서버 `/exercise/weeks` 와 같다) —
      // 기록 목록이 아니라 그 주 그날의 분이 늘었는지로 본다.
      Future<ExerciseWeek> lastWeekOfPeriod() async => (await r.fetchPeriod(
        from: _lastMonday,
        to: _friday,
      )).firstWhere((ExercisePeriodWeek w) => w.weekStart == _lastMonday).week;
      final ExerciseWeek before = await lastWeekOfPeriod();

      await _add(r, _lastThursday, minutes: 35);

      final ExerciseWeek after = await lastWeekOfPeriod();
      expect(after.dailyMinutes[_thu], before.dailyMinutes[_thu] + 35);
      expect(after.totalMinutes, before.totalMinutes + 35);
    });

    test('배정 루틴 완료를 지난 날짜로 남겨도 그 주에 들어가고 되돌리면 빠진다', () async {
      final demo = await _demo();
      final ExerciseRepository r = demo.repository;
      final ExerciseSession done = await demo.api.addAssignedRoutineSession(
        type: ExerciseType.stretching,
        minutes: 10,
        calories: 30,
        date: _lastThursday,
        routineId: 'routine-1',
        name: '폼롤러',
      );
      expect(_has(await r.fetchWeek(_lastMonday), done.id), isTrue);
      expect(_has(await r.fetchThisWeek(), done.id), isFalse);

      await demo.api.removeAssignedRoutineSession(done.id!);
      expect(_has(await r.fetchWeek(_lastMonday), done.id), isFalse);
    });
  });
}

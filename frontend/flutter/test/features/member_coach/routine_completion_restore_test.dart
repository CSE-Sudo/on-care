/// 새로고침해도 추천 개인운동 체크가 수행 기록과 함께 남는다. (#2662)
///
/// 데모의 체크는 목업 코치 저장소의 메모리에, 수행 기록은 로컬 목업 API(drift)에
/// 남는다. 새로고침은 코치 저장소를 새로 만드는 일이라, 체크를 기록에서 되살리지
/// 않으면 운동 현황은 30분을 말하는데 목록은 미완료로 보이고, 다시 체크하면 같은
/// 기록이 하나 더 생긴다. 실서버는 완료를 저장하므로 새로고침해도 체크가 남는다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

void main() {
  late AppDatabase db;
  late LocalApiInterceptor api;
  late String routineId;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = LocalApiInterceptor(db, Logger(level: Level.off));
    routineId = DemoFixture.load().routines.first.id;
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<ExerciseSessionRow>> routineRows() => (db.select(
    db.exerciseSessions,
  )..where((t) => t.source.equals('assigned_routine'))).get();

  CoachRoutine routineOf(List<CoachRoutine> list) =>
      list.firstWhere((CoachRoutine r) => r.id == routineId);

  test('새로고침한 뒤에도 오늘 한 체크가 남는다', () async {
    await MockMemberCoachRepository(
      exercise: api,
    ).completeRoutine(routineId, minutes: 30);

    // 새로고침 — 코치 저장소만 새로 만들어진다. 기록은 drift 에 남아 있다.
    final MockMemberCoachRepository refreshed = MockMemberCoachRepository(
      exercise: api,
    );
    final CoachRoutine routine = routineOf(await refreshed.fetchRoutines());

    expect(routine.completed, isTrue);
    expect(routine.completedMinutes, 30);
  });

  test('새로고침한 뒤 다시 체크해도 기록이 늘지 않는다', () async {
    await MockMemberCoachRepository(
      exercise: api,
    ).completeRoutine(routineId, minutes: 30);
    expect(await routineRows(), hasLength(1));

    await MockMemberCoachRepository(
      exercise: api,
    ).completeRoutine(routineId, minutes: 30);

    expect(await routineRows(), hasLength(1));
  });

  test('새로고침한 뒤 체크를 풀면 그 기록이 지워진다', () async {
    await MockMemberCoachRepository(
      exercise: api,
    ).completeRoutine(routineId, minutes: 30);

    final MockMemberCoachRepository refreshed = MockMemberCoachRepository(
      exercise: api,
    );
    await refreshed.uncompleteRoutine(routineId);

    expect(await routineRows(), isEmpty);
    expect(routineOf(await refreshed.fetchRoutines()).completed, isFalse);
  });
}

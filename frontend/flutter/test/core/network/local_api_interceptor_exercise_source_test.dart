import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/demo/period_advice.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

/// 데모 운동이 drift 에 남으면서(#2662) 로컬 목업 API 가 맡게 된 일 — 기록의
/// 출처, 파생 기록 잠금, 루틴 완료 기록, 조언의 추천 개인운동.
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _thisMonday() {
  final DateTime now = nowKst();
  return _ymd(DateTime(now.year, now.month, now.day - (now.weekday - 1)));
}

const List<String> _labels = <String>['월', '화', '수', '목', '금', '토', '일'];

void main() {
  late AppDatabase db;
  late Dio dio;
  late LocalApiInterceptor api;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = LocalApiInterceptor(db, Logger(level: Level.off));
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..interceptors.add(api);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<Map<String, Object?>>> sessions() async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/exercise/weeks/current');
    return (res.data!['sessions']! as List<Object?>)
        .cast<Map<String, Object?>>();
  }

  Future<void> insertPt() async {
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'seed-ex-pt',
            weekStart: _thisMonday(),
            dayLabel: _labels[nowKst().weekday - 1],
            type: 'strength',
            minutes: 50,
            calories: 300,
            name: const Value('레그프레스'),
            source: const Value('trainer_pt'),
          ),
        );
  }

  test('주간 응답이 기록의 출처를 싣는다', () async {
    await insertPt();

    final Map<String, Object?> pt = (await sessions()).single;
    expect(pt['source'], 'trainer_pt');
    expect(
      ExerciseSession.fromJson(pt).isEditable,
      isFalse,
      reason: 'PT 기록이 `직접 추가한 운동` 에 서면 안 된다',
    );
  });

  test('PT·배정 루틴 기록은 고치거나 지울 수 없다 — 서버와 같은 409', () async {
    await insertPt();

    // 인터셉터는 409 를 응답으로 돌려준다 — 예외로 오든 응답으로 오든 상태만 본다.
    Future<int?> status(Future<Response<Object?>> call) async {
      try {
        return (await call).statusCode;
      } on DioException catch (e) {
        return e.response?.statusCode;
      }
    }

    expect(await status(dio.delete<Object?>('/exercise/sessions/seed-ex-pt')), 409);
    expect(
      await status(
        dio.put<Object?>(
          '/exercise/sessions/seed-ex-pt',
          data: <String, Object?>{'type': 'cardio', 'minutes': 10},
        ),
      ),
      409,
    );
    final Map<String, Object?> kept = (await sessions()).single;
    expect(kept['minutes'], 50);
    expect(kept['type'], 'strength');
  });

  test('루틴 완료 기록이 같은 표에 남고 되돌리면 지워진다', () async {
    final ExerciseSession done = await api.addAssignedRoutineSession(
      type: ExerciseType.cardio,
      minutes: 20,
      calories: 0,
      date: nowKst(),
      routineId: 'routine-1',
      name: '빠르게 걷기',
    );
    expect(done.source, ExerciseSource.assignedRoutine);
    expect(done.assignedRoutineId, 'routine-1');

    final Map<String, Object?> row = (await sessions()).single;
    expect(row['id'], done.id);
    expect(row['source'], 'assigned_routine');
    expect(row['assigned_routine_id'], 'routine-1');
    expect(row['assigned_routine_name'], '빠르게 걷기');

    await api.removeAssignedRoutineSession(done.id!);
    expect(await sessions(), isEmpty);
  });

  test('루틴 완료 되돌리기는 회원이 적은 기록을 지우지 않는다', () async {
    final Response<Map<String, Object?>> res = await dio
        .post<Map<String, Object?>>(
          '/exercise/sessions',
          data: <String, Object?>{
            'sessions': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'cardio',
                'name': '줄넘기',
                'minutes': 10,
                'date': _ymd(nowKst()),
              },
            ],
          },
        );
    final String id =
        ((res.data!['sessions']! as List<Object?>).single!
                as Map<String, Object?>)['id']!
            as String;

    await api.removeAssignedRoutineSession(id);
    expect((await sessions()).single['source'], 'member');
  });

  test('조언이 추천 개인운동을 서버와 같은 구간으로 읽는다 (#2162)', () async {
    DateTime? asked;
    api.routineDays = (DateTime from, DateTime to) {
      asked = from;
      return const <RoutineAdviceDay>[];
    };

    await dio.get<Object?>(
      '/exercise/advice',
      queryParameters: <String, Object?>{'period': kPeriodWeek},
    );

    final DateTime now = nowKst();
    expect(
      asked,
      routineAdviceFetchStart(
        kPeriodWeek,
        DateTime(now.year, now.month, now.day),
      ),
    );
  });

  test('시드 운동 기록은 PT·배정 루틴 출처를 든다', () async {
    await seedIfEmpty(db);

    final List<ExerciseSessionRow> rows = await db
        .select(db.exerciseSessions)
        .get();
    expect(rows, isNotEmpty);
    expect(
      rows.map((ExerciseSessionRow r) => r.source),
      everyElement(isIn(<String>['trainer_pt', 'assigned_routine'])),
      reason: '픽스처에는 회원이 손으로 적은 기록이 없다',
    );
    expect(
      rows.map((ExerciseSessionRow r) => r.source),
      contains('trainer_pt'),
    );
  });
}

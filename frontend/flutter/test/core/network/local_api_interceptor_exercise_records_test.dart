/// 데모 주간 목록도 직접 기록한 운동에 개인 기록 태그를 싣는다(#3099).
///
/// 실서버 `exercise_records.personal_records`(#2971)와 같은 규칙이다 — 사례도
/// `backend/tests/test_exercise_records.py` 에서 옮겼다. 데모 응답에 `record` 가
/// 없으면 운동 목록의 `최고 중량`·`최장 시간` 태그가 데모에서만 뜨지 않는다.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare_core/clock.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const List<String> _labels = <String>['월', '화', '수', '목', '금', '토', '일'];

void main() {
  late AppDatabase db;
  late Dio dio;
  int seq = 0;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
  });

  /// [daysAgo] 일 전 기록 한 건. 같은 날 기록은 [order] 순서로 저장한 것으로 둔다.
  Future<String> insert({
    required String type,
    required String name,
    int daysAgo = 0,
    int minutes = 12,
    double? weight,
    int order = 0,
    String source = 'member',
  }) async {
    final DateTime now = nowKst();
    final DateTime day = DateTime(now.year, now.month, now.day - daysAgo);
    final DateTime monday = DateTime(
      day.year,
      day.month,
      day.day - (day.weekday - 1),
    );
    final String id = 'rec-${++seq}';
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: id,
            weekStart: _ymd(monday),
            dayLabel: _labels[day.weekday - 1],
            type: type,
            minutes: minutes,
            calories: 100,
            name: Value(name),
            weight: Value(weight),
            durationSeconds: Value(minutes * 60),
            source: Value(source),
            createdAt: Value(DateTime(2026, 1, 1, 0, 0, order)),
          ),
        );
    return id;
  }

  Future<String> bench(
    double weight, {
    int daysAgo = 0,
    int order = 0,
    String name = '벤치프레스',
  }) => insert(
    type: 'strength',
    name: name,
    weight: weight,
    daysAgo: daysAgo,
    order: order,
  );

  Future<String> run(int minutes, {int daysAgo = 0, int order = 0}) => insert(
    type: 'cardio',
    name: '아침 러닝',
    minutes: minutes,
    daysAgo: daysAgo,
    order: order,
  );

  Future<Map<String, Object?>> session(String id) async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/exercise/weeks/current');
    return (res.data!['sessions']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((Map<String, Object?> s) => s['id'] == id);
  }

  Future<Object?> recordOf(String id) async => (await session(id))['record'];

  test('이름으로 처음 적은 운동은 first 다', () async {
    final String id = await bench(40);
    expect(await recordOf(id), 'first');
  });

  test('같은 근력 운동을 20kg → 25kg 로 들면 둘째가 max_weight 다', () async {
    final String first = await bench(20, order: 1);
    final String second = await bench(25, order: 2);
    expect(await recordOf(first), 'first');
    expect(await recordOf(second), 'max_weight');
  });

  test('같거나 가벼운 중량은 태그가 없다', () async {
    await bench(50, order: 1);
    final String tie = await bench(50, order: 2);
    final String lighter = await bench(45, order: 3);
    expect(await recordOf(tie), isNull);
    expect(await recordOf(lighter), isNull);
  });

  test('유산소 30분 → 40분이면 둘째가 longest 다', () async {
    await run(30, order: 1);
    final String id = await run(40, order: 2);
    expect(await recordOf(id), 'longest');
  });

  test('띄어쓰기·대소문자만 다른 이름은 같은 운동이다', () async {
    await bench(60, order: 1, name: '벤치 프레스');
    final String id = await bench(55, order: 2);
    expect(await recordOf(id), isNull);
    await bench(30, order: 3, name: 'Bench Press');
    final String lower = await bench(35, order: 4, name: 'benchpress');
    expect(await recordOf(lower), 'max_weight');
  });

  test('지난주 기록도 견준다', () async {
    await run(50, daysAgo: 8);
    final String id = await run(40);
    expect(await recordOf(id), isNull);
  });

  test('PT·배정 루틴 기록에는 태그가 없고 견줄 기록으로도 세지 않는다', () async {
    final String pt = await insert(
      type: 'strength',
      name: '벤치프레스',
      weight: 80,
      source: 'trainer_pt',
      order: 1,
    );
    final String routine = await insert(
      type: 'cardio',
      name: '아침 러닝',
      minutes: 90,
      source: 'assigned_routine',
      order: 1,
    );
    final String mine = await bench(40, order: 2);
    expect(await recordOf(pt), isNull);
    expect(await recordOf(routine), isNull);
    expect(await recordOf(mine), 'first');
  });

  test('생성 응답은 서버처럼 record 키를 null 로 싣는다', () async {
    final Response<Map<String, Object?>> res = await dio
        .post<Map<String, Object?>>(
          '/exercise/sessions',
          data: <String, Object?>{
            'sessions': <Map<String, Object?>>[
              <String, Object?>{'type': 'cardio', 'name': '걷기', 'minutes': 20},
            ],
          },
        );
    final Map<String, Object?> created =
        ((res.data!['sessions']! as List<Object?>).single!
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    expect(created.containsKey('record'), isTrue);
    expect(created['record'], isNull);
  });
}

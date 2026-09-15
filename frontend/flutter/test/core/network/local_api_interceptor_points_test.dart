/// 목업 API 의 포인트 적립 — 실서버와 같은 규칙. (#1786)
///
/// 식단 +50P(하루 3회), 운동 직접 추가 +20P(하루 3회), 같은 기록은 한 번만,
/// 지우면 회수. 잔액은 `/users/me/health` 로 읽는다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      LocalApiInterceptor(
        db,
        Logger(level: Level.off),
        points: DemoPointsLedger(),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<Map<String, Object?>> analyze({String? key}) async {
    final FormData form = FormData.fromMap(<String, Object?>{
      'image': MultipartFile.fromBytes(<int>[1, 2, 3, 4], filename: 'meal.jpg'),
      'meal_type': 'lunch',
      'idempotency_key': ?key,
    });
    final Response<Map<String, Object?>> res = await dio
        .post<Map<String, Object?>>('/diet/analyze', data: form);
    return res.data!;
  }

  Future<Map<String, Object?>> addExercise() async {
    final Response<Map<String, Object?>> res = await dio
        .post<Map<String, Object?>>(
          '/exercise/sessions',
          data: <String, Object?>{
            'type': 'cardio',
            'name': '걷기',
            'minutes': 20,
            'calories': 0,
          },
        );
    return res.data!;
  }

  Map<String, Object?> points(Map<String, Object?> body) =>
      body['points']! as Map<String, Object?>;

  Future<int> balance() async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/users/me/health');
    return (res.data!['activity_points']! as num).toInt();
  }

  test('식단 기록은 +50P 를 하루 3회까지 받고 잔액이 따라 오른다', () async {
    final List<Map<String, Object?>> results = <Map<String, Object?>>[
      for (int i = 0; i < 4; i++) points(await analyze()),
    ];

    expect(
      results.map((Map<String, Object?> p) => p['awarded']).toList(),
      <int>[50, 50, 50, 0],
    );
    expect(results.last['balance'], 1240 + 150);
    expect(await balance(), 1240 + 150);
  });

  test('운동 직접 추가는 +20P 를 하루 3회까지 받는다', () async {
    final List<Object?> awarded = <Object?>[
      for (int i = 0; i < 4; i++) points(await addExercise())['awarded'],
    ];

    expect(awarded, <int>[20, 20, 20, 0]);
    expect(await balance(), 1240 + 60);
  });

  test('같은 멱등키로 다시 보내도 한 번만 적립하고 같은 값을 돌려준다', () async {
    final Map<String, Object?> first = await analyze(key: 'retry-1');
    final Map<String, Object?> retried = await analyze(key: 'retry-1');

    expect(retried['entry_id'], first['entry_id']);
    expect(points(retried), <String, Object?>{
      'awarded': 50,
      'balance': 1290,
    });
    expect(await balance(), 1290);
  });

  test('식단을 지우면 적립을 회수하고 그날 한도가 풀린다', () async {
    final List<String> ids = <String>[
      for (int i = 0; i < 3; i++) (await analyze())['entry_id']! as String,
    ];

    final Response<Object?> deleted = await dio.delete<Object?>(
      '/diet/entries/${ids.first}',
    );
    expect(deleted.statusCode, 200);
    expect(await balance(), 1240 + 100);

    expect(points(await analyze())['awarded'], 50);
    expect(points(await analyze())['awarded'], 0);
  });

  test('운동 기록을 지우면 적립을 회수한다', () async {
    final String id = (await addExercise())['id']! as String;

    await dio.delete<Object?>('/exercise/sessions/$id');

    expect(await balance(), 1240);
  });

  test('운동 기록을 고쳐도 새로 적립하지 않는다', () async {
    final String id = (await addExercise())['id']! as String;

    final Response<Map<String, Object?>> updated = await dio
        .put<Map<String, Object?>>(
          '/exercise/sessions/$id',
          data: <String, Object?>{
            'type': 'cardio',
            'name': '걷기',
            'minutes': 40,
            'calories': 0,
          },
        );

    expect(updated.data!.containsKey('points'), isFalse);
    expect(await balance(), 1260);
  });
}

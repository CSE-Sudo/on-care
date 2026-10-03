/// 목업 API 의 운동 기록 추가 재시도 — 실서버와 같은 멱등 규칙. (#3095)
///
/// 같은 `client_request_id` 로 다시 오면 새로 넣거나 적립하지 않고 처음 결과를
/// 돌려주고, 목록이 다르면 409 다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare_core/clock.dart';

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
        points: DemoPointsLedger(openingBalance: 1000),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  final DateTime now = nowKst();
  final String today =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  List<Map<String, Object?>> sessions({int sets = 3}) => <Map<String, Object?>>[
    <String, Object?>{
      'type': 'cardio',
      'name': '러닝머신',
      'duration_seconds': 1800,
      'date': today,
    },
    <String, Object?>{
      'type': 'strength',
      'name': '스쿼트',
      'minutes': 12,
      'sets': sets,
      'reps': 10,
      'weight': 20,
      'date': today,
    },
  ];

  Future<Response<Map<String, Object?>>> add(
    List<Map<String, Object?>> items, {
    String? key,
  }) => dio.post<Map<String, Object?>>(
    '/exercise/sessions',
    data: <String, Object?>{'sessions': items, 'client_request_id': ?key},
    options: Options(validateStatus: (_) => true),
  );

  List<Object?> idsOf(Response<Map<String, Object?>> r) => <Object?>[
    for (final Object? s in r.data!['sessions']! as List<Object?>)
      (s! as Map<String, Object?>)['id'],
  ];

  Future<int> rowCount() async =>
      (await db.select(db.exerciseSessions).get()).length;

  test('같은 키 재전송은 처음 응답을 돌려주고 새로 적립하지 않는다', () async {
    final first = await add(sessions(), key: 'k-1');
    expect(first.statusCode, lessThan(300));
    final Map<String, Object?> points =
        first.data!['points']! as Map<String, Object?>;
    expect(points['awarded'], greaterThan(0));

    final retry = await add(sessions(), key: 'k-1');
    expect(retry.statusCode, lessThan(300));
    expect(idsOf(retry), idsOf(first));
    expect(retry.data!['points'], points);
    expect(await rowCount(), 2);
  });

  test('같은 키에 다른 목록은 409 이고 아무것도 바뀌지 않는다', () async {
    final first = await add(sessions(), key: 'k-2');
    final Object? balance =
        (first.data!['points']! as Map<String, Object?>)['balance'];

    for (final List<Map<String, Object?>> changed
        in <List<Map<String, Object?>>>[
          sessions(sets: 4),
          sessions().sublist(0, 1),
        ]) {
      final r = await add(changed, key: 'k-2');
      expect(r.statusCode, 409);
    }
    expect(await rowCount(), 2);
    final again = await add(sessions(), key: 'k-2');
    expect(
      (again.data!['points']! as Map<String, Object?>)['balance'],
      balance,
    );
  });

  test('키가 없으면 지금처럼 매번 저장한다', () async {
    await add(sessions());
    await add(sessions());
    expect(await rowCount(), 4);
  });

  test('그 키의 기록이 모두 지워졌으면 새로 저장한다', () async {
    final first = await add(sessions(), key: 'k-3');
    for (final Object? id in idsOf(first)) {
      await dio.delete<Object?>('/exercise/sessions/$id');
    }
    final again = await add(sessions(), key: 'k-3');
    expect(again.statusCode, lessThan(300));
    expect(idsOf(again).toSet().intersection(idsOf(first).toSet()), isEmpty);
    expect(await rowCount(), 2);
  });

  test('일부만 지워졌으면 409 다', () async {
    final first = await add(sessions(), key: 'k-4');
    await dio.delete<Object?>('/exercise/sessions/${idsOf(first).first}');
    final r = await add(sessions(), key: 'k-4');
    expect(r.statusCode, 409);
    expect(await rowCount(), 1);
  });
}

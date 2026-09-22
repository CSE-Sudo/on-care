/// 목업 API 의 식단 직접 추가(POST /diet/entries) — 실서버와 같은 규칙. (#2151)
///
/// 합계는 음식에서 내고, 출처가 빠진 음식은 회원 값이며, 포인트는 적립하지 않는다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/utils/clock.dart';

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
        points: DemoPointsLedger(openingBalance: 1240),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  String wire(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  final DateTime now = nowKst();
  final String today = wire(DateTime(now.year, now.month, now.day));

  Future<Response<Map<String, Object?>>> create(Map<String, Object?> body) =>
      dio.post<Map<String, Object?>>(
        '/diet/entries',
        data: body,
        options: Options(validateStatus: (_) => true),
      );

  const List<Map<String, Object?>> foods = <Map<String, Object?>>[
    <String, Object?>{
      'name': '김밥',
      'calories': 420,
      'carbs_g': 70,
      'protein_g': 12,
      'fat_g': 9,
      'sodium_mg': 900,
      'sugar_g': 4,
      'source': 'db',
    },
    <String, Object?>{
      'name': '라면',
      'calories': 500,
      'carbs_g': 80,
      'sodium_mg': 1800,
      'sugar_g': 3,
    },
  ];

  test('끼니를 저장하고 합계는 음식에서 낸다', () async {
    final res = await create(<String, Object?>{
      'date': today,
      'meal_type': 'lunch',
      'foods': foods,
    });
    expect(res.statusCode, 201);
    final Map<String, Object?> entry = res.data!;
    expect(entry['total_calories'], 920);
    expect(entry['sodium_mg'], 2700);
    expect(entry['carbs_g'], 150);
    expect(entry['photo_url'], isNull);
    final List<Object?> saved = entry['foods']! as List<Object?>;
    expect(
      saved.map((Object? f) => (f! as Map<Object?, Object?>)['source']),
      <String>['db', 'member'],
    );

    final day = await dio.get<Map<String, Object?>>('/diet/days/today');
    final List<Object?> entries = day.data!['entries']! as List<Object?>;
    expect(
      entries.map((Object? e) => (e! as Map<Object?, Object?>)['id']),
      contains(entry['id']),
    );
  });

  test('포인트는 적립하지 않는다', () async {
    await create(<String, Object?>{
      'date': today,
      'meal_type': 'lunch',
      'foods': foods,
    });
    final health = await dio.get<Map<String, Object?>>('/users/me/health');
    expect(health.data!['activity_points'], 1240);
  });

  test('같은 멱등키는 끼니를 하나만 만든다', () async {
    final Map<String, Object?> body = <String, Object?>{
      'date': today,
      'meal_type': 'dinner',
      'foods': foods,
      'idempotency_key': 'manual-1',
    };
    final first = await create(body);
    final second = await create(body);
    expect(first.data!['id'], second.data!['id']);
  });

  test('틀린 요청은 422', () async {
    final DateTime tomorrow = DateTime(now.year, now.month, now.day + 1);
    for (final Map<String, Object?> body in <Map<String, Object?>>[
      <String, Object?>{'meal_type': 'lunch', 'foods': <Object?>[]},
      <String, Object?>{
        'meal_type': 'lunch',
        'foods': <Object?>[
          <String, Object?>{'name': ' ', 'calories': 1},
        ],
      },
      <String, Object?>{'meal_type': 'brunch', 'foods': foods},
      <String, Object?>{
        'date': wire(tomorrow),
        'meal_type': 'lunch',
        'foods': foods,
      },
      <String, Object?>{
        'meal_type': 'snack',
        'foods': <Object?>[
          <String, Object?>{'name': '사탕', 'carbs_g': 0, 'sugar_g': 9},
        ],
      },
    ]) {
      expect((await create(body)).statusCode, 422, reason: '$body');
    }
  });
}

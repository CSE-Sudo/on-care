/// 데모 백엔드의 사진 분석이 실려 온 기록 날짜로 저장하는지. (#2849)
///
/// 실서버 `POST /diet/analyze` 의 선택 `date` 폼 필드와 같은 규칙이다 — 빠지면
/// 오늘, 앞날·작년 1월 1일보다 앞선 날·형식이 틀린 값은 422. 데모에서만
/// 통과하면 실연동에서 그 화면이 처음 실패한다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

import '../../helpers/fixed_clock.dart';

final Uint8List _jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    // 오늘은 2026-08-20(목).
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test',
        validateStatus: (int? _) => true,
      ),
    );
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() => db.close());

  Future<Response<Map<String, Object?>>> analyze({
    String? date,
    String mealType = 'lunch',
  }) => dio.post<Map<String, Object?>>(
    '/diet/analyze',
    data: FormData.fromMap(<String, Object?>{
      'image': MultipartFile.fromBytes(_jpeg, filename: 'meal.jpg'),
      'meal_type': mealType,
      'date': ?date,
    }),
  );

  Future<List<Object?>> entriesOn(String day) async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/diet/days/$day');
    return res.data!['entries']! as List<Object?>;
  }

  test('지난 날짜를 실으면 그 날에 저장되고 오늘에는 없다', () async {
    final Response<Map<String, Object?>> res = await analyze(
      date: '2026-08-19',
    );
    expect(res.statusCode, 200);
    final String id = res.data!['entry_id']! as String;

    final List<Object?> yesterday = await entriesOn('2026-08-19');
    expect(
      yesterday.map((Object? e) => (e! as Map<String, Object?>)['id']),
      contains(id),
    );
    final List<Object?> today = await entriesOn('2026-08-20');
    expect(
      today.map((Object? e) => (e! as Map<String, Object?>)['id']),
      isNot(contains(id)),
    );
  });

  test('날짜를 싣지 않으면 오늘이다', () async {
    final Response<Map<String, Object?>> res = await analyze();
    expect(res.statusCode, 200);
    final List<Object?> today = await entriesOn('2026-08-20');
    expect(
      today.map((Object? e) => (e! as Map<String, Object?>)['id']),
      contains(res.data!['entry_id']),
    );
  });

  test('앞날은 422 — 먹지 않은 식사는 기록하지 않는다', () async {
    final Response<Map<String, Object?>> res = await analyze(
      date: '2026-08-21',
    );
    expect(res.statusCode, 422);
    expect(await entriesOn('2026-08-21'), isEmpty);
  });

  test('작년 1월 1일까지는 받고, 그보다 앞선 날은 422', () async {
    expect((await analyze(date: '2025-01-01')).statusCode, 200);
    expect((await analyze(date: '2024-12-31')).statusCode, 422);
  });

  test('형식이 틀린 날짜는 422', () async {
    expect((await analyze(date: '20260819')).statusCode, 422);
    expect((await analyze(date: 'yesterday')).statusCode, 422);
  });
}

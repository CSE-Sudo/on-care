/// 데모 API 의 음식 없는 사진 — 실서버처럼 끼니·포인트 없이 422 로 거절한다. (#2848)
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis_failure.dart';

void main() {
  late AppDatabase db;
  late Dio dio;
  late LocalApiInterceptor api;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    api = LocalApiInterceptor(
      db,
      Logger(level: Level.off),
      points: DemoPointsLedger(openingBalance: 1000),
    );
    dio.interceptors.add(api);
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<Response<Map<String, Object?>>> analyze({String? key}) {
    final FormData form = FormData.fromMap(<String, Object?>{
      'image': MultipartFile.fromBytes(<int>[1, 2, 3, 4], filename: 'desk.jpg'),
      'meal_type': 'lunch',
      'idempotency_key': ?key,
    });
    return dio.post<Map<String, Object?>>('/diet/analyze', data: form);
  }

  Future<int> balance() async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/users/me/health');
    return (res.data!['activity_points']! as num).toInt();
  }

  test('기본은 지금처럼 고정 식단을 인식해 저장한다', () async {
    final Response<Map<String, Object?>> res = await analyze();

    expect(res.statusCode, 200);
    expect(await db.select(db.dietEntries).get(), hasLength(1));
  });

  test('음식이 없는 사진은 422 no_food_detected — 끼니·포인트를 남기지 않는다', () async {
    api.demoPhotoHasFood = (Uint8List? _) => false;

    final DioException error = await analyze(key: 'k-empty').then<DioException>(
      (_) => fail('음식 없는 사진이 저장됐다'),
      onError: (Object e) => e as DioException,
    );

    expect(error.response?.statusCode, 422);
    final Map<String, Object?> detail =
        (error.response!.data! as Map<String, Object?>)['detail']!
            as Map<String, Object?>;
    expect(detail['code'], 'no_food_detected');
    expect(detail['message'], isA<String>());
    expect(await db.select(db.dietEntries).get(), isEmpty);
    expect(await balance(), 1000);
  });

  test('실서버와 같은 본문이라 저장소가 같은 거절로 읽는다', () async {
    api.demoPhotoHasFood = (Uint8List? _) => false;

    final DioException error = await analyze().then<DioException>(
      (_) => fail('음식 없는 사진이 저장됐다'),
      onError: (Object e) => e as DioException,
    );

    expect(
      DietAnalysisRejected.fromResponseData(error.response?.data)?.failure,
      DietAnalysisFailure.noFood,
    );
  });

  test('거절된 멱등키로 음식이 보이는 사진을 다시 보내면 그때 저장한다', () async {
    api.demoPhotoHasFood = (Uint8List? _) => false;
    await analyze(key: 'k-retry').then<void>((_) {}, onError: (Object _) {});

    api.demoPhotoHasFood = null;
    final Response<Map<String, Object?>> res = await analyze(key: 'k-retry');

    expect(res.statusCode, 200);
    expect(await db.select(db.dietEntries).get(), hasLength(1));
    expect(await balance(), 1050);
  });
}

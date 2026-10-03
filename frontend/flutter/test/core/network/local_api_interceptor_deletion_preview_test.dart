/// 목업 API 의 `GET /users/me/deletion-preview` — 실서버와 같은 모양. (#3006)
///
/// 포인트는 원장 잔액, 쿠폰은 사용 전(`issued`) 쿠폰 수다. 데모의 PT 예약·상담
/// 요청은 목 저장소가 들고 있어 여기서는 0 이고, 앱이 저장소에서 다시 센다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/account/domain/entities/account_deletion_preview.dart';

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

  Future<Map<String, Object?>> preview() async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/users/me/deletion-preview');
    expect(res.statusCode, 200);
    return res.data!;
  }

  test('실서버와 같은 네 칸을 준다', () async {
    final Map<String, Object?> body = await preview();
    expect(
      body.keys,
      unorderedEquals(<String>[
        'points',
        'active_coupons',
        'upcoming_reservations',
        'pending_consultations',
      ]),
    );
    expect(AccountDeletionPreview.fromJson(body).points, 1240);
  });

  test('포인트는 MY 카드가 보여 주는 잔액과 같다', () async {
    final Response<Map<String, Object?>> health = await dio
        .get<Map<String, Object?>>('/users/me/health');
    expect(
      (await preview())['points'],
      (health.data!['activity_points']! as num).toInt(),
    );
  });

  test('쿠폰은 쿠폰함의 사용 전 쿠폰 수다', () async {
    final Response<List<Object?>> coupons = await dio.get<List<Object?>>(
      '/me/coupons',
    );
    final int issued = coupons.data!
        .cast<Map<String, Object?>>()
        .where((Map<String, Object?> c) => c['status'] == 'issued')
        .length;
    expect((await preview())['active_coupons'], issued);
  });

  test('예약·상담 요청은 목 저장소 몫이라 0 이다', () async {
    final Map<String, Object?> body = await preview();
    expect(body['upcoming_reservations'], 0);
    expect(body['pending_consultations'], 0);
  });
}

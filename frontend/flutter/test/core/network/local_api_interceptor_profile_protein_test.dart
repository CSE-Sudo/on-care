/// 데모 백엔드의 프로필 응답도 실효 단백질 목표를 싣는다. (#2898)
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

import '../../helpers/fixed_clock.dart';

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    useFixedKstDate(DateTime(2026, 8, 20, 12));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>> profile() async =>
      (await dio.get<Map<String, Object?>>('/users/me/profile')).data!;

  Future<Map<String, Object?>> putGoals(Map<String, Object?> body) async =>
      (await dio.put<Map<String, Object?>>(
        '/users/me/health-goals',
        data: body,
      )).data!;

  test('개인 목표가 있으면 그 값이다', () async {
    final Map<String, Object?> me = await profile();
    expect(me['effective_daily_protein_g'], me['daily_protein_g']);
  });

  test('목표를 지우면 체중 × 1.2g — 데모 회원 72kg 은 86g', () async {
    final Map<String, Object?> me = await putGoals(<String, Object?>{
      'daily_protein_g': null,
    });
    expect(me['daily_protein_g'], isNull);
    expect(me['effective_daily_protein_g'], 86);
    expect((await profile())['effective_daily_protein_g'], 86);
  });

  test('새 목표를 저장하면 응답도 그 값이다', () async {
    final Map<String, Object?> me = await putGoals(<String, Object?>{
      'daily_protein_g': 140,
    });
    expect(me['effective_daily_protein_g'], 140);
  });
}

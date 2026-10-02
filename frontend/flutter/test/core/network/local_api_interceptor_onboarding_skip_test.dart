/// 데모 경로의 첫 설정 건너뛰기 — 실서버 `POST /users/me/onboarding/skip` 과
/// 같은 응답을 낸다. (#2855)
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  /// 가입 직후처럼 첫 설정을 끝내지 않은 데모 계정.
  Future<void> freshAccount() => db.putValue(
    'profile_overlay',
    jsonEncode(<String, Object?>{'onboarded': false}),
  );

  test('기본 데모 프로필은 건너뛰지 않은 계정이다', () async {
    final res = await dio.get<Map<String, Object?>>('/users/me/profile');

    expect(res.data!['onboarding_skipped'], false);
  });

  test('건너뛰기는 표시만 남기고 끝낸 계정으로 바꾸지 않는다', () async {
    await freshAccount();

    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding/skip',
    );

    expect(res.statusCode, 200);
    expect(res.data!['onboarding_skipped'], true);
    expect(res.data!['onboarded'], false);

    // 다음 진입의 프로필에도 남는다.
    final prof = await dio.get<Map<String, Object?>>('/users/me/profile');
    expect(prof.data!['onboarding_skipped'], true);
    expect(prof.data!['onboarded'], false);
  });

  test('건너뛴 뒤 첫 설정을 저장하면 끝낸 계정이 된다', () async {
    await freshAccount();
    await dio.post<Map<String, Object?>>('/users/me/onboarding/skip');

    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      data: <String, Object?>{'height_cm': 170},
    );

    expect(res.data!['onboarded'], true);
    expect(res.data!['height_cm'], 170);
  });

  test('건너뛰기는 이름·생년월일 같은 값을 건드리지 않는다', () async {
    final before = await dio.get<Map<String, Object?>>('/users/me/profile');

    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding/skip',
    );

    expect(res.data!['name'], before.data!['name']);
    expect(res.data!['birth_date'], before.data!['birth_date']);
    expect(res.data!['conditions'], before.data!['conditions']);
  });
}

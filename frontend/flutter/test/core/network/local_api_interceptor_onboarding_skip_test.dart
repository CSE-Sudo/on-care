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

  // ---- 건너뛴 뒤 다시 연 첫 설정 (#3339) ----
  //
  // 앱은 바꾼 칸만 보낸다. 데모 경로도 실서버처럼 보내지 않은 칸을 그대로 둬야
  // MY 에서 정한 목표와 적혀 있던 주의사항이 남는다.

  /// 건너뛴 뒤 MY 에서 목표를 정한 데모 계정.
  Future<void> skippedWithGoals() async {
    await freshAccount();
    await dio.post<Map<String, Object?>>('/users/me/onboarding/skip');
    await dio.put<Map<String, Object?>>(
      '/users/me/health-goals',
      data: <String, Object?>{
        'conditions': '재활, 왼쪽 무릎 수술 이력',
        'daily_calories': 1800,
        'daily_sodium_mg': 1900,
        'weekly_cardio_minutes': 90,
      },
    );
  }

  test('다시 연 첫 설정은 보내지 않은 칸을 그대로 둔다', () async {
    await skippedWithGoals();

    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      data: <String, Object?>{'daily_sodium_mg': 1500},
    );

    expect(res.data!['onboarded'], true);
    expect(res.data!['daily_sodium_mg'], 1500);
    expect(res.data!['daily_calories'], 1800);
    expect(res.data!['weekly_cardio_minutes'], 90);
    expect(res.data!['conditions'], '재활, 왼쪽 무릎 수술 이력');
  });

  test('바꾼 것 없이 끝내면 끝냈다는 표시만 남는다', () async {
    await skippedWithGoals();
    final before = await dio.get<Map<String, Object?>>('/users/me/profile');

    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      data: <String, Object?>{},
    );

    expect(res.data!['onboarded'], true);
    for (final String key in <String>[
      'conditions',
      'daily_calories',
      'daily_sodium_mg',
      'weekly_cardio_minutes',
      'focus_changed_at',
      'notes_changed_at',
    ]) {
      expect(res.data![key], before.data![key], reason: key);
    }
  });

  test('목표 칩만 바꾼 저장은 주의사항 기록을 다시 찍지 않는다', () async {
    await skippedWithGoals();
    final before = await dio.get<Map<String, Object?>>('/users/me/profile');

    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      data: <String, Object?>{'conditions': '근력 향상, 재활, 왼쪽 무릎 수술 이력'},
    );

    expect(res.data!['conditions'], '근력 향상, 재활, 왼쪽 무릎 수술 이력');
    expect(res.data!['notes_changed_at'], before.data!['notes_changed_at']);
  });

  test('다시 연 첫 설정이 비운 목표는 건강 목표 저장의 null 로 해제된다', () async {
    await skippedWithGoals();
    await dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      data: <String, Object?>{},
    );

    final res = await dio.put<Map<String, Object?>>(
      '/users/me/health-goals',
      data: <String, Object?>{'daily_sodium_mg': null},
    );

    expect(res.data!['daily_sodium_mg'], isNull);
    expect(res.data!['daily_calories'], 1800);
  });
}

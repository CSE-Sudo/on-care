import 'dart:io';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

/// End-to-end smoke test for Stage 9: drift seeded → dio → LocalApi
/// interceptor → JSON → fromJson factory. If any of these layers
/// drift apart, this lights up first.
void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db); // production seed path
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  test('dio → LocalApi → DietDay.fromJson round-trips totals', () async {
    final res = await dio.get<Map<String, Object?>>('/diet/days/today');
    final day = DietDay.fromJson(res.data!);
    // 오늘 저녁은 데모 시연(사진으로 저녁 기록)을 위해 비워 둔다 (#548).
    expect(day.entries.length, 3);
    expect(
      day.entries.every((entry) => entry.mealType != MealType.dinner),
      isTrue,
    );
    expect(day.totalCalories, 1054);
    expect(day.totalSodiumMg, 4657);
    expect(day.totalSugarG, closeTo(16.7, 0.001));
    expect(day.macros.carbsG, closeTo(111.6, 0.001));
    expect(day.macros.proteinG, closeTo(54.4, 0.001));
    expect(day.macros.fatG, closeTo(34.1, 0.001));
    expect(
      <int>[day.macros.carbsPct, day.macros.proteinPct, day.macros.fatPct],
      <int>[46, 22, 32],
    );
    final pastRes = await dio.get<Map<String, Object?>>(
      '/diet/days/${_daysAgoString(2)}',
    );
    final pastDay = DietDay.fromJson(pastRes.data!);
    expect(
      pastDay.entries
          .firstWhere((entry) => entry.mealType == MealType.dinner)
          .photoAsset,
      'assets/images/diet-salmon-brown-rice.jpeg',
    );
  });

  test('dio → LocalApi → ExerciseWeek.fromJson stays Mon..Sun', () async {
    final res = await dio.get<Map<String, Object?>>('/exercise/weeks/current');
    final week = ExerciseWeek.fromJson(res.data!);
    expect(week.dailyMinutes.length, 7);
    expect(week.dayLabels, <String>['월', '화', '수', '목', '금', '토', '일']);
    // 합계는 픽스처가 정한다(#757). 여기 숫자를 적어 두면 요일마다 달라지는 값을
    // 고정하게 되고(이번 주는 오늘까지만 시드된다), 픽스처를 고칠 때마다 깨진다.
    final DateTime now = nowKst();
    final String monday = _dateString(
      DateTime(now.year, now.month, now.day - (now.weekday - 1)),
    );
    final int expectedMinutes = DemoFixture.parse(
      File('../../shared/demo_fixture/assets/kim_minsu.json').readAsStringSync(),
    ).daysFor(now).where((FixtureDay d) => d.weekStart == monday).fold<int>(
      0,
      (int sum, FixtureDay d) =>
          sum +
          d.doneExercises.fold<int>(
            0,
            (int m, FixtureExercise e) => m + e.minutes,
          ),
    );
    expect(week.totalMinutes, expectedMinutes);
    expect(expectedMinutes, greaterThan(0), reason: '이번 주 운동이 하나도 없으면 검증이 빈다');
    // 홈 '주간 추이' 차트가 데모 상수로 폴백하지 않도록 일별 칼로리도 내려준다.
    expect(week.dailyCalories.length, 7);
    expect(week.dailyCalories.reduce((a, b) => a + b), week.totalCalories);
    // 운동한 요일 수 == 분이 0보다 큰 요일 수.
    expect(
      week.workoutCount,
      week.dailyMinutes.where((double m) => m > 0).length,
    );
  });

  test('근력 세트는 픽스처가 적은 값 그대로다 (#1265)', () async {
    // 예전에는 시드가 픽스처의 `sets` 를 버려서, 화면이 분에서 세트를 되짚었다 —
    // 회원 앱과 트레이너 웹이 같은 날 근력을 다른 수로 말했다. 기대값은 여기
    // 적지 않고 픽스처에서 계산한다.
    final DateTime now = nowKst();
    final String monday = _dateString(
      DateTime(now.year, now.month, now.day - (now.weekday - 1)),
    );
    final DemoFixture fixture = DemoFixture.parse(
      File('../../shared/demo_fixture/assets/kim_minsu.json').readAsStringSync(),
    );
    final List<int> expected = List<int>.filled(7, 0);
    for (final FixtureDay day in fixture
        .daysFor(now)
        .where((FixtureDay d) => d.weekStart == monday)) {
      final int index = DateTime.parse(day.date).weekday - 1;
      for (final FixtureExercise e in day.doneExercises) {
        if (e.type == 'strength') expected[index] += e.sets ?? 0;
      }
    }
    expect(expected.reduce((int a, int b) => a + b), greaterThan(0));

    final res = await dio.get<Map<String, Object?>>('/exercise/weeks/current');
    expect(
      (res.data!['strength_sets']! as List<Object?>)
          .map((Object? v) => (v! as num).toInt())
          .toList(),
      expected,
    );
  });

  test('dio → LocalApi → DashboardSummary aggregates seeded data', () async {
    final res = await dio.get<Map<String, Object?>>('/dashboard/summary');
    final summary = DashboardSummary.fromJson(res.data!);
    final dietRes = await dio.get<Map<String, Object?>>('/diet/days/today');
    final todayDiet = DietDay.fromJson(dietRes.data!);
    // 혈당 row was removed from the home summary; indicator list now
    // ends at 당류 (calories / sodium / sugar).
    expect(summary.indicators.length, 3);
    final cal = summary.indicators.firstWhere((i) => i.label == '칼로리');
    final sodium = summary.indicators.firstWhere((i) => i.label == '나트륨');
    final sugar = summary.indicators.firstWhere((i) => i.label == '당류');
    expect(cal.current, todayDiet.totalCalories);
    expect(sodium.current, todayDiet.totalSodiumMg);
    expect(sugar.current, todayDiet.totalSugarG);
    expect(
      summary.indicators.any((i) => i.label == '혈당'),
      isFalse,
      reason: '혈당 row should no longer be in the home summary',
    );
    // 4 seeded meals (아침·점심·저녁·간식).
    expect(summary.dietEntries, todayDiet.entries.length);
    expect(summary.macros.carbsG, todayDiet.macros.carbsG);
    expect(summary.macros.proteinG, todayDiet.macros.proteinG);
    expect(summary.macros.fatG, todayDiet.macros.fatG);
    expect(summary.macros.carbsPct, todayDiet.macros.carbsPct);
    expect(summary.nutritionWeek, hasLength(7));
    final todayTrend = summary.nutritionWeek[nowKst().weekday - 1];
    expect(todayTrend.calories, todayDiet.totalCalories);
    expect(todayTrend.sodiumMg, todayDiet.totalSodiumMg);
    expect(todayTrend.sugarG, todayDiet.totalSugarG);
    // 시드가 큐레이션한 '통합 조언'이 동적 나트륨 경고 대신 노출된다. 문구가
    // 아니라 키로 내려와야 화면이 로케일에 맞게 고를 수 있다(#435).
    expect(summary.aiAdviceKey, kDailyCombinedAdviceKey);
    expect(summary.sodiumWarning, isNull);
  });
}

String _daysAgoString(int days) =>
    _dateString(nowKst().subtract(Duration(days: days)));

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

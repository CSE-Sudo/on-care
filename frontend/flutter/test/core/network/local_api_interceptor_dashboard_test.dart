import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/utils/clock.dart';

const _weekdayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

String _todayDateString() {
  final now = nowKst();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

String _currentMonday() {
  final now = nowKst();
  final m = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  return '${m.year.toString().padLeft(4, '0')}-'
      '${m.month.toString().padLeft(2, '0')}-'
      '${m.day.toString().padLeft(2, '0')}';
}

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));

    final today = _todayDateString();
    final ws = _currentMonday();
    final todayLabel = _weekdayLabels[nowKst().weekday - 1];

    // Diet rows that mirror the React mock totals.
    await db.batch((b) {
      b.insertAll(db.dietEntries, <DietEntriesCompanion>[
        DietEntriesCompanion.insert(
          id: 'd-b',
          date: today,
          mealType: 'breakfast',
          timeLabel: '08:20',
          foodsJson: jsonEncode(<Object?>[
            <String, Object?>{
              'name': '그릭요거트',
              'sodium_mg': 70,
              'carbs_g': 40,
              'protein_g': 20,
              'fat_g': 10,
            },
          ]),
          totalCalories: 315,
          sodiumMg: const Value(380),
          sugarG: const Value(18),
        ),
        DietEntriesCompanion.insert(
          id: 'd-l',
          date: today,
          mealType: 'lunch',
          timeLabel: '12:40',
          foodsJson: jsonEncode(<Object?>[
            <String, Object?>{
              'name': '김치찌개',
              'sodium_mg': 900,
              'carbs_g': 50,
              'protein_g': 25,
              'fat_g': 15,
            },
            <String, Object?>{
              'name': '배추김치',
              'sodium_mg': 420,
              'carbs_g': 20,
              'protein_g': 5,
              'fat_g': 5,
            },
          ]),
          totalCalories: 530,
          sodiumMg: const Value(1120),
          sugarG: const Value(14),
        ),
        DietEntriesCompanion.insert(
          id: 'd-d',
          date: today,
          mealType: 'dinner',
          timeLabel: '19:00',
          foodsJson: jsonEncode(<Object?>[
            <String, Object?>{
              'name': '닭가슴살 샐러드',
              'sodium_mg': 180,
              'carbs_g': 50,
              'protein_g': 40,
              'fat_g': 15,
            },
          ]),
          totalCalories: 575,
          sodiumMg: const Value(600),
          sugarG: const Value(13),
        ),
      ]);
    });

    // One session tagged to today's weekday — fixes the expected total
    // regardless of when the test actually runs.
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'ex-today',
            weekStart: ws,
            dayLabel: todayLabel,
            type: 'cardio',
            minutes: 45,
            calories: 320,
          ),
        );
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  test(
    'GET /dashboard/summary aggregates diet + exercise',
    () async {
      final res = await dio.get<Map<String, Object?>>('/dashboard/summary');
      expect(res.statusCode, 200);
      final body = res.data!;

      // Indicators — 3 rows after 혈당 row was removed per the latest
      // design ref (Home summary now ends at 당류).
      final indicators = (body['indicators']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(indicators.length, 3);
      final byLabel = <String, Map<String, Object?>>{
        for (final i in indicators) i['label']! as String: i,
      };
      expect(byLabel['칼로리']!['current'], 1420);
      expect(byLabel['나트륨']!['current'], 2100);
      expect(byLabel['나트륨']!['over_budget'], isTrue);
      expect(byLabel['당류']!['current'], 45);
      expect(byLabel.containsKey('혈당'), isFalse);
      expect(body['macros'], <String, Object?>{
        'carbs_g': 160.0,
        'protein_g': 90.0,
        'fat_g': 45.0,
        'carbs_pct': 45,
        'protein_pct': 26,
        'fat_pct': 29,
      });

      // Quick stats.
      expect(body['diet_entries'], 3);
      expect(body['exercise_minutes'], 45);
      expect(body['exercise_calories'], 320);
      expect(body['exercise_count'], 1);
      final nutritionWeek = (body['nutrition_week']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(nutritionWeek, hasLength(7));
      final todayTrend = nutritionWeek[nowKst().weekday - 1];
      expect(todayTrend['calories'], 1420);
      expect(todayTrend['sodium_mg'], 2100);
      expect(todayTrend['sugar_g'], 45.0);

      // Sodium warning is set when total > 2000.
      expect(body['sodium_warning'], '김치찌개·배추김치 섭취로 나트륨이 높아요.');

      // Week score is in the 0..100 band.
      final score = body['week_score']! as int;
      expect(score, inInclusiveRange(0, 100));
    },
  );

  test('sodium_warning is null when total stays under budget', () async {
    // Wipe and re-seed with a single low-sodium meal.
    await (db.delete(db.dietEntries)).go();
    await db
        .into(db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: 'd-snack',
            date: _todayDateString(),
            mealType: 'snack',
            timeLabel: '15:00',
            foodsJson: jsonEncode(<Object?>[]),
            totalCalories: 100,
            sodiumMg: const Value(50),
            sugarG: const Value(2),
          ),
        );

    final res = await dio.get<Map<String, Object?>>('/dashboard/summary');
    expect(res.data!['sodium_warning'], isNull);
  });

  test(
    'health goal update changes dashboard targets and over-budget state',
    () async {
      await dio.put<Object?>(
        '/users/me/health-goals',
        data: <String, Object?>{
          'daily_calories': 1800,
          'daily_sodium_mg': 1500,
          'daily_sugar_g': 35,
          'daily_carbs_g': 220,
          'daily_protein_g': 120,
          'daily_fat_g': 50,
        },
      );

      final response = await dio.get<Map<String, Object?>>(
        '/dashboard/summary',
      );
      final indicators = (response.data!['indicators']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final byLabel = <String, Map<String, Object?>>{
        for (final indicator in indicators)
          indicator['label']! as String: indicator,
      };
      expect(byLabel['칼로리']!['max'], 1800);
      expect(byLabel['나트륨']!['max'], 1500);
      expect(byLabel['당류']!['max'], 35);
      expect(byLabel['칼로리']!['over_budget'], isFalse);
      expect(byLabel['나트륨']!['over_budget'], isTrue);
      expect(byLabel['당류']!['over_budget'], isTrue);
    },
  );

  test('sodium goal changes week score using the FastAPI criteria', () async {
    final before = await dio.get<Map<String, Object?>>('/dashboard/summary');
    expect(before.data!['week_score'], 65);

    await dio.put<Object?>(
      '/users/me/health-goals',
      data: <String, Object?>{'daily_sodium_mg': 2500},
    );

    final after = await dio.get<Map<String, Object?>>('/dashboard/summary');
    expect(after.data!['week_score'], 85);
  });

  test(
    'sodium_warning handles one source name with a final consonant',
    () async {
      await (db.delete(db.dietEntries)).go();
      await db
          .into(db.dietEntries)
          .insert(
            DietEntriesCompanion.insert(
              id: 'd-ramen',
              date: _todayDateString(),
              mealType: 'lunch',
              timeLabel: '12:00',
              foodsJson: jsonEncode(<Object?>[
                <String, Object?>{'name': '라면', 'sodium_mg': 2100},
              ]),
              totalCalories: 500,
              sodiumMg: const Value(2100),
              sugarG: const Value(2),
            ),
          );

      final res = await dio.get<Map<String, Object?>>('/dashboard/summary');
      expect(res.data!['sodium_warning'], '라면 섭취로 나트륨이 높아요.');
    },
  );

  test('sodium_warning combines duplicate food names before ranking', () async {
    await (db.delete(db.dietEntries)).go();
    await db.batch((batch) {
      batch.insertAll(db.dietEntries, <DietEntriesCompanion>[
        DietEntriesCompanion.insert(
          id: 'd-duplicate-lunch',
          date: _todayDateString(),
          mealType: 'lunch',
          timeLabel: '12:00',
          foodsJson: jsonEncode(<Object?>[
            <String, Object?>{'name': '라면', 'sodium_mg': 600},
            <String, Object?>{'name': '김밥', 'sodium_mg': 700},
          ]),
          totalCalories: 500,
          sodiumMg: const Value(1100),
          sugarG: const Value(2),
        ),
        DietEntriesCompanion.insert(
          id: 'd-duplicate-dinner',
          date: _todayDateString(),
          mealType: 'dinner',
          timeLabel: '18:00',
          foodsJson: jsonEncode(<Object?>[
            <String, Object?>{'name': '라면', 'sodium_mg': 600},
            <String, Object?>{'name': '샐러드', 'sodium_mg': 800},
          ]),
          totalCalories: 500,
          sodiumMg: const Value(1100),
          sugarG: const Value(2),
        ),
      ]);
    });

    final res = await dio.get<Map<String, Object?>>('/dashboard/summary');

    expect(res.data!['sodium_warning'], '라면·샐러드 섭취로 나트륨이 높아요.');
  });

  test(
    'exercise summary aggregates every session in the current week',
    () async {
      await db
          .into(db.exerciseSessions)
          .insert(
            ExerciseSessionsCompanion.insert(
              id: 'ex-another-day',
              weekStart: _currentMonday(),
              dayLabel: _weekdayLabels[nowKst().weekday % 7],
              type: 'strength',
              minutes: 15,
              calories: 100,
            ),
          );

      final res = await dio.get<Map<String, Object?>>('/dashboard/summary');
      final body = res.data!;

      expect(body['exercise_minutes'], 60);
      expect(body['exercise_calories'], 420);
      expect(body['exercise_count'], 2);
      expect(body['exercise_feedback'], contains('이번 주'));
    },
  );

  test('sodium_warning falls back when source names are empty', () async {
    await (db.delete(db.dietEntries)).go();
    await db
        .into(db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: 'd-unknown',
            date: _todayDateString(),
            mealType: 'lunch',
            timeLabel: '12:00',
            foodsJson: jsonEncode(<Object?>[]),
            totalCalories: 500,
            sodiumMg: const Value(2100),
            sugarG: const Value(2),
          ),
        );

    final res = await dio.get<Map<String, Object?>>('/dashboard/summary');
    expect(res.data!['sodium_warning'], '오늘 나트륨이 2100mg 으로 권장량(2000mg)을 넘었어요.');
  });

  test(
    'exercise_count counts distinct workout days, not session rows',
    () async {
      // 운동 화면 workoutCount(활성 일수)와 정의를 맞춘다: 같은 날 유산소+근력을
      // 각각 기록해도 운동 횟수는 1(하루)로 센다.
      await (db.delete(db.exerciseSessions)).go();
      final ws = _currentMonday();
      final todayLabel = _weekdayLabels[nowKst().weekday - 1];
      await db.batch((b) {
        b.insertAll(db.exerciseSessions, <ExerciseSessionsCompanion>[
          ExerciseSessionsCompanion.insert(
            id: 'ex-same-1',
            weekStart: ws,
            dayLabel: todayLabel,
            type: 'cardio',
            minutes: 30,
            calories: 200,
          ),
          ExerciseSessionsCompanion.insert(
            id: 'ex-same-2',
            weekStart: ws,
            dayLabel: todayLabel,
            type: 'strength',
            minutes: 20,
            calories: 150,
          ),
        ]);
      });

      final res = await dio.get<Map<String, Object?>>('/dashboard/summary');
      final body = res.data!;
      expect(body['exercise_count'], 1); // 세션 2개지만 활성 일수는 1
      expect(body['exercise_minutes'], 50);
      expect(body['exercise_calories'], 350);
    },
  );
}

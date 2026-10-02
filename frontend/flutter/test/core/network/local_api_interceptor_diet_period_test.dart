/// 데모 모드의 기간 조회와 기록 시작일 — `GET /diet/days?from=&to=`,
/// `GET /me/records/span`. (#2236)
///
/// 데모와 실 연동의 그래프가 같은 그림이어야 하므로 서버
/// (`diet_service.build_period`)와 같은 규칙을 여기서 재현한다: `from` 을
/// 생략하면 첫 기록일부터, 오늘 이후로는 넘어가지 않고, 기록이 없는 날도 0 으로
/// 채운다.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_limits.dart';
import 'package:oncare_core/clock.dart';

const List<String> _weekdayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  late AppDatabase db;
  late Dio dio;
  late DateTime today;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
    final DateTime now = nowKst();
    today = DateTime(now.year, now.month, now.day);
  });

  tearDown(() async => db.close());

  Future<void> addDiet(
    DateTime date, {
    int calories = 500,
    int sodiumMg = 400,
    double sugarG = 5,
  }) async {
    await db
        .into(db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: 'd-${_ymd(date)}-$calories',
            date: _ymd(date),
            mealType: 'lunch',
            timeLabel: '12:00',
            foodsJson: jsonEncode(<Object?>[
              <String, Object?>{
                'name': '현미밥',
                'carbs_g': 40.0,
                'protein_g': 10.0,
                'fat_g': 5.0,
              },
            ]),
            totalCalories: calories,
            sodiumMg: Value<int>(sodiumMg),
            sugarG: Value<double>(sugarG),
          ),
        );
  }

  Future<void> addExercise(DateTime date, {int minutes = 30}) async {
    final DateTime monday = DateTime(
      date.year,
      date.month,
      date.day - (date.weekday - 1),
    );
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'e-${_ymd(date)}',
            weekStart: _ymd(monday),
            dayLabel: _weekdayLabels[date.weekday - 1],
            type: 'cardio',
            name: const Value<String>('걷기'),
            minutes: minutes,
            calories: 200,
          ),
        );
  }

  test('구간의 모든 날이 오고, 같은 날의 끼니는 합쳐진다', () async {
    final DateTime from = DateTime(today.year, today.month, today.day - 3);
    await addDiet(from, calories: 400);
    await addDiet(from, calories: 600, sodiumMg: 100);

    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>(
          '/diet/days',
          queryParameters: <String, String>{
            'from': _ymd(from),
            'to': _ymd(today),
          },
        );

    final Map<String, Object?> body = res.data!;
    expect(body['from_date'], _ymd(from));
    expect(body['to_date'], _ymd(today));
    final List<Object?> days = body['days']! as List<Object?>;
    expect(days, hasLength(4));
    final Map<String, Object?> first = days.first! as Map<String, Object?>;
    expect(first['total_calories'], 1000);
    expect(first['total_sodium_mg'], 500);
    // 기록이 없는 날도 빈 칸으로 온다.
    expect((days.last! as Map<String, Object?>)['total_calories'], 0);
  });

  test('`from` 을 생략하면 첫 기록일부터다', () async {
    final DateTime first = DateTime(today.year, today.month, today.day - 10);
    await addDiet(first);
    await addDiet(DateTime(today.year, today.month, today.day - 2));

    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/diet/days');

    expect(res.data!['from_date'], _ymd(first));
    expect(res.data!['to_date'], _ymd(today));
    expect((res.data!['days']! as List<Object?>), hasLength(11));
  });

  test('아직 오지 않은 날은 칸이 아니다', () async {
    await addDiet(today);

    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>(
          '/diet/days',
          queryParameters: <String, String>{
            'from': _ymd(today),
            'to': _ymd(DateTime(today.year, today.month, today.day + 30)),
          },
        );

    expect(res.data!['to_date'], _ymd(today));
    expect((res.data!['days']! as List<Object?>), hasLength(1));
  });

  test('기록이 하나도 없으면 오늘 하루짜리 빈 칸 하나다', () async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/diet/days');

    expect(res.data!['from_date'], _ymd(today));
    final List<Object?> days = res.data!['days']! as List<Object?>;
    expect(days, hasLength(1));
    expect((days.single! as Map<String, Object?>)['total_calories'], 0);
  });

  test('형식이 틀린 날짜는 422 다 — 하루 조회와 같은 규약', () async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>(
          '/diet/days',
          queryParameters: <String, String>{'from': '2026-13-40'},
          options: Options(validateStatus: (int? _) => true),
        );

    expect(res.statusCode, 422);
  });

  test('기록 시작일은 식단·운동이 각자다', () async {
    final DateTime dietFirst = DateTime(
      today.year,
      today.month,
      today.day - 20,
    );
    final DateTime exerciseFirst = DateTime(
      today.year,
      today.month,
      today.day - 9,
    );
    await addDiet(dietFirst);
    await addExercise(exerciseFirst);

    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/me/records/span');

    expect(res.data!['diet_first_date'], _ymd(dietFirst));
    expect(res.data!['exercise_first_date'], _ymd(exerciseFirst));
  });

  test('기록이 없으면 null 이다 — 오늘로 지어내지 않는다', () async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/me/records/span');

    expect(res.data!['diet_first_date'], isNull);
    expect(res.data!['exercise_first_date'], isNull);
  });

  // 서버 기간 집계와 같은 구간 상한(#2833). 날짜가 잘못 들어간 아주 오래된 기록
  // 하나가 데모 그래프를 수십만 칸으로 늘리지 않는다. "오늘" 은 KST 2026-09-17(목).
  group('구간 상한(#2833)', () {
    final DateTime fixedToday = DateTime(2026, 9, 17);
    final DateTime dayFloor = DateTime(
      2026,
      9,
      17 - (kDietAllPeriodMaxDays - 1),
    );
    final DateTime weekFloor = DateTime(
      2026,
      9,
      14 - (kExerciseMaxPeriodWeeks - 1) * 7,
    );

    setUp(() => debugNowKstOverride = () => DateTime(2026, 9, 17, 10));
    tearDown(() => debugNowKstOverride = null);

    test('아주 이른 `from` 은 1100일 전으로 잘린다', () async {
      final Response<Map<String, Object?>> res = await dio
          .get<Map<String, Object?>>(
            '/diet/days',
            queryParameters: <String, String>{'from': '0001-01-01'},
          );

      expect(res.data!['from_date'], _ymd(dayFloor));
      expect(res.data!['to_date'], _ymd(fixedToday));
      expect(
        res.data!['days']! as List<Object?>,
        hasLength(kDietAllPeriodMaxDays),
      );
    });

    test('`from` 없이 옛 기록 하나가 있어도 같은 상한이다', () async {
      await addDiet(DateTime(1970));
      await addDiet(DateTime(2026, 9, 14), calories: 700);

      final Response<Map<String, Object?>> res = await dio
          .get<Map<String, Object?>>('/diet/days');

      expect(res.data!['from_date'], _ymd(dayFloor));
      final List<Object?> days = res.data!['days']! as List<Object?>;
      expect(days, hasLength(kDietAllPeriodMaxDays));
      expect(
        (days[days.length - 4]! as Map<String, Object?>)['total_calories'],
        700,
      );
    });

    test('상한 안쪽 구간은 그대로다', () async {
      final DateTime from = DateTime(2025, 9, 18);
      final Response<Map<String, Object?>> res = await dio
          .get<Map<String, Object?>>(
            '/diet/days',
            queryParameters: <String, String>{'from': _ymd(from)},
          );

      expect(res.data!['from_date'], _ymd(from));
      expect(res.data!['days']! as List<Object?>, hasLength(365));
    });

    test('운동 기간도 160주 전 월요일로 잘린다', () async {
      await addExercise(DateTime(1970, 1, 7));

      final Response<Map<String, Object?>> res = await dio
          .get<Map<String, Object?>>('/exercise/weeks');

      expect(res.data!['from_week'], _ymd(weekFloor));
      expect(weekFloor.weekday, DateTime.monday);
      expect(
        res.data!['weeks']! as List<Object?>,
        hasLength(kExerciseMaxPeriodWeeks),
      );
    });
  });
}

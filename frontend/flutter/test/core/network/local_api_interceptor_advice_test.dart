/// 데모의 기간별 AI 맞춤 조언. (#1574)
///
/// 예전에는 `GET /diet/advice` 를 데모가 아예 처리하지 않아 요청이 네트워크로
/// 흘러 실패했고, 화면은 어쩔 수 없이 오늘 조언을 대신 그렸다 — `이번 주` 를
/// 보면서 오늘 이야기를 읽게 되는 원인이 여기였다.
///
/// 여기서 확인하는 것: 세 기간이 **각자 자기 구간의 기록만** 보고, 서로 다른
/// 말을 하는가.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/utils/clock.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _today() {
  final DateTime now = nowKst();
  return DateTime(now.year, now.month, now.day);
}

DateTime _thisMonday() {
  final DateTime today = _today();
  return DateTime(today.year, today.month, today.day - (today.weekday - 1));
}

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

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

  Future<void> addMeal(DateTime date, {required int sodium}) async {
    await db
        .into(db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: 'diet-${_ymd(date)}',
            date: _ymd(date),
            mealType: 'lunch',
            timeLabel: '12:00',
            foodsJson: jsonEncode(<Map<String, Object?>>[
              <String, Object?>{'name': '점심', 'calories': 700},
            ]),
            totalCalories: 700,
            sodiumMg: Value(sodium),
          ),
        );
  }

  Future<void> addWorkout(
    DateTime date, {
    String type = 'cardio',
    int minutes = 30,
  }) async {
    final DateTime monday = DateTime(
      date.year,
      date.month,
      date.day - (date.weekday - 1),
    );
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'ex-${_ymd(date)}-$type',
            weekStart: _ymd(monday),
            dayLabel: _dayLabels[date.weekday - 1],
            type: type,
            minutes: minutes,
            calories: minutes * 9,
          ),
        );
  }

  test('GET /diet/advice 는 기간마다 다른 말을 한다', () async {
    final DateTime today = _today();
    final DateTime monday = _thisMonday();
    // 이번 주 월요일부터 어제까지는 짜게, 오늘은 싱겁게 먹은 주.
    for (
      DateTime day = monday;
      day.isBefore(today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      await addMeal(day, sodium: 2600);
    }
    await addMeal(today, sodium: 900);

    final Response<Map<String, Object?>> todayView = await dio
        .get<Map<String, Object?>>(
          '/diet/advice',
          queryParameters: <String, Object?>{'period': 'today'},
        );
    expect(todayView.data!['from_date'], _ymd(today));
    expect(todayView.data!['days_logged'], 1);
    // 규칙 한 줄은 문장 키로도 온다(#2255) — 앱이 자기 언어로 그린다.
    expect(todayView.data!['analysis_key'], startsWith('today_'));

    final Response<Map<String, Object?>> week = await dio
        .get<Map<String, Object?>>(
          '/diet/advice',
          queryParameters: <String, Object?>{'period': 'week'},
        );
    expect(week.data!['from_date'], _ymd(monday));
    expect(week.data!['message'], isNot(todayView.data!['message']));

    final Response<Map<String, Object?>> all = await dio
        .get<Map<String, Object?>>(
          '/diet/advice',
          queryParameters: <String, Object?>{'period': 'all'},
        );
    // 전체는 최근 4주를 본다 — 이번 주와 시작일이 다르다(#2254).
    expect(
      (all.data!['from_date']! as String).compareTo(_ymd(monday)),
      lessThan(0),
    );
  });

  test('GET /diet/advice 는 lang 을 받는다 — 메뉴 이름이 그 언어다', () async {
    final Response<Map<String, Object?>> en = await dio
        .get<Map<String, Object?>>(
          '/diet/advice',
          queryParameters: <String, Object?>{'period': 'today', 'lang': 'en'},
        );
    final Object? menu =
        (en.data!['action_params']! as Map<String, Object?>)['menu'];
    if (menu != null) {
      expect((menu as String).codeUnits.every((int c) => c < 128), isTrue);
    }

    final Response<Object?> unknown = await dio.get<Object?>(
      '/diet/advice',
      queryParameters: <String, Object?>{'period': 'today', 'lang': 'jp'},
      options: Options(validateStatus: (int? _) => true),
    );
    expect(unknown.statusCode, 422);
  });

  test('GET /diet/advice 는 기록이 없어도 그 기간의 안내를 남긴다', () async {
    for (final String period in <String>['today', 'week', 'all']) {
      final Response<Map<String, Object?>> res = await dio
          .get<Map<String, Object?>>(
            '/diet/advice',
            queryParameters: <String, Object?>{'period': period},
          );
      expect(res.data!['days_logged'], 0);
      expect(res.data!['message'], isNotEmpty);
    }
  });

  test('GET /exercise/advice 는 구간에 걸친 주를 모두 읽고 날짜로 거른다', () async {
    final DateTime today = _today();
    final DateTime monday = _thisMonday();
    // 지난 주 하루 — `이번 주` 에는 들어오지 않고 `전체` 에만 잡힌다.
    await addWorkout(
      DateTime(monday.year, monday.month, monday.day - 3),
      minutes: 50,
    );
    for (
      DateTime day = monday;
      !day.isAfter(today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      await addWorkout(day);
    }

    final Response<Map<String, Object?>> week = await dio
        .get<Map<String, Object?>>(
          '/exercise/advice',
          queryParameters: <String, Object?>{'period': 'week'},
        );
    expect(week.data!['from_date'], _ymd(monday));
    expect(week.data!['days_logged'], today.weekday);

    final Response<Map<String, Object?>> all = await dio
        .get<Map<String, Object?>>(
          '/exercise/advice',
          queryParameters: <String, Object?>{'period': 'all'},
        );
    expect(all.data!['days_logged'], today.weekday + 1);

    final Response<Map<String, Object?>> todayView = await dio
        .get<Map<String, Object?>>(
          '/exercise/advice',
          queryParameters: <String, Object?>{'period': 'today'},
        );
    expect(todayView.data!['days_logged'], 1);
    expect(todayView.data!['message'], contains('오늘'));
    expect(todayView.data!['message'], isNot(week.data!['message']));
  });

  test('기간 이름이 아니면 422 다 — 조용히 오늘로 흘려보내지 않는다', () async {
    for (final String path in <String>['/diet/advice', '/exercise/advice']) {
      final Response<Object?> res = await dio.get<Object?>(
        path,
        queryParameters: <String, Object?>{'period': 'month'},
        options: Options(validateStatus: (int? _) => true),
      );
      expect(res.statusCode, 422, reason: path);
    }
  });
}

/// 데모 홈 요약이 로컬 인터셉터 한 경로에서 **지금 기록**을 따르는지(#2645).
///
/// 예전 데모 홈은 별도 목업 저장소를 거쳐 운동 45분·큐레이션 조언을 고정으로
/// 냈다. 끼니를 다 지워도 홈 조언은 "짬뽕 …" 그대로였다. 이제 데모 홈도 실서버와
/// 같은 `GET /dashboard/summary` 를 타고, 기록이 바뀌면 인터셉터가 시드의
/// 큐레이션 문장을 거둔다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/core/utils/clock.dart';

String _dateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _today() => _dateString(nowKst());

String _currentMonday() {
  final DateTime now = nowKst();
  return _dateString(
    DateTime(now.year, now.month, now.day - (now.weekday - 1)),
  );
}

Options _lang(String lang) =>
    Options(headers: <String, Object?>{'Accept-Language': lang});

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
    await seedIfEmpty(db);
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<Map<String, Object?>> summary([String lang = 'ko']) async =>
      (await dio.get<Map<String, Object?>>(
        '/dashboard/summary',
        options: _lang(lang),
      )).data!;

  Future<String> dayMessage(String date, [String lang = 'ko']) async =>
      (await dio.get<Map<String, Object?>>(
            '/diet/days/$date',
            options: _lang(lang),
          )).data!['ai_coach_message']!
          as String;

  Future<List<String>> todayMealIds() async => <String>[
    for (final DietEntryRow row in await (db.select(
      db.dietEntries,
    )..where((t) => t.date.equals(_today()))).get())
      row.id,
  ];

  Future<void> deleteTodayMeals() async {
    for (final String id in await todayMealIds()) {
      await dio.delete<Object?>('/diet/entries/$id');
    }
  }

  Future<int> weekExerciseMinutes() async {
    final List<ExerciseSessionRow> rows = await (db.select(
      db.exerciseSessions,
    )..where((t) => t.weekStart.equals(_currentMonday()))).get();
    return rows.fold<int>(
      0,
      (int sum, ExerciseSessionRow r) => sum + r.minutes,
    );
  }

  num indicator(Map<String, Object?> body, String unit) =>
      ((body['indicators']! as List<Object?>).cast<Map<String, Object?>>())
              .firstWhere(
                (Map<String, Object?> i) => i['unit'] == unit,
              )['current']!
          as num;

  test('시드 직후에는 큐레이션 통합 조언 키를 싣는다', () async {
    final Map<String, Object?> body = await summary();

    expect(body['ai_advice_key'], kDailyCombinedAdviceKey);
    expect(body['sodium_warning'], isNull);
  });

  test('운동 분은 고정값이 아니라 이번 주 실제 기록의 합이다', () async {
    final Map<String, Object?> body = await summary();

    expect(body['exercise_minutes'], await weekExerciseMinutes());
  });

  group('오늘 끼니를 모두 지우면', () {
    setUp(deleteTodayMeals);

    test('오늘 영양 수치와 끼니 수가 0 이다', () async {
      final Map<String, Object?> body = await summary();

      expect(body['diet_entries'], 0);
      expect(indicator(body, 'kcal'), 0);
      expect(indicator(body, 'mg'), 0);
      final Map<String, Object?> macros =
          (body['macros']! as Map<Object?, Object?>).cast<String, Object?>();
      expect(macros['carbs_g'], 0);
      expect(macros['protein_g'], 0);
      expect(macros['fat_g'], 0);
    });

    test('큐레이션 조언 대신 지금 기록으로 만든 조언이다', () async {
      final Map<String, Object?> ko = await summary();
      final Map<String, Object?> en = await summary('en');

      expect(ko['ai_advice_key'], isNot(kDailyCombinedAdviceKey));
      // 나트륨이 0 이라 경고는 없고, 이번 주 운동 되먹임이 조언이다.
      expect(ko['sodium_warning'], isNull);
      expect(
        ko['ai_advice_key'],
        isIn(<String>['exercise_start', 'exercise_more', 'exercise_on_track']),
      );
      expect(en['ai_advice_key'], ko['ai_advice_key']);
      expect(en['exercise_feedback'], isNot(matches(RegExp('[가-힣]'))));
    });

    test('식단 탭 하루 문장도 시드 큐레이션이 아니라 빈 날 문장이다', () async {
      expect(
        await dayMessage(_today()),
        LocalApiInterceptor.derivedDietDayMessage(
          lang: 'ko',
          totalSodium: 0,
          empty: true,
        ),
      );
    });

    test('큐레이션 키는 저장소에서도 사라진다', () async {
      expect(await db.readValue('dashboard_ai_advice'), isNull);
      final String? raw = await db.readValue(kDietDayMessagesKey);
      expect(raw, isNot(contains('"${_today()}"')));
    });
  });

  test('끼니 한 건만 지워도 통합 조언을 거둔다 — 남은 기록으로 판단한다', () async {
    final List<String> ids = await todayMealIds();
    expect(ids, isNotEmpty);

    await dio.delete<Object?>('/diet/entries/${ids.first}');

    expect((await summary())['ai_advice_key'], isNot(kDailyCombinedAdviceKey));
  });

  test('운동을 추가하면 통합 조언을 거두고 운동 분이 늘어난다', () async {
    final int before = (await summary())['exercise_minutes']! as int;

    await dio.post<Object?>(
      '/exercise/sessions',
      data: <String, Object?>{
        'sessions': <Map<String, Object?>>[
          <String, Object?>{'type': 'cardio', 'name': '걷기', 'minutes': 30},
        ],
      },
    );

    final Map<String, Object?> after = await summary();
    expect(after['ai_advice_key'], isNot(kDailyCombinedAdviceKey));
    expect(after['exercise_minutes'], before + 30);
    // 운동만 바뀌었으니 식단 탭 하루 문장(큐레이션)은 그대로다.
    expect(await dayMessage(_today()), contains('짬뽕'));
  });

  test('없는 끼니를 지우려 하면 큐레이션을 건드리지 않는다', () async {
    final Response<Object?> res = await dio.delete<Object?>(
      '/diet/entries/no-such-id',
      options: Options(validateStatus: (_) => true),
    );

    expect(res.statusCode, 404);
    expect((await summary())['ai_advice_key'], kDailyCombinedAdviceKey);
  });
}

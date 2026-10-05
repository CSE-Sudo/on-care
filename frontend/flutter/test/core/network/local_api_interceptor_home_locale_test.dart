/// 데모 서버(로컬 인터셉터)의 홈 조언·하루 식단 코치 문장이 화면 언어와 날짜를
/// 따르는지. 실 서버와 같은 규칙·같은 문장이다(#2644).
///
/// 예전에는 두 자리 모두 `Accept-Language` 를 보지 않고 한국어만 만들었다. 홈은
/// 음식 이름이 든 나트륨 경고를 키 없이 한국어 문장으로만 실었고, 하루 코치
/// 문장은 지난 날짜에도 "오늘 … 저녁은" 이었다.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare_core/clock.dart';

const List<String> _weekdayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

final RegExp _hangul = RegExp('[가-힣]');

String _dateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _today() => _dateString(nowKst());

String _daysAgo(int days) {
  final DateTime now = nowKst();
  return _dateString(DateTime(now.year, now.month, now.day - days));
}

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

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<void> addMeal({
    required String id,
    required String date,
    required List<Map<String, Object?>> foods,
    required int sodium,
  }) => db
      .into(db.dietEntries)
      .insert(
        DietEntriesCompanion.insert(
          id: id,
          date: date,
          mealType: 'lunch',
          timeLabel: '12:00',
          foodsJson: jsonEncode(foods),
          totalCalories: 600,
          sodiumMg: Value(sodium),
          sugarG: const Value(5),
        ),
      );

  Future<void> addExercise(int minutes) => db
      .into(db.exerciseSessions)
      .insert(
        ExerciseSessionsCompanion.insert(
          id: 'ex-$minutes',
          weekStart: _currentMonday(),
          dayLabel: _weekdayLabels[nowKst().weekday - 1],
          type: 'cardio',
          minutes: minutes,
          calories: minutes * 5,
        ),
      );

  Future<Map<String, Object?>> summary(String lang) async =>
      (await dio.get<Map<String, Object?>>(
        '/dashboard/summary',
        options: _lang(lang),
      )).data!;

  group('홈 나트륨 경고', () {
    setUp(
      () => addMeal(
        id: 'd-salty',
        date: _today(),
        foods: <Map<String, Object?>>[
          <String, Object?>{'name': '라면', 'sodium_mg': 1500},
          <String, Object?>{'name': '김밥', 'sodium_mg': 800},
          <String, Object?>{'name': '단무지', 'sodium_mg': 100},
        ],
        sodium: 2400,
      ),
    );

    test('음식 이름이 든 경고도 키와 음식 이름 인자로 싣는다', () async {
      for (final String lang in <String>['ko', 'en']) {
        final Map<String, Object?> body = await summary(lang);
        expect(body['ai_advice_key'], 'sodium_over_sources', reason: lang);
        expect(body['ai_advice_params'], <String, Object?>{
          'foods': <String>['라면', '김밥'],
        }, reason: lang);
      }
    });

    test('문장은 요청 언어를 따른다 — 음식 이름은 그대로', () async {
      final Map<String, Object?> ko = await summary('ko');
      final Map<String, Object?> en = await summary('en');

      expect(ko['sodium_warning'], '라면·김밥 섭취로 나트륨이 높아요.');
      expect(en['sodium_warning'], 'Sodium is high from 라면 and 김밥.');
      expect(
        (en['sodium_warning']! as String)
            .replaceAll('라면', '')
            .replaceAll('김밥', ''),
        isNot(matches(_hangul)),
      );
      expect(en['exercise_feedback'], isNot(matches(_hangul)));
    });

    test('음식 이름이 없으면 sodium_over 키와 수치 문장이다', () async {
      await db.delete(db.dietEntries).go();
      await addMeal(
        id: 'd-unknown',
        date: _today(),
        foods: <Map<String, Object?>>[],
        sodium: 2100,
      );

      final Map<String, Object?> en = await summary('en');
      expect(en['ai_advice_key'], 'sodium_over');
      expect(en['ai_advice_params'], isEmpty);
      expect(
        en['sodium_warning'],
        'Sodium is at 2,100 mg today, over your target (2,000 mg).',
      );
    });

    test('회원 나트륨 목표를 기준으로 넘침을 판정한다', () async {
      await db.delete(db.dietEntries).go();
      await addMeal(
        id: 'd-mid',
        date: _today(),
        foods: <Map<String, Object?>>[
          <String, Object?>{'name': '된장국', 'sodium_mg': 1700},
        ],
        sodium: 1700,
      );
      expect((await summary('ko'))['sodium_warning'], isNull);

      await dio.put<Object?>(
        '/users/me/health-goals',
        data: <String, Object?>{'daily_sodium_mg': 1500},
      );
      expect((await summary('ko'))['ai_advice_key'], 'sodium_over_sources');
    });
  });

  group('홈 운동 되먹임', () {
    test('나트륨 경고가 없으면 서버와 같은 150분 기준으로 키를 고른다', () async {
      expect((await summary('en'))['ai_advice_key'], 'exercise_start');

      await addExercise(40);
      Map<String, Object?> en = await summary('en');
      expect(en['ai_advice_key'], 'exercise_more');
      expect(
        en['exercise_feedback'],
        'You worked out 40 minutes this week. A little more to go!',
      );

      await addExercise(120);
      en = await summary('en');
      expect(en['ai_advice_key'], 'exercise_on_track');
      expect(
        en['exercise_feedback'],
        'You worked out 160 minutes this week. You are on track!',
      );
      expect(
        (await summary('ko'))['exercise_feedback'],
        '이번 주 160분 운동했어요. 목표 달성 중이에요!',
      );
    });

    test('Accept-Language 가 없거나 모르는 언어면 한국어다', () async {
      final Map<String, Object?> none = (await dio.get<Map<String, Object?>>(
        '/dashboard/summary',
      )).data!;
      final Map<String, Object?> fr = await summary('fr-FR');

      expect(none['exercise_feedback'], '이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요.');
      expect(fr['exercise_feedback'], none['exercise_feedback']);
    });
  });

  group('하루 식단 코치 문장', () {
    Future<String> coach(String date, String lang) async =>
        (await dio.get<Map<String, Object?>>(
              '/diet/days/$date',
              options: _lang(lang),
            )).data!['ai_coach_message']!
            as String;

    test('지난 날짜는 그날을 되짚는다 — 오늘·저녁 말투가 아니다', () async {
      final String past = _daysAgo(3);
      await addMeal(
        id: 'd-past',
        date: past,
        foods: <Map<String, Object?>>[
          <String, Object?>{'name': '짬뽕', 'sodium_mg': 4000},
        ],
        sodium: 4000,
      );

      final String ko = await coach(past, 'ko');
      final String en = await coach(past, 'en');

      expect(ko, '그날은 나트륨 섭취가 많았어요. 다음 날은 국물·양념을 줄여 균형을 맞춰 봐요.');
      expect(
        en,
        'Sodium ran high that day. Go easy on soups and sauces the next day to balance it out.',
      );
      expect(ko, isNot(contains('오늘')));
      expect(ko, isNot(contains('저녁')));
    });

    test('오늘은 지금 문장 그대로다', () async {
      await addMeal(
        id: 'd-today',
        date: _today(),
        foods: <Map<String, Object?>>[],
        sodium: 4000,
      );

      expect(await coach(_today(), 'ko'), startsWith('오늘 나트륨 섭취가 많았어요.'));
      expect(
        await coach(_today(), 'en'),
        startsWith('You had a lot of sodium today.'),
      );
    });

    test('나트륨 기준은 회원 목표다', () async {
      final String past = _daysAgo(2);
      await addMeal(
        id: 'd-goal',
        date: past,
        foods: <Map<String, Object?>>[],
        sodium: 1800,
      );
      expect(await coach(past, 'ko'), '나트륨을 목표 안에서 지킨 균형 잡힌 하루였어요.');

      await dio.put<Object?>(
        '/users/me/health-goals',
        data: <String, Object?>{'daily_sodium_mg': 1500},
      );
      expect(await coach(past, 'ko'), startsWith('그날은 나트륨 섭취가 많았어요.'));
    });

    test('영어 화면은 시드의 한국어 큐레이션 문장 대신 수치 문장이다', () async {
      await seedIfEmpty(db);

      final String ko = await coach(_today(), 'ko');
      final String en = await coach(_today(), 'en');

      // 한국어는 시드 큐레이션 그대로(짬뽕 …), 영어는 한글 없는 수치 문장.
      expect(ko, contains('짬뽕'));
      expect(en, isNot(matches(_hangul)));
    });
  });

  group('derivedDietDayMessage', () {
    for (final String lang in <String>['ko', 'en']) {
      test('$lang — 지난 날짜 세 갈래는 서로 다르고 오늘 말투가 없다', () {
        final Set<String> messages = <String>{
          for (final (int sodium, bool empty) in <(int, bool)>[
            (3000, false),
            (0, true),
            (1000, false),
          ])
            LocalApiInterceptor.derivedDietDayMessage(
              lang: lang,
              totalSodium: sodium,
              empty: empty,
              isPast: true,
            ),
        };
        expect(messages, hasLength(3));
        for (final String m in messages) {
          expect(m, isNot(contains('오늘')));
          expect(m.toLowerCase(), isNot(contains('today')));
        }
        if (lang == 'en') {
          for (final String m in messages) {
            expect(m, isNot(matches(_hangul)));
          }
        }
      });
    }

    test('목표가 없으면 2,000mg 이 기준이다', () {
      String at(int sodium) => LocalApiInterceptor.derivedDietDayMessage(
        lang: 'ko',
        totalSodium: sodium,
        empty: false,
        isPast: true,
      );
      expect(at(2000), '나트륨을 목표 안에서 지킨 균형 잡힌 하루였어요.');
      expect(at(2001), startsWith('그날은 나트륨 섭취가 많았어요.'));
    });
  });
}

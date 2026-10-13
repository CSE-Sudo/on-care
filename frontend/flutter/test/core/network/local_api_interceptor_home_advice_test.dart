/// 데모 서버(로컬 인터셉터)의 홈 조언·하루 식단 코치 문장이 기록과 날짜를
/// 따르는지. 실 서버와 같은 규칙·같은 문장이다(#2644).
///
/// 예전에는 홈이 음식 이름이 든 나트륨 경고를 키 없이 문장으로만 실었고, 하루
/// 코치 문장은 지난 날짜에도 "오늘 … 저녁은" 이었다.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare_core/clock.dart';

const List<String> _weekdayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

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

  Future<void> addExercise(int minutes, {String type = 'cardio'}) => db
      .into(db.exerciseSessions)
      .insert(
        ExerciseSessionsCompanion.insert(
          id: 'ex-$type-$minutes',
          weekStart: _currentMonday(),
          dayLabel: _weekdayLabels[nowKst().weekday - 1],
          type: type,
          minutes: minutes,
          calories: minutes * 5,
        ),
      );

  Future<Map<String, Object?>> summary() async =>
      (await dio.get<Map<String, Object?>>('/dashboard/summary')).data!;

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
      final Map<String, Object?> body = await summary();
      expect(body['ai_advice_key'], 'sodium_over_sources');
      expect(body['ai_advice_params'], <String, Object?>{
        'foods': <String>['라면', '김밥'],
      });
    });

    test('문장에 음식 이름을 그대로 싣는다', () async {
      final Map<String, Object?> ko = await summary();

      expect(ko['sodium_warning'], '라면·김밥 섭취로 나트륨이 높아요.');
    });

    test('음식 이름이 없으면 sodium_over 키와 수치 문장이다', () async {
      await db.delete(db.dietEntries).go();
      await addMeal(
        id: 'd-unknown',
        date: _today(),
        foods: <Map<String, Object?>>[],
        sodium: 2100,
      );

      final Map<String, Object?> body = await summary();
      expect(body['ai_advice_key'], 'sodium_over');
      expect(body['ai_advice_params'], isEmpty);
      expect(body['sodium_warning'], '오늘 나트륨이 2,100mg으로 목표(2,000mg)를 넘었어요.');
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
      expect((await summary())['sodium_warning'], isNull);

      await dio.put<Object?>(
        '/users/me/health-goals',
        data: <String, Object?>{'daily_sodium_mg': 1500},
      );
      expect((await summary())['ai_advice_key'], 'sodium_over_sources');
    });
  });

  group('홈 운동 되먹임', () {
    test('나트륨 경고가 없으면 서버와 같은 기본 목표(150분)로 키를 고른다', () async {
      expect((await summary())['ai_advice_key'], 'exercise_start');

      await addExercise(40);
      Map<String, Object?> body = await summary();
      expect(body['ai_advice_key'], 'exercise_more');
      expect(body['exercise_feedback'], '이번 주 유산소 40분 운동했어요. 조금만 더 힘내요!');

      await addExercise(120);
      body = await summary();
      expect(body['ai_advice_key'], 'exercise_on_track');
      expect(body['exercise_feedback'], '이번 주 유산소 160분 운동했어요. 목표 달성 중이에요!');
    });

    // 운동 탭과 같은 판정이다(#3350) — 유산소 분을 회원의 주간 유산소 목표와
    // 견준다. 예전에는 유형을 가리지 않은 합계를 주 150분 고정과 견줬다.
    test('회원의 주간 유산소 목표를 기준으로 판정한다', () async {
      await addExercise(100);
      expect((await summary())['ai_advice_key'], 'exercise_more');

      await dio.put<Object?>(
        '/users/me/health-goals',
        data: <String, Object?>{'weekly_cardio_minutes': 90},
      );
      final Map<String, Object?> lowered = await summary();
      expect(lowered['ai_advice_key'], 'exercise_on_track');
      expect(lowered['exercise_feedback'], '이번 주 유산소 100분 운동했어요. 목표 달성 중이에요!');
    });

    test('목표를 올린 회원은 150분을 넘겨도 아직 달성이 아니다', () async {
      await addExercise(160);
      expect((await summary())['ai_advice_key'], 'exercise_on_track');

      await dio.put<Object?>(
        '/users/me/health-goals',
        data: <String, Object?>{'weekly_cardio_minutes': 200},
      );
      expect((await summary())['ai_advice_key'], 'exercise_more');
    });

    test('근력 시간은 유산소 목표에 넣지 않는다', () async {
      await addExercise(40);
      await addExercise(200, type: 'strength');

      final Map<String, Object?> ko = await summary();
      expect(ko['exercise_minutes'], 240);
      expect(ko['exercise_cardio_minutes'], 40);
      expect(ko['ai_advice_key'], 'exercise_more');
      expect(ko['exercise_feedback'], '이번 주 유산소 40분 운동했어요. 조금만 더 힘내요!');
    });

    test('근력만 한 주는 유산소를 권한다 — 0분 운동했다고 적지 않는다', () async {
      await addExercise(60, type: 'strength');

      final Map<String, Object?> body = await summary();
      expect(body['exercise_cardio_minutes'], 0);
      expect(body['ai_advice_key'], 'exercise_cardio_start');
      expect(
        body['exercise_feedback'],
        '이번 주 유산소 기록은 아직 없어요. 가볍게 걷기부터 시작해 볼까요?',
      );
    });

    test('요청이 어떤 언어 헤더를 실어도 한국어다', () async {
      final Map<String, Object?> none = await summary();
      final Map<String, Object?> english = (await dio.get<Map<String, Object?>>(
        '/dashboard/summary',
        options: Options(
          headers: <String, Object?>{'Accept-Language': 'en-US'},
        ),
      )).data!;

      expect(none['exercise_feedback'], '이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요.');
      expect(english['exercise_feedback'], none['exercise_feedback']);
    });
  });

  // 데모 AI 대화의 답에 적히는 목표도 회원의 것이다(#3350). 예전에는 나트륨
  // 2,000mg·유산소 150분이 문장에 박혀 있었다.
  group('AI 대화 답의 목표 숫자', () {
    Future<String> ask(String message) async =>
        (await dio.post<Map<String, Object?>>(
              '/ai-coach/chat',
              data: <String, Object?>{'message': message},
            )).data!['reply']!
            as String;

    test('목표가 없으면 기본값을 적는다', () async {
      expect(await ask('나트륨 줄이는 법 알려줘'), contains('2000mg 이하'));
      final String cardio = await ask('유산소 얼마나 해야 해?');
      expect(cardio, contains('하루 30분씩'));
      expect(cardio, contains('주간 목표 150분'));
    });

    test('회원이 바꾼 목표를 적는다', () async {
      await dio.put<Object?>(
        '/users/me/health-goals',
        data: <String, Object?>{
          'daily_sodium_mg': 1500,
          'weekly_cardio_minutes': 90,
        },
      );

      expect(await ask('나트륨 줄이는 법 알려줘'), contains('1500mg 이하'));
      final String ko = await ask('유산소 얼마나 해야 해?');
      expect(ko, contains('하루 18분씩'));
      expect(ko, contains('주간 목표 90분'));
      expect(ko, isNot(contains('150')));
    });
  });

  group('하루 식단 코치 문장', () {
    Future<String> coach(String date) async =>
        (await dio.get<Map<String, Object?>>(
              '/diet/days/$date',
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

      final String ko = await coach(past);

      expect(ko, '그날은 나트륨 섭취가 많았어요. 다음 날은 국물·양념을 줄여 균형을 맞춰 봐요.');
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

      expect(await coach(_today()), startsWith('오늘 나트륨 섭취가 많았어요.'));
    });

    test('나트륨 기준은 회원 목표다', () async {
      final String past = _daysAgo(2);
      await addMeal(
        id: 'd-goal',
        date: past,
        foods: <Map<String, Object?>>[],
        sodium: 1800,
      );
      expect(await coach(past), '나트륨을 목표 안에서 지킨 균형 잡힌 하루였어요.');

      await dio.put<Object?>(
        '/users/me/health-goals',
        data: <String, Object?>{'daily_sodium_mg': 1500},
      );
      expect(await coach(past), startsWith('그날은 나트륨 섭취가 많았어요.'));
    });
  });

  group('derivedDietDayMessage', () {
    test('지난 날짜 세 갈래는 서로 다르고 오늘 말투가 없다', () {
      final Set<String> messages = <String>{
        for (final (int sodium, bool empty) in <(int, bool)>[
          (3000, false),
          (0, true),
          (1000, false),
        ])
          LocalApiInterceptor.derivedDietDayMessage(
            totalSodium: sodium,
            empty: empty,
            isPast: true,
          ),
      };
      expect(messages, hasLength(3));
      for (final String m in messages) {
        expect(m, isNot(contains('오늘')));
      }
    });

    test('목표가 없으면 2,000mg 이 기준이다', () {
      String at(int sodium) => LocalApiInterceptor.derivedDietDayMessage(
        totalSodium: sodium,
        empty: false,
        isPast: true,
      );
      expect(at(2000), '나트륨을 목표 안에서 지킨 균형 잡힌 하루였어요.');
      expect(at(2001), startsWith('그날은 나트륨 섭취가 많았어요.'));
    });
  });
}

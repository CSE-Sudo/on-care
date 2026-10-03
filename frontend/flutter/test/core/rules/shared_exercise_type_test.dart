import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/demo/period_advice.dart' show exerciseTypeLabel;
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare_core/clock.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 회원 앱의 운동 유형 접기가 서버 `exercise_types` 와 같은 표를 쓰는가(#2861).
void main() {
  final Map<String, Object?> vectors = loadSharedRuleVectors('exercise_types');
  final List<List<Object?>> rows = <List<Object?>>[
    for (final Object? r in vectors['normalize']! as List<Object?>)
      r! as List<Object?>,
  ];

  const Map<String, ExerciseType> byCode = <String, ExerciseType>{
    'cardio': ExerciseType.cardio,
    'strength': ExerciseType.strength,
    'stretching': ExerciseType.stretching,
    'other': ExerciseType.other,
  };

  String show(Object? v) => v == null ? 'null' : '"$v"';

  group('기록·루틴 유형 → ExerciseType — 서버 normalize 와 같다', () {
    for (final List<Object?> r in rows) {
      test('${show(r[0])} → ${r[1]}', () {
        expect(exerciseTypeFromCode(r[0] as String?), byCode[r[1]]);
        expect(exerciseTypeFromLabel(r[0] as String?), byCode[r[1]]);
      });
    }

    test('한글 라벨로 온 기록도 기타로 떨어지지 않는다', () {
      final ExerciseSession session = ExerciseSession.fromJson(
        <String, Object?>{
          'day_label': '월',
          'type': '유산소',
          'minutes': 20,
          'calories': 180,
        },
      );
      expect(session.type, ExerciseType.cardio);
    });
  });

  group('조언 문장의 유형 라벨 — 서버 normalize_ko 와 같다', () {
    for (final List<Object?> r in rows.where((r) => r[0] != null)) {
      test('${show(r[0])} → ${r[2]}', () {
        expect(exerciseTypeLabel(r[0]! as String), r[2]);
      });
    }
  });

  group('데모 서버 주간 운동 — 한글·옛 유형 기록도 제 칸에 든다', () {
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

    String currentMonday() {
      final DateTime now = nowKst();
      final DateTime m = DateTime(
        now.year,
        now.month,
        now.day - (now.weekday - 1),
      );
      return '${m.year.toString().padLeft(4, '0')}-'
          '${m.month.toString().padLeft(2, '0')}-'
          '${m.day.toString().padLeft(2, '0')}';
    }

    for (final (String type, String key) in <(String, String)>[
      ('유산소', 'cardio_minutes'),
      ('걷기', 'cardio_minutes'),
      ('근력', 'strength_minutes'),
      ('스트레칭', 'stretching_minutes'),
      ('요가', 'stretching_minutes'),
      ('유연성', 'stretching_minutes'),
      ('crossfit', 'other_minutes'),
    ]) {
      test('$type 기록은 $key 에 센다', () async {
        await db
            .into(db.exerciseSessions)
            .insert(
              ExerciseSessionsCompanion.insert(
                id: 'ex-type-$type',
                weekStart: currentMonday(),
                dayLabel: '월',
                type: type,
                minutes: 25,
                calories: 100,
              ),
            );
        final Response<Map<String, Object?>> res = await dio
            .get<Map<String, Object?>>('/exercise/weeks/current');
        final Map<String, Object?> body = res.data!;
        for (final String k in <String>[
          'cardio_minutes',
          'strength_minutes',
          'stretching_minutes',
          'other_minutes',
        ]) {
          final List<num> series = (body[k]! as List<Object?>)
              .cast<num>()
              .toList();
          expect(series.first, k == key ? 25 : 0, reason: k);
        }
      });
    }
  });

  group('데모 kcal 추정 — 한글 유형도 제 단가', () {
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

    test('유산소는 cardio 와 같은 분당 9kcal 이다', () async {
      Future<Object?> kcal(String type) async =>
          (await dio.post<Map<String, Object?>>(
            '/exercise/calories',
            data: <String, Object?>{
              'type': type,
              'name': '종목표에없는운동이름',
              'minutes': 10,
              'intensity': 'moderate',
            },
          )).data!['calories'];
      expect(await kcal('유산소'), 90);
      expect(await kcal('cardio'), 90);
      expect(await kcal('요가'), 30);
      expect(await kcal('crossfit'), 50);
    });
  });
}

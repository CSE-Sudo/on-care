import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/demo/diet_advice.dart' show pyRound;
import 'package:oncare/core/demo/exercise_catalog_demo.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare_rules/oncare_rules.dart' show minutesFromSeconds;

import '../../helpers/exercise_session_post.dart';
import '../../helpers/shared_rule_vectors.dart';

/// 운동 분·kcal 반올림이 서버(Python `round`)와 같은가 — 입력 시트·데모 서버·
/// 식단 조언이 한 함수를 쓴다(#2860).
void main() {
  final Map<String, Object?> vectors = loadSharedRuleVectors('rounding');

  group('공용 반올림 — 서버와 같은 입력 표', () {
    for (final (Object? x, Object? expected) in vectorPairs(
      vectors,
      'py_round',
    )) {
      test('pyRound($x) == $expected', () {
        expect(pyRound(x! as num), expected);
      });
    }

    for (final (Object? seconds, Object? minutes) in vectorPairs(
      vectors,
      'minutes_from_seconds',
    )) {
      test('$seconds초 → $minutes분', () {
        expect(minutesFromSeconds(seconds! as int), minutes);
      });
    }
  });

  group('폴백 kcal 추정 — 서버 energy.fallback 과 같다', () {
    for (final Map<String, Object?> c in vectorRows(
      vectors,
      'fallback_calories',
    )) {
      test('${c['type']} ${c['minutes']}분 ${c['intensity']} → '
          '${c['calories']}kcal', () {
        expect(
          estimateExerciseCalories(
            exerciseTypeFromLabel(c['type']! as String),
            c['minutes']! as int,
            intensity: exerciseIntensityFromLabel(c['intensity']! as String),
          ),
          c['calories'],
        );
      });
    }

    test('절반에서 짝수 쪽으로 간다 — 기타 2분 가벼움은 8.5 → 8', () {
      expect(
        estimateExerciseCalories(
          ExerciseType.other,
          2,
          intensity: ExerciseIntensity.light,
        ),
        8,
      );
    });
  });

  group('데모 종목 kcal — 서버 from_catalog 와 같은 식', () {
    test('정확히 절반이면 짝수 쪽이다', () {
      // met 5 × 보통 1.0 × 51kg × (2분 / 60) = 8.5 → 8, 6분이면 25.5 → 26.
      const DemoExerciseActivity activity = DemoExerciseActivity(
        '테스트 종목',
        'cardio',
        5,
        <String>[],
      );
      expect(demoCatalogCalories(activity, 2, 1.0, 51), 8);
      expect(demoCatalogCalories(activity, 6, 1.0, 51), 26);
    });

    test('음수 분은 0kcal 이다', () {
      const DemoExerciseActivity activity = DemoExerciseActivity(
        '테스트 종목',
        'cardio',
        5,
        <String>[],
      );
      expect(demoCatalogCalories(activity, -3, 1.0, 70), 0);
    });
  });

  group('데모 서버 — 실서버와 같은 분·kcal', () {
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

    for (final (Object? seconds, Object? minutes) in vectorPairs(
      vectors,
      'minutes_from_seconds',
    ).where(((Object?, Object?) p) => (p.$1! as int) > 0)) {
      test('초 $seconds 로 저장하면 $minutes분이 된다', () async {
        final Response<Map<String, Object?>> res = await postExerciseSession(
          dio,
          <String, Object?>{
            'type': 'cardio',
            'name': '러닝머신',
            'duration_seconds': seconds,
          },
        );
        expect(res.data!['minutes'], minutes);
      });
    }

    for (final Map<String, Object?> c in vectorRows(
      vectors,
      'fallback_calories',
    ).where((Map<String, Object?> c) => (c['minutes']! as int) > 0)) {
      test('이름이 종목에 붙지 않으면 유형 평균 — ${c['type']} '
          '${c['minutes']}분 ${c['intensity']}', () async {
        final Response<Map<String, Object?>> res = await dio
            .post<Map<String, Object?>>(
              '/exercise/calories',
              data: <String, Object?>{
                'type': c['type'],
                'name': '종목표에없는운동이름',
                'minutes': c['minutes'],
                'intensity': c['intensity'],
              },
            );
        expect(res.data!['source'], 'estimate');
        expect(res.data!['calories'], c['calories']);
      });
    }
  });
}

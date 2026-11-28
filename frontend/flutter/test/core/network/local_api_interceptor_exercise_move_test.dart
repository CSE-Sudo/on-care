/// 로컬 목업 API 가 운동 기록 묶음 이동과 `전체` 조언 기간에서 실서버와 같은
/// 규칙을 쓴다 — #3365.
///
/// - `POST /exercise/sessions/move` 는 전부 옮기거나 전부 그대로 둔다.
/// - `GET /exercise/advice?period=all` 은 `전체` 그래프(`GET /exercise/weeks`)와
///   같은 첫 기록 주부터 세고, "○주 동안" 이 그 주 수다.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_limits.dart';

import '../../helpers/fixed_clock.dart';

/// 2026-09-17 (목).
final DateTime _thursday = DateTime(2026, 9, 17, 10);
const String _today = '2026-09-17';
const String _thisMonday = '2026-09-14';

/// 지난주 화요일 — 다른 주로 옮기는 것까지 본다.
const String _lastTuesday = '2026-09-08';

final Options _anyStatus = Options(validateStatus: (int? s) => true);

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    useFixedKstDate(_thursday);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<void> insert(
    String id, {
    String weekStart = _thisMonday,
    String dayLabel = '목',
    String name = '걷기',
    int minutes = 30,
    int calories = 123,
    String source = 'member',
  }) => db
      .into(db.exerciseSessions)
      .insert(
        ExerciseSessionsCompanion.insert(
          id: id,
          weekStart: weekStart,
          dayLabel: dayLabel,
          type: 'cardio',
          minutes: minutes,
          calories: calories,
          name: Value(name),
          source: Value(source),
        ),
      );

  /// 그 주의 기록 id → 날짜.
  Future<Map<String, Object?>> datesIn(String weekStart) async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>(
          '/exercise/weeks/current',
          queryParameters: <String, Object?>{'week_start': weekStart},
        );
    return <String, Object?>{
      for (final Map<String, Object?> s
          in (res.data!['sessions']! as List<Object?>)
              .cast<Map<String, Object?>>())
        s['id']! as String: s['date'],
    };
  }

  Future<Response<Map<String, Object?>>> move(Object? ids, Object? date) =>
      dio.post<Map<String, Object?>>(
        '/exercise/sessions/move',
        data: <String, Object?>{'session_ids': ids, 'date': ?date},
        options: _anyStatus,
      );

  group('POST /exercise/sessions/move', () {
    test('기록들을 고른 날로 한 번에 옮기고 요청 순서로 돌려준다', () async {
      await insert('ex-a', name: '러닝머신');
      await insert('ex-b', name: '사이클');

      final Response<Map<String, Object?>> res = await move(<String>[
        'ex-b',
        'ex-a',
      ], _lastTuesday);

      expect(res.statusCode, 200);
      final List<Map<String, Object?>> sessions =
          (res.data!['sessions']! as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(sessions.map((Map<String, Object?> s) => s['id']), <String>[
        'ex-b',
        'ex-a',
      ]);
      expect(
        sessions.map((Map<String, Object?> s) => s['date']),
        everyElement(_lastTuesday),
      );
      expect(await datesIn(_thisMonday), isEmpty);
      expect(await datesIn('2026-09-07'), <String, Object?>{
        'ex-a': _lastTuesday,
        'ex-b': _lastTuesday,
      });
    });

    test('날짜 말고는 그대로다 — 칼로리를 다시 계산하지 않는다', () async {
      await insert('ex-a', name: '러닝머신', minutes: 45, calories: 321);

      final Response<Map<String, Object?>> res = await move(<String>[
        'ex-a',
      ], _lastTuesday);

      final Map<String, Object?> moved =
          (res.data!['sessions']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(moved['name'], '러닝머신');
      expect(moved['minutes'], 45);
      expect(moved['calories'], 321);
      expect(moved['source'], 'member');
    });

    test('같은 요청을 다시 보내도 결과가 같다', () async {
      await insert('ex-a');

      final Response<Map<String, Object?>> first = await move(<String>[
        'ex-a',
      ], _lastTuesday);
      final Response<Map<String, Object?>> again = await move(<String>[
        'ex-a',
      ], _lastTuesday);

      expect(again.statusCode, 200);
      expect(again.data, first.data);
      expect(await datesIn('2026-09-07'), <String, Object?>{
        'ex-a': _lastTuesday,
      });
    });

    test('같은 id 가 두 번 와도 한 번만 옮긴다', () async {
      await insert('ex-a');

      final Response<Map<String, Object?>> res = await move(<String>[
        'ex-a',
        'ex-a',
      ], _lastTuesday);

      expect(res.statusCode, 200);
      expect(res.data!['sessions'], hasLength(1));
    });

    test('없는 기록이 섞이면 404 이고 아무것도 옮기지 않는다', () async {
      await insert('ex-a');

      final Response<Map<String, Object?>> res = await move(<String>[
        'ex-a',
        'ex-missing',
      ], _lastTuesday);

      expect(res.statusCode, 404);
      expect(await datesIn(_thisMonday), <String, Object?>{'ex-a': _today});
      expect(await datesIn('2026-09-07'), isEmpty);
    });

    for (final String source in <String>['trainer_pt', 'assigned_routine']) {
      test('$source 기록이 섞이면 단건 수정처럼 409 이고 전부 그대로다', () async {
        await insert('ex-a');
        await insert('ex-derived', source: source);

        final Response<Map<String, Object?>> res = await move(<String>[
          'ex-a',
          'ex-derived',
        ], _lastTuesday);

        expect(res.statusCode, 409);
        expect(await datesIn(_thisMonday), <String, Object?>{
          'ex-a': _today,
          'ex-derived': _today,
        });
        expect(await datesIn('2026-09-07'), isEmpty);
      });
    }

    test('앞날로는 옮기지 못한다 — 단건 수정과 같은 422', () async {
      await insert('ex-a');

      final Response<Map<String, Object?>> res = await move(<String>[
        'ex-a',
      ], '2026-09-18');

      expect(res.statusCode, 422);
      expect(res.data!['detail'], 'date 는 오늘보다 뒤일 수 없어요.');
      expect(await datesIn(_thisMonday), <String, Object?>{'ex-a': _today});
    });

    test('모양이 틀린 요청은 422 다', () async {
      await insert('ex-a');

      expect((await move(<String>[], _lastTuesday)).statusCode, 422);
      expect((await move('ex-a', _lastTuesday)).statusCode, 422);
      expect((await move(<String>['ex-a'], null)).statusCode, 422);
      expect((await move(<String>['ex-a'], 'next-monday')).statusCode, 422);
      expect(
        (await move(<String>[
          for (int i = 0; i <= kMaxExerciseSessionsPerMove; i++) 'ex-$i',
        ], _lastTuesday)).statusCode,
        422,
      );
      expect(await datesIn(_thisMonday), <String, Object?>{'ex-a': _today});
    });
  });

  group('GET /exercise/advice?period=all', () {
    Future<Map<String, Object?>> advice([String period = 'all']) async =>
        (await dio.get<Map<String, Object?>>(
          '/exercise/advice',
          queryParameters: <String, Object?>{'period': period},
        )).data!;

    Future<Map<String, Object?>> graph() async =>
        (await dio.get<Map<String, Object?>>('/exercise/weeks')).data!;

    test('12주보다 오래된 기록도 세고, 그래프와 같은 주부터다', () async {
      // 28주 전 수요일 · 14주 전 수요일 · 오늘.
      await insert('ex-old', weekStart: '2026-03-02', dayLabel: '수');
      await insert('ex-mid', weekStart: '2026-06-08', dayLabel: '수');
      await insert('ex-now');

      final Map<String, Object?> body = await advice();
      final Map<String, Object?> weeks = await graph();

      expect(body['from_date'], '2026-03-02');
      expect(body['from_date'], weeks['from_week']);
      expect(body['to_date'], _today);
      expect(body['days_logged'], 3);
      expect(body['advice_key'], 'record_all_steady');
      final Map<String, Object?> params =
          body['advice_params']! as Map<String, Object?>;
      expect(params['weeks'], 29);
      expect(params['weeks'], (weeks['weeks']! as List<Object?>).length);
      expect(body['message'], contains('29주 동안'));
    });

    test('막 시작한 회원에게 12주라고 하지 않는다', () async {
      await insert('ex-last', weekStart: '2026-09-07', dayLabel: '수');
      await insert('ex-now');

      final Map<String, Object?> body = await advice();

      expect(body['from_date'], '2026-09-07');
      expect((body['advice_params']! as Map<String, Object?>)['weeks'], 2);
      expect(body['message'], contains('2주 동안'));
    });

    test('기록이 없으면 그래프의 한 칸과 같은 이번 주다', () async {
      final Map<String, Object?> body = await advice();

      expect(body['from_date'], _thisMonday);
      expect(body['from_date'], (await graph())['from_week']);
      expect(body['days_logged'], 0);
      expect(body['advice_key'], 'record_empty_all');
    });

    test('오늘·이번 주의 구간은 그대로다', () async {
      await insert('ex-old', weekStart: '2026-03-02', dayLabel: '수');
      await insert('ex-now');

      final Map<String, Object?> week = await advice('week');
      final Map<String, Object?> today = await advice('today');

      expect(week['from_date'], _thisMonday);
      expect(week['days_logged'], 1);
      expect(today['from_date'], _today);
      expect(today['days_logged'], 1);
    });
  });
}

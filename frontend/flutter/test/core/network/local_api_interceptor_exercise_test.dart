import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare_core/clock.dart';
import '../../helpers/exercise_session_post.dart';
import '../../helpers/fixed_clock.dart';

/// 기준일 — 2026-08-23 (일) 저녁. 이번 주 월~일이 모두 오늘까지라, 요일로
/// 고른 기록 날짜가 실행 요일에 따라 앞날(422, #3042)이 되지 않는다.
final DateTime _sundayEvening = DateTime(2026, 8, 23, 20);

String _currentMonday() {
  final now = nowKst();
  final m = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  return _ymd(m);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 이번 주 `label` 요일의 날짜. 기록은 요일이 아니라 날짜로 보낸다 (#1276).
String _day(String label) {
  final DateTime monday = DateTime.parse(_currentMonday());
  final int index = <String>['월', '화', '수', '목', '금', '토', '일'].indexOf(label);
  return _ymd(DateTime(monday.year, monday.month, monday.day + index));
}

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() async {
    useFixedKstDate(_sundayEvening);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));

    // Seed a few sessions for the current week — same shape the
    // production `seedIfEmpty` would have written.
    final ws = _currentMonday();
    await db.batch((b) {
      b.insertAll(db.exerciseSessions, <ExerciseSessionsCompanion>[
        ExerciseSessionsCompanion.insert(
          id: 'ex-mon',
          weekStart: ws,
          dayLabel: '월',
          type: 'cardio',
          minutes: 30,
          calories: 250,
        ),
        ExerciseSessionsCompanion.insert(
          id: 'ex-wed',
          weekStart: ws,
          dayLabel: '수',
          type: 'strength',
          minutes: 45,
          calories: 320,
        ),
        ExerciseSessionsCompanion.insert(
          id: 'ex-fri',
          weekStart: ws,
          dayLabel: '금',
          type: 'cardio',
          minutes: 60,
          calories: 480,
        ),
      ]);
    });
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  test(
    'GET /exercise/weeks/current aggregates daily minutes Mon..Sun',
    () async {
      final res = await dio.get<Map<String, Object?>>(
        '/exercise/weeks/current',
      );
      expect(res.statusCode, 200);
      final body = res.data!;

      final daily = (body['daily_minutes']! as List<Object?>)
          .cast<num>()
          .toList();
      // Mon=30, Tue=0, Wed=45, Thu=0, Fri=60, Sat=0, Sun=0.
      expect(daily, <num>[30, 0, 45, 0, 60, 0, 0]);

      expect(body['total_minutes'], 135);
      expect(body['total_calories'], 1050);
      // "N일 연속" = 가장 긴 연속 구간. 월·수·금은 서로 떨어져 있으므로 활성
      // 일수는 3이지만 연속은 1이다.
      expect(body['streak_days'], 1);
      // Day labels are always Mon..Sun in Korean.
      expect(body['day_labels'], <String>['월', '화', '수', '목', '금', '토', '일']);
    },
  );

  test('weeks/current ignores rows from other weeks', () async {
    // Inject a row tagged to a different weekStart — it shouldn't show up.
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'ex-old',
            weekStart: '2000-01-03', // arbitrary Monday in the past
            dayLabel: '월',
            type: 'cardio',
            minutes: 999,
            calories: 9999,
          ),
        );
    final res = await dio.get<Map<String, Object?>>('/exercise/weeks/current');
    final daily = (res.data!['daily_minutes']! as List<Object?>)
        .cast<num>()
        .toList();
    expect(daily.first, 30); // monday still 30 — old row was filtered out
  });

  test('weeks/current returns zeros + empty list when no rows', () async {
    // Fresh DB with no inserts.
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final freshDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    addTearDown(() async {
      freshDio.close();
    });
    freshDio.interceptors.add(
      LocalApiInterceptor(db, Logger(level: Level.off)),
    );
    final res = await freshDio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
    );
    final body = res.data!;
    expect(body['total_minutes'], 0);
    expect(body['total_calories'], 0);
    expect(body['streak_days'], 0);
    expect((body['sessions']! as List<Object?>), isEmpty);
  });

  test(
    'POST /exercise/sessions persists and shows up in weeks/current',
    () async {
      final add = await postExerciseSession(dio, <String, Object?>{
        'type': 'cardio',
        'minutes': 40,
        'calories': 300,
        'date': _day('화'),
      });
      expect(add.statusCode, 200);
      expect(add.data!['type'], 'cardio');
      expect(add.data!['minutes'], 40);
      expect(add.data!['day_label'], '화');
      expect(add.data!['date_label'], isNotNull);

      // 재조회 시 화요일(0→40) 반영, 합계 증가(135→175).
      final res = await dio.get<Map<String, Object?>>(
        '/exercise/weeks/current',
      );
      final daily = (res.data!['daily_minutes']! as List<Object?>)
          .cast<num>()
          .toList();
      expect(daily, <num>[30, 40, 45, 0, 60, 0, 0]);
      expect(res.data!['total_minutes'], 175);
    },
  );

  test('POST/PUT /exercise/sessions round-trips intensity', () async {
    final add = await postExerciseSession(dio, <String, Object?>{
      'type': 'strength',
      'minutes': 40,
      'calories': 300,
      'intensity': 'high',
      'date': _day('화'),
    });
    expect(add.data!['intensity'], 'high');
    final String id = add.data!['id']! as String;

    // GET week echoes the saved intensity for that session.
    final week = await dio.get<Map<String, Object?>>('/exercise/weeks/current');
    final sessions = (week.data!['sessions']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final added = sessions.firstWhere((s) => s['id'] == id);
    expect(added['intensity'], 'high');

    // Editing to a lower intensity persists.
    final put = await dio.put<Map<String, Object?>>(
      '/exercise/sessions/$id',
      data: <String, Object?>{
        'type': 'strength',
        'minutes': 40,
        'calories': 250,
        'intensity': 'light',
        'date': _day('화'),
      },
    );
    expect(put.data!['intensity'], 'light');
  });

  test('POST /exercise/sessions defaults intensity to moderate', () async {
    final add = await postExerciseSession(dio, <String, Object?>{
      'type': 'cardio',
      'minutes': 20,
      'date': _day('목'),
    });
    expect(add.data!['intensity'], 'moderate');
  });

  test('POST /exercise/sessions rejects non-positive minutes', () async {
    final res = await postExerciseSession(dio, <String, Object?>{
      'type': 'cardio',
      'minutes': 0,
    }, options: Options(validateStatus: (int? s) => true));
    // 실 서버처럼 항목 검증 실패는 422 다(#2544).
    expect(res.statusCode, 422);
  });

  test('POST /exercise/sessions 는 여러 건을 요청 순서대로 저장한다 (#2544)', () async {
    final Response<Map<String, Object?>> res = await dio
        .post<Map<String, Object?>>(
          '/exercise/sessions',
          data: <String, Object?>{
            'sessions': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'cardio',
                'name': '러닝머신',
                'duration_seconds': 1800,
                'date': _day('화'),
              },
              <String, Object?>{
                'type': 'strength',
                'name': '스쿼트',
                'minutes': 12,
                'sets': 3,
                'reps': 10,
                'date': _day('화'),
              },
            ],
          },
        );
    final List<Object?> sessions = res.data!['sessions']! as List<Object?>;
    expect(
      sessions.map((Object? s) => (s! as Map<String, Object?>)['name']),
      <String>['러닝머신', '스쿼트'],
    );
    final Set<Object?> ids = sessions
        .map((Object? s) => (s! as Map<String, Object?>)['id'])
        .toSet();
    expect(ids, hasLength(2));

    final week = await dio.get<Map<String, Object?>>('/exercise/weeks/current');
    final List<Object?> saved = week.data!['sessions']! as List<Object?>;
    expect(
      saved.map((Object? s) => (s! as Map<String, Object?>)['id']),
      containsAll(ids),
    );
  });

  test('항목 하나가 잘못되면 아무것도 저장하지 않는다 (#2544)', () async {
    final before = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
    );
    final int count = (before.data!['sessions']! as List<Object?>).length;
    final res = await dio.post<Map<String, Object?>>(
      '/exercise/sessions',
      data: <String, Object?>{
        'sessions': <Map<String, Object?>>[
          <String, Object?>{'type': 'cardio', 'minutes': 20, 'date': _day('수')},
          <String, Object?>{'type': 'cardio', 'minutes': 0, 'date': _day('수')},
        ],
      },
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 422);
    final after = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
    );
    expect((after.data!['sessions']! as List<Object?>).length, count);
  });

  test('빈 목록과 단건 몸통은 거절한다 (#2544)', () async {
    for (final Map<String, Object?> body in <Map<String, Object?>>[
      <String, Object?>{'sessions': <Object?>[]},
      <String, Object?>{'type': 'cardio', 'minutes': 20},
    ]) {
      final res = await dio.post<Map<String, Object?>>(
        '/exercise/sessions',
        data: body,
        options: Options(validateStatus: (int? s) => true),
      );
      expect(res.statusCode, 422);
    }
  });

  test('week_start 로 지난 주를 조회한다 (#671)', () async {
    // 지난 주 월요일에 세션 하나. 이번 주 시드와 섞이면 안 된다.
    final DateTime lastMonday = DateTime.parse(
      _currentMonday(),
    ).subtract(const Duration(days: 7));
    final String lastWeek =
        '${lastMonday.year.toString().padLeft(4, '0')}-'
        '${lastMonday.month.toString().padLeft(2, '0')}-'
        '${lastMonday.day.toString().padLeft(2, '0')}';
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'ex-last-mon',
            weekStart: lastWeek,
            dayLabel: '월',
            type: 'cardio',
            minutes: 20,
            calories: 140,
          ),
        );

    final res = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
      queryParameters: <String, Object?>{'week_start': lastWeek},
    );
    expect(res.data!['total_minutes'], 20);
    expect((res.data!['sessions']! as List<Object?>).length, 1);

    // 파라미터가 없으면 예전 그대로 이번 주다.
    final current = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
    );
    expect(current.data!['total_minutes'], isNot(20));
  });

  test('지난 주 세션의 date_label 은 오늘/어제로 잘못 붙지 않는다 (#671)', () async {
    final DateTime lastMonday = DateTime.parse(
      _currentMonday(),
    ).subtract(const Duration(days: 7));
    final String lastWeek =
        '${lastMonday.year.toString().padLeft(4, '0')}-'
        '${lastMonday.month.toString().padLeft(2, '0')}-'
        '${lastMonday.day.toString().padLeft(2, '0')}';
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'ex-last-tue',
            weekStart: lastWeek,
            dayLabel: '화',
            type: 'cardio',
            minutes: 30,
            calories: 200,
          ),
        );

    final res = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
      queryParameters: <String, Object?>{'week_start': lastWeek},
    );
    final sessions = (res.data!['sessions']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final DateTime lastTuesday = lastMonday.add(const Duration(days: 1));
    expect(
      sessions.single['date_label'],
      '${lastTuesday.month}월 ${lastTuesday.day}일',
    );
  });

  test('week_start 로 월요일이 아닌 날을 줘도 그 주로 맞춘다 (#671)', () async {
    // 서버(FastAPI)가 monday_of_str 로 맞추므로 목업도 같아야 한다.
    final DateTime lastMonday = DateTime.parse(
      _currentMonday(),
    ).subtract(const Duration(days: 7));
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final String lastWeek = fmt(lastMonday);
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'ex-last-wed',
            weekStart: lastWeek,
            dayLabel: '수',
            type: 'cardio',
            minutes: 35,
            calories: 240,
          ),
        );

    // 그 주의 목요일을 넘긴다.
    final res = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
      queryParameters: <String, Object?>{
        'week_start': fmt(lastMonday.add(const Duration(days: 3))),
      },
    );
    expect(res.data!['total_minutes'], 35);
  });

  test('week_start 형식이 깨지면 422 다 (서버와 같은 코드)', () async {
    final res = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
      queryParameters: <String, Object?>{'week_start': 'not-a-date'},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 422);
  });

  test('week_start 가 빈 문자열이어도 조용히 이번 주로 넘어가지 않는다', () async {
    // FastAPI 는 빈 값에 422 를 준다. 목업이 이번 주를 돌려주면 두 구현이 갈린다.
    final res = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
      queryParameters: <String, Object?>{'week_start': ''},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 422);
  });

  test('ISO 기본 형식(20260810)은 받지 않는다', () async {
    final res = await dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
      queryParameters: <String, Object?>{'week_start': '20260810'},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 422);
  });

  // --- 근력 세트 (#1262) ------------------------------------------------

  test('POST /exercise/sessions 는 근력 세트를 그대로 저장한다', () async {
    final res = await postExerciseSession(dio, <String, Object?>{
      'type': 'strength',
      'minutes': 36,
      'sets': 12,
      'calories': 216,
      'date': _day('화'),
    });
    expect(res.data!['sets'], 12);

    final week = await dio.get<Map<String, Object?>>('/exercise/weeks/current');
    final sets = (week.data!['strength_sets']! as List).cast<num>();
    // 화요일에 방금 적은 12세트 + 수요일 시드(45분 → 15세트).
    expect(sets[1], 12);
    expect(sets[2], 15);
  });

  test('세트를 안 보낸 근력 기록은 분에서 환산해 센다', () async {
    final res = await postExerciseSession(dio, <String, Object?>{
      'type': 'strength',
      'minutes': 30,
      'calories': 180,
      'date': _day('목'),
    });
    expect(res.data!['sets'], isNull);

    final week = await dio.get<Map<String, Object?>>('/exercise/weeks/current');
    final sets = (week.data!['strength_sets']! as List).cast<num>();
    expect(sets[3], 10); // 30분 ÷ 3분
  });

  test('근력이 아닌 기록에는 세트를 남기지 않는다', () async {
    final res = await postExerciseSession(dio, <String, Object?>{
      'type': 'cardio',
      'minutes': 30,
      'sets': 12,
      'calories': 270,
      'date': _day('토'),
    });
    expect(res.data!['sets'], isNull);
  });

  test('PUT 으로 유형을 바꾸면 세트가 지워진다', () async {
    final id =
        (await postExerciseSession(dio, <String, Object?>{
              'type': 'strength',
              'minutes': 36,
              'sets': 12,
              'calories': 216,
              'date': _day('일'),
            })).data!['id']!
            as String;

    final res = await dio.put<Map<String, Object?>>(
      '/exercise/sessions/$id',
      data: <String, Object?>{
        'type': 'cardio',
        'minutes': 36,
        'sets': null,
        'calories': 324,
        'date': _day('일'),
      },
    );
    expect(res.data!['sets'], isNull);
  });

  group('앞날 기록 (#3042)', () {
    final Options anyStatus = Options(validateStatus: (int? s) => true);
    // 기준일(일요일)의 다음 날 — 다음 주 월요일.
    const String tomorrow = '2026-08-24';

    Future<int> sessionCount() async {
      final week = await dio.get<Map<String, Object?>>(
        '/exercise/weeks/current',
      );
      return (week.data!['sessions']! as List<Object?>).length;
    }

    test('오늘보다 뒤 날짜의 추가는 422 이고 아무것도 남지 않는다', () async {
      final int before = await sessionCount();
      final res = await postExerciseSession(dio, <String, Object?>{
        'type': 'cardio',
        'minutes': 20,
        'date': tomorrow,
      }, options: anyStatus);
      expect(res.statusCode, 422);
      // 식단 기록과 같은 문구다.
      expect(res.data!['detail'], 'date 는 오늘보다 뒤일 수 없어요.');
      expect(await sessionCount(), before);
      final next = await dio.get<Map<String, Object?>>(
        '/exercise/weeks/current',
        queryParameters: <String, Object?>{'week_start': tomorrow},
      );
      expect(next.data!['sessions'], isEmpty);
    });

    test('여러 건 중 하나만 앞날이어도 전체가 422 다', () async {
      final int before = await sessionCount();
      final res = await dio.post<Map<String, Object?>>(
        '/exercise/sessions',
        data: <String, Object?>{
          'sessions': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'cardio',
              'minutes': 20,
              'date': _day('일'),
            },
            <String, Object?>{
              'type': 'cardio',
              'minutes': 20,
              'date': tomorrow,
            },
          ],
        },
        options: anyStatus,
      );
      expect(res.statusCode, 422);
      expect(await sessionCount(), before);
    });

    test('오늘·지난 날짜와 날짜 생략은 그대로 저장된다', () async {
      for (final Object? date in <Object?>[_day('일'), _day('월'), null]) {
        final res = await postExerciseSession(dio, <String, Object?>{
          'type': 'cardio',
          'minutes': 20,
          'date': ?date,
        });
        expect(res.statusCode, 200, reason: '$date');
        expect(res.data!['day_label'], date == _day('월') ? '월' : '일');
      }
    });

    test('기록을 앞날로 옮기는 수정은 422 이고 원래 날짜가 남는다', () async {
      final res = await dio.put<Map<String, Object?>>(
        '/exercise/sessions/ex-wed',
        data: <String, Object?>{
          'type': 'strength',
          'minutes': 45,
          'date': tomorrow,
        },
        options: anyStatus,
      );
      expect(res.statusCode, 422);
      final week = await dio.get<Map<String, Object?>>(
        '/exercise/weeks/current',
      );
      final Map<String, Object?> wed =
          (week.data!['sessions']! as List<Object?>)
              .cast<Map<String, Object?>>()
              .firstWhere((s) => s['id'] == 'ex-wed');
      expect(wed['day_label'], '수');
      expect(wed['minutes'], 45);
    });

    test('지난 날짜로 옮기는 수정과 날짜 없는 수정은 된다', () async {
      final moved = await dio.put<Map<String, Object?>>(
        '/exercise/sessions/ex-wed',
        data: <String, Object?>{
          'type': 'strength',
          'minutes': 45,
          'date': _day('화'),
        },
      );
      expect(moved.statusCode, 200);
      expect(moved.data!['day_label'], '화');

      final kept = await dio.put<Map<String, Object?>>(
        '/exercise/sessions/ex-fri',
        data: <String, Object?>{'type': 'cardio', 'minutes': 50},
      );
      expect(kept.statusCode, 200);
      expect(kept.data!['day_label'], '금');
    });

    test('형식이 깨진 날짜는 422 다 (서버와 같은 코드)', () async {
      final res = await postExerciseSession(dio, <String, Object?>{
        'type': 'cardio',
        'minutes': 20,
        'date': '20260823',
      }, options: anyStatus);
      expect(res.statusCode, 422);
    });
  });
}

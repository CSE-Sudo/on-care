/// 데모 백엔드의 식단 저장 규칙 — 날짜 하한·끼니 시각·홈 경고의 음식 이름. (#3354)
///
/// 실서버와 같은 규칙이어야 한다. 데모에서만 통과하면 실연동에서 그 화면이 처음
/// 실패하고, 데모에서만 다르게 보이면 시연 화면이 실제와 어긋난다.
///
/// - 직접 입력·수정의 날짜도 사진 분석처럼 작년 1월 1일보다 앞설 수 없다.
/// - 지난 날짜에 적는 끼니의 시각은 적는 시각이 아니라 끼니 종류의 기본 시각이다.
/// - 홈 나트륨 경고는 음식을 저장된 이름으로 짚는다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

import '../../helpers/fixed_clock.dart';

final Uint8List _jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);

const List<Map<String, Object?>> _foods = <Map<String, Object?>>[
  <String, Object?>{'name': '김밥', 'calories': 420, 'sodium_mg': 900},
];

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    // 오늘은 2026-08-20(목) 23:05 — 어제 아침을 밤 11시에 적는 때다.
    useFixedKstDate(DateTime(2026, 8, 20, 23, 5));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test',
        validateStatus: (int? _) => true,
      ),
    );
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<Response<Map<String, Object?>>> create({
    String? date,
    String mealType = 'lunch',
    List<Map<String, Object?>> foods = _foods,
  }) => dio.post<Map<String, Object?>>(
    '/diet/entries',
    data: <String, Object?>{
      'date': ?date,
      'meal_type': mealType,
      'foods': foods,
    },
  );

  Future<Response<Map<String, Object?>>> analyze({
    String? date,
    String mealType = 'lunch',
  }) => dio.post<Map<String, Object?>>(
    '/diet/analyze',
    data: FormData.fromMap(<String, Object?>{
      'image': MultipartFile.fromBytes(_jpeg, filename: 'meal.jpg'),
      'meal_type': mealType,
      'date': ?date,
    }),
  );

  Future<List<Map<String, Object?>>> entriesOn(String day) async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/diet/days/$day');
    return (res.data!['entries']! as List<Object?>)
        .cast<Map<String, Object?>>();
  }

  group('날짜 하한', () {
    test('직접 입력은 작년 1월 1일까지 받고, 그보다 앞선 날은 422', () async {
      expect((await create(date: '2025-01-01')).statusCode, 201);

      final Response<Map<String, Object?>> tooOld = await create(
        date: '2024-12-31',
      );

      expect(tooOld.statusCode, 422);
      expect(await entriesOn('2024-12-31'), isEmpty);
    });

    test('수정으로도 하한보다 앞선 날에 옮기지 못한다', () async {
      final String id = (await create()).data!['id']! as String;

      final Response<Map<String, Object?>> moved = await dio
          .put<Map<String, Object?>>(
            '/diet/entries/$id',
            data: <String, Object?>{'date': '2024-12-31'},
          );

      expect(moved.statusCode, isNot(200));
      expect(
        (await entriesOn(
          '2026-08-20',
        )).map((Map<String, Object?> e) => e['id']),
        <Object?>[id],
      );
      expect(await entriesOn('2024-12-31'), isEmpty);
    });

    test('사진 분석의 하한은 그대로다', () async {
      expect((await analyze(date: '2025-01-01')).statusCode, 200);
      expect((await analyze(date: '2024-12-31')).statusCode, 422);
    });
  });

  group('끼니 시각', () {
    test('지난 날짜에 직접 적은 끼니는 끼니 종류의 기본 시각이다', () async {
      const Map<String, String> expected = <String, String>{
        'breakfast': '08:00',
        'lunch': '12:00',
        'snack': '15:00',
        'dinner': '18:00',
        'lateNight': '22:00',
      };
      int minute = 5;
      for (final MapEntry<String, String> meal in expected.entries) {
        // 데모 기록의 id 는 저장 시각에서 나온다 — 끼니마다 시각을 달리한다.
        useFixedKstDate(DateTime(2026, 8, 20, 23, minute++));
        final Response<Map<String, Object?>> res = await create(
          date: '2026-08-19',
          mealType: meal.key,
        );
        expect(res.statusCode, 201);
        expect(res.data!['time_label'], meal.value, reason: meal.key);
      }
    });

    test('오늘 적은 끼니는 적은 시각이다', () async {
      expect((await create()).data!['time_label'], '23:05');
      // 오늘 날짜를 직접 실어도 같다.
      useFixedKstDate(DateTime(2026, 8, 20, 23, 6));
      expect((await create(date: '2026-08-20')).data!['time_label'], '23:06');
    });

    test('지난 날짜의 사진 분석도 끼니의 기본 시각이고 목록과 같다', () async {
      final Response<Map<String, Object?>> res = await analyze(
        date: '2026-08-19',
        mealType: 'breakfast',
      );

      expect(res.statusCode, 200);
      expect(res.data!['time_label'], '08:00');
      expect((await entriesOn('2026-08-19')).single['time_label'], '08:00');
    });

    test('오늘의 사진 분석은 적은 시각이다', () async {
      expect((await analyze()).data!['time_label'], '23:05');
    });
  });

  group('홈 나트륨 경고의 음식 이름', () {
    const List<Map<String, Object?>> salty = <Map<String, Object?>>[
      <String, Object?>{
        'name': '라면',
        'display_name': 'Ramyeon',
        'calories': 500,
        'sodium_mg': 1800,
      },
      <String, Object?>{'name': '김밥', 'calories': 420, 'sodium_mg': 900},
    ];

    Future<Map<String, Object?>> summary() async =>
        (await dio.get<Map<String, Object?>>('/dashboard/summary')).data!;

    test('표시 이름이 있어도 저장된 이름으로 짚는다', () async {
      expect((await create(foods: salty)).statusCode, 201);

      final Map<String, Object?> body = await summary();

      expect(body['ai_advice_params'], <String, Object?>{
        'foods': <String>['라면', '김밥'],
      });
      expect(body['sodium_warning'], contains('라면'));
    });
  });
}

/// 데모 백엔드도 끼니 구분·시각을 실서버와 같은 규칙으로 검증한다. (#2882)
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

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    useFixedKstDate(DateTime(2026, 8, 20, 12));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test',
        validateStatus: (int? _) => true,
      ),
    );
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() => db.close());

  Future<Response<Map<String, Object?>>> analyze(String mealType) =>
      dio.post<Map<String, Object?>>(
        '/diet/analyze',
        data: FormData.fromMap(<String, Object?>{
          'image': MultipartFile.fromBytes(_jpeg, filename: 'meal.jpg'),
          'meal_type': mealType,
        }),
      );

  Future<int> entriesToday() async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/diet/days/2026-08-20');
    return (res.data!['entries']! as List<Object?>).length;
  }

  for (final String meal in <String>[
    'breakfast',
    'lunch',
    'dinner',
    'snack',
    'lateNight',
  ]) {
    test('분석은 $meal 을 받는다', () async {
      expect((await analyze(meal)).statusCode, 200);
    });
  }

  test('분석은 다섯 값 밖의 끼니를 422 로 거절하고 저장하지 않는다', () async {
    final int before = await entriesToday();
    expect((await analyze('brunch')).statusCode, 422);
    expect((await analyze('late_night')).statusCode, 422);
    expect(await entriesToday(), before);
  });

  group('수정', () {
    late String id;

    setUp(() async {
      id = (await analyze('lunch')).data!['entry_id']! as String;
    });

    Future<int?> put(Map<String, Object?> body) async =>
        (await dio.put<Object?>('/diet/entries/$id', data: body)).statusCode;

    test('다섯 값 밖의 끼니는 422', () async {
      expect(await put(<String, Object?>{'meal_type': 'brunch'}), 422);
      expect(await put(<String, Object?>{'meal_type': ''}), 422);
    });

    test('정상 끼니는 그대로 고친다', () async {
      expect(await put(<String, Object?>{'meal_type': 'lateNight'}), 200);
    });

    test('시각은 HH:MM 이거나 빈 문자열', () async {
      expect(await put(<String, Object?>{'time_label': '19:30'}), 200);
      expect(await put(<String, Object?>{'time_label': ''}), 200);
      expect(await put(<String, Object?>{'time_label': '25:00'}), 422);
      expect(await put(<String, Object?>{'time_label': '오후 7:30'}), 422);
    });
  });
}

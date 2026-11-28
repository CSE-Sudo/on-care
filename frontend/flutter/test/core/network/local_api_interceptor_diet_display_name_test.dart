/// 데모 백엔드의 사진 분석은 표시 이름 없이 한국어 식단평을 싣는다. (#2850)
///
/// 실서버 스텁 인식기와 같은 값이다. `name` 은 영양표 매칭용 이름이다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare_core/clock.dart';

final Uint8List _jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    // 2026-08-20 정오에 고정하되, 읽을 때마다 1µs 씩 흐르게 둔다. 데모 백엔드는
    // 끼니 id 를 지금 시각으로 만들어, 한 테스트에서 두 번 분석하면 시계가
    // 멈춰 있는 동안 id 가 겹친다 — 실제 시계에서는 생기지 않는 충돌이다.
    final DateTime noon = DateTime(2026, 8, 20, 12);
    int tick = 0;
    debugNowKstOverride = () => noon.add(Duration(microseconds: tick++));
    addTearDown(() => debugNowKstOverride = null);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>> analyze() async {
    final Response<Map<String, Object?>> res = await dio
        .post<Map<String, Object?>>(
          '/diet/analyze',
          data: FormData.fromMap(<String, Object?>{
            'image': MultipartFile.fromBytes(_jpeg, filename: 'meal.jpg'),
            'meal_type': 'lunch',
          }),
        );
    return res.data!;
  }

  List<Map<String, Object?>> foodsOf(Map<String, Object?> body) =>
      ((body['analysis']! as Map<String, Object?>)['foods']! as List<Object?>)
          .cast<Map<String, Object?>>();

  test('표시 이름이 없고 식단평은 한국어다', () async {
    final Map<String, Object?> body = await analyze();
    expect(
      foodsOf(
        body,
      ).every((Map<String, Object?> f) => f['display_name'] == null),
      isTrue,
    );
    expect(
      (body['analysis']! as Map<String, Object?>)['coach_comment'],
      contains('나트륨'),
    );
  });
}

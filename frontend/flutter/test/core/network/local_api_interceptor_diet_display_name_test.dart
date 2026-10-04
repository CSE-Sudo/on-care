/// 데모 백엔드의 사진 분석도 영어 화면이면 영어 표시 이름과 식단평을 싣는다. (#2850)
///
/// 실서버 스텁 인식기와 같은 값이다. `name` 은 영양표 매칭용이라 한국어 그대로다.
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

  Future<Map<String, Object?>> analyze(String lang) async {
    final Response<Map<String, Object?>> res = await dio
        .post<Map<String, Object?>>(
          '/diet/analyze',
          data: FormData.fromMap(<String, Object?>{
            'image': MultipartFile.fromBytes(_jpeg, filename: 'meal.jpg'),
            'meal_type': 'lunch',
          }),
          options: Options(headers: <String, Object?>{'Accept-Language': lang}),
        );
    return res.data!;
  }

  Future<Map<String, Object?>> savedEntry(String id) async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/diet/days/2026-08-20');
    return (res.data!['entries']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((Map<String, Object?> e) => e['id'] == id);
  }

  List<Map<String, Object?>> foodsOf(Map<String, Object?> body) =>
      ((body['analysis']! as Map<String, Object?>)['foods']! as List<Object?>)
          .cast<Map<String, Object?>>();

  test('영어 화면이면 표시 이름과 영어 식단평을 싣고 저장한다', () async {
    final Map<String, Object?> body = await analyze('en');
    final List<Map<String, Object?>> foods = foodsOf(body);
    expect(foods.map((Map<String, Object?> f) => f['display_name']), <String>[
      'Frozen yogurt',
      'Fruit topping',
      'Granola topping',
    ]);
    expect(foods.first['name'], '요거트 아이스크림');
    final String comment =
        (body['analysis']! as Map<String, Object?>)['coach_comment']! as String;
    expect(comment, startsWith('Sodium is low'));

    final Map<String, Object?> saved = await savedEntry(
      body['entry_id']! as String,
    );
    final Map<String, Object?> first =
        (saved['foods']! as List<Object?>).first! as Map<String, Object?>;
    expect(first['display_name'], 'Frozen yogurt');
    expect(saved['ai_comment'], comment);
  });

  test('한국어 화면은 지금과 같다 — 표시 이름이 없고 식단평은 한국어', () async {
    final Map<String, Object?> body = await analyze('ko');
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

  test('영양 수치는 화면 언어와 상관없이 같다', () async {
    final Map<String, Object?> en = await analyze('en');
    final Map<String, Object?> ko = await analyze('ko');
    List<Object?> numbers(Map<String, Object?> b) => <Object?>[
      for (final Map<String, Object?> f in foodsOf(b))
        <Object?>[f['name'], f['calories'], f['sodium_mg'], f['sugar_g']],
    ];
    expect(numbers(en), numbers(ko));
  });
}

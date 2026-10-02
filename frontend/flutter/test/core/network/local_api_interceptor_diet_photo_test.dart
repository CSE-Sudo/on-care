/// 사진을 찍어 추가한 끼니가 **그 사진으로** 보이는지 — 데모 백엔드 쪽 계약.
///
/// 화면(끼니 카드·수정 화면)은 이미 `photo_url` 을 읽어 그린다. 빠져 있던 것은
/// 데모 백엔드였다: 분석이 사진을 버려서, 방금 올린 끼니만 이모지 칩으로
/// 남았다. 여기서 고정하는 것은 실서버와 같은 모양의 계약이다 —
/// 기록에 `photo_url` 이 붙고, 그 경로가 올린 바이트를 그대로 돌려준다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/network/request_extras.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';

import '../../helpers/strict_dio.dart';

/// JPEG 매직 넘버로 시작하는 가짜 사진. 인터셉터가 저장한 바이트에서 MIME 을
/// 되짚으므로 앞 세 바이트가 진짜 형식이어야 한다.
final Uint8List _jpeg = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  1,
  2,
  3,
  4,
]);

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 상태 코드를 그대로 보려고 오류 응답도 응답으로 받는다 — 로컬 목업 API 는
    // 실서버처럼 오류를 예외로 돌려준다(#2743).
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test',
        validateStatus: (int? _) => true,
      ),
    );
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() => db.close());

  Future<Response<Map<String, Object?>>> analyze({Uint8List? photo}) {
    final FormData form = FormData.fromMap(<String, Object?>{
      'image': MultipartFile.fromBytes(photo ?? _jpeg, filename: 'meal.jpg'),
      'meal_type': 'lunch',
    });
    return dio.post<Map<String, Object?>>(
      '/diet/analyze',
      data: form,
      options: photo == null
          ? null
          : Options(extra: <String, Object?>{kMealPhotoBytesExtra: photo}),
    );
  }

  test('사진을 올려 분석한 끼니에는 photo_url 이 붙는다', () async {
    final Response<Map<String, Object?>> res = await analyze(photo: _jpeg);
    final String entryId = res.data!['entry_id']! as String;

    final Response<Map<String, Object?>> today = await dio
        .get<Map<String, Object?>>('/diet/days/today');
    final Map<String, Object?> entry =
        (today.data!['entries']! as List<Object?>).single
            as Map<String, Object?>;

    expect(entry['id'], entryId);
    expect(entry['photo_url'], '/diet/photos/$entryId');
  });

  test('photo_url 은 올린 바이트를 그대로 돌려준다', () async {
    final Response<Map<String, Object?>> res = await analyze(photo: _jpeg);
    final String entryId = res.data!['entry_id']! as String;

    final Response<List<int>> photo = await dio.get<List<int>>(
      '/diet/photos/$entryId',
      options: Options(responseType: ResponseType.bytes),
    );

    expect(photo.statusCode, 200);
    expect(photo.data, _jpeg);
    // 실서버처럼 형식을 밝힌다. 바이트에서 되짚은 값이라 확장자를 믿지 않는다.
    expect(photo.headers.value(Headers.contentTypeHeader), 'image/jpeg');
  });

  test('사진 없이 만든 기록은 photo_url 이 비어 있다', () async {
    await analyze();

    final Response<Map<String, Object?>> today = await dio
        .get<Map<String, Object?>>('/diet/days/today');
    final Map<String, Object?> entry =
        (today.data!['entries']! as List<Object?>).single
            as Map<String, Object?>;

    expect(entry['photo_url'], isNull);
  });

  test('끼니를 고쳐도 사진은 그 기록에 남는다', () async {
    final Response<Map<String, Object?>> res = await analyze(photo: _jpeg);
    final String entryId = res.data!['entry_id']! as String;

    final Response<Map<String, Object?>> updated = await dio
        .put<Map<String, Object?>>(
          '/diet/entries/$entryId',
          data: <String, Object?>{'meal_type': 'dinner'},
        );

    expect(updated.data!['photo_url'], '/diet/photos/$entryId');
  });

  test('재시도(같은 멱등키)는 사진을 한 벌만 남긴다', () async {
    Future<Response<Map<String, Object?>>> send() {
      final FormData form = FormData.fromMap(<String, Object?>{
        'image': MultipartFile.fromBytes(_jpeg, filename: 'meal.jpg'),
        'meal_type': 'lunch',
        'idempotency_key': 'idem-photo-1',
      });
      return dio.post<Map<String, Object?>>(
        '/diet/analyze',
        data: form,
        options: Options(extra: <String, Object?>{kMealPhotoBytesExtra: _jpeg}),
      );
    }

    final String first = (await send()).data!['entry_id']! as String;
    final String second = (await send()).data!['entry_id']! as String;
    expect(second, first);

    final Response<Map<String, Object?>> today = await dio
        .get<Map<String, Object?>>('/diet/days/today');
    final List<Object?> entries = today.data!['entries']! as List<Object?>;
    expect(entries.length, 1);
    expect(
      (entries.single as Map<String, Object?>)['photo_url'],
      '/diet/photos/$first',
    );
  });

  test('앱이 실제로 올리는 경로(저장소 → 인터셉터)로도 사진이 남는다', () async {
    // 위 테스트들은 사진 바이트를 직접 실어 보낸다. 앱에서 그 일을 하는 것은
    // `DioDietRepository.analyze` 라, 거기서 빠지면 화면만 조용히 이모지로
    // 돌아간다 — 그 연결까지 같이 고정한다.
    final DioDietRepository repository = DioDietRepository(strictDioOf(dio));
    final MealPhoto photo = MealPhoto.fromBytes(_jpeg)!;

    await repository.analyze(photo: photo, mealType: 'lunch');
    final DietDay day = await repository.fetchToday();
    final DietEntry entry = day.entries.single;

    expect(entry.photoUrl, isNotNull);
    final Response<List<int>> stored = await dio.get<List<int>>(
      entry.photoUrl!,
      options: Options(responseType: ResponseType.bytes),
    );
    expect(stored.data, _jpeg);
  });

  test('사진이 없는 기록의 사진 경로는 404 와 빈 바이트', () async {
    // 인터셉터가 만든 응답은 dio 의 상태 검증을 거치지 않아 예외가 아니라
    // 그대로 돌아온다. 사진을 읽는 쪽(`storedMealPhotoProvider`)은 빈 바이트를
    // "사진 없음" 으로 읽어 카드가 이모지로 물러난다.
    final Response<List<int>> res = await dio.get<List<int>>(
      '/diet/photos/diet-none',
      options: Options(responseType: ResponseType.bytes),
    );

    expect(res.statusCode, 404);
    expect(res.data, isEmpty);
  });
}

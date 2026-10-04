/// 식단 직접 추가의 멱등키 — 화면이 준 키를 그대로 싣고, 409 는 충돌로 알린다. (#3095)
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/diet_entry_key_conflict.dart';

void main() {
  late Dio dio;
  late DioDietRepository repository;
  late List<String?> sentKeys;
  late int? failNextWith;

  setUp(() {
    sentKeys = <String?>[];
    failNextWith = null;
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final Map<String, Object?> body =
              options.data as Map<String, Object?>;
          sentKeys.add(body['idempotency_key'] as String?);
          final int? status = failNextWith;
          failNextWith = null;
          if (status != null) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: status == 0
                    ? DioExceptionType.receiveTimeout
                    : DioExceptionType.badResponse,
                response: status == 0
                    ? null
                    : Response<Object?>(
                        requestOptions: options,
                        statusCode: status,
                      ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 201,
              data: <String, Object?>{
                'id': 'diet-1',
                'meal_type': body['meal_type'],
                'time_label': '12:00',
                'foods': <Object?>[],
                'total_calories': 0,
                'sodium_mg': 0,
                'sugar_g': 0,
                'carbs_g': 0,
                'protein_g': 0,
                'fat_g': 0,
              },
            ),
          );
        },
      ),
    );
    repository = DioDietRepository(dio);
  });

  tearDown(() => dio.close());

  Future<void> create({
    String meal = 'lunch',
    int calories = 420,
    String key = 'manual-1',
  }) => repository.createEntry(
    date: '2026-10-04',
    mealType: meal,
    foods: <FoodItem>[
      FoodItem(name: '김밥', calories: calories, source: FoodSource.member),
    ],
    idempotencyKey: key,
  );

  test('화면이 준 키를 재시도에도 그대로 싣는다 — 고쳐 보내도 같은 키', () async {
    failNextWith = 0;
    await expectLater(create(), throwsA(isA<DioException>()));
    await create();
    await create(calories: 500);
    expect(sentKeys, <String?>['manual-1', 'manual-1', 'manual-1']);
  });

  test('409 는 DietEntryKeyConflict 다', () async {
    failNextWith = 409;
    await expectLater(create(), throwsA(isA<DietEntryKeyConflict>()));
  });

  test('다른 실패는 그대로 올린다', () async {
    failNextWith = 500;
    await expectLater(create(), throwsA(isA<DioException>()));
  });
}

/// 식단 직접 추가의 멱등키 — 같은 끼니면 같은 키, 고치면 새 키, 409 는 알린다. (#3095)
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

  Future<void> create({String meal = 'lunch', int calories = 420}) =>
      repository.createEntry(
        date: '2026-10-04',
        mealType: meal,
        foods: <FoodItem>[
          FoodItem(name: '김밥', calories: calories, source: FoodSource.member),
        ],
      );

  test('응답을 잃은 뒤 같은 끼니를 다시 보내면 같은 키다', () async {
    failNextWith = 0;
    await expectLater(create(), throwsA(isA<DioException>()));
    await create();
    expect(sentKeys[0], isNotNull);
    expect(sentKeys[1], sentKeys[0]);
  });

  test('응답을 잃은 뒤 고쳐 보내면 새 키다 — 고친 내용이 버려지지 않는다', () async {
    failNextWith = 0;
    await expectLater(create(), throwsA(isA<DioException>()));
    await create(calories: 500);
    await create(meal: 'dinner');
    expect(sentKeys.toSet(), hasLength(3));
  });

  test('저장이 성공한 뒤의 같은 끼니는 새 키다', () async {
    await create();
    await create();
    expect(sentKeys[1], isNot(sentKeys[0]));
  });

  test('409 는 DietEntryKeyConflict 이고 그 키를 버린다', () async {
    failNextWith = 409;
    await expectLater(create(), throwsA(isA<DietEntryKeyConflict>()));
    await create();
    expect(sentKeys[1], isNot(sentKeys[0]));
  });

  test('부르는 쪽이 준 키는 그대로 쓴다', () async {
    await repository.createEntry(
      date: '2026-10-04',
      mealType: 'lunch',
      foods: const <FoodItem>[FoodItem(name: '김밥', calories: 1)],
      idempotencyKey: 'given-1',
    );
    expect(sentKeys, <String?>['given-1']);
  });
}

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';

void main() {
  late Dio dio;
  late DioDietRepository repository;
  late List<String> requestedPaths;
  late List<Object?> sentBodies;

  setUp(() {
    requestedPaths = <String>[];
    sentBodies = <Object?>[];
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requestedPaths.add(options.path);
          sentBodies.add(options.data);
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.startsWith('/diet/days/')
                  ? _serverDayResponse
                  : _serverResponse,
            ),
          );
        },
      ),
    );
    repository = DioDietRepository(dio);
  });

  tearDown(() {
    dio.close();
  });

  test('fetchByDate requests the selected YYYY-MM-DD date', () async {
    final day = await repository.fetchByDate(DateTime(2026, 8, 3));

    expect(requestedPaths, <String>['/diet/days/2026-08-03']);
    expect(day.totalCalories, 100);
    expect(day.entries.single.id, 'diet-edit');
  });

  test('수정해도 사진과 코멘트는 그대로 남는다', () async {
    // 수정은 끼니 내용만 바꾼다 — 사진과 코멘트는 서버가 그대로 돌려준다.
    // 여기서 빠지면 이름만 고쳐도 끼니 카드가 이모지로 떨어진다(#1871).
    final Dio photoDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    addTearDown(photoDio.close);
    photoDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 200,
              data: <String, Object?>{
                ..._serverResponse,
                'photo_url': '/diet/photos/photo-1',
                'photo_asset': 'assets/images/breakfast.jpg',
                'ai_comment': '단백질이 넉넉해요',
              },
            ),
          );
        },
      ),
    );

    final DietEntry updated = await DioDietRepository(photoDio).updateEntry(
      id: 'diet-edit',
      foods: const <FoodItem>[FoodItem(name: '고친 이름', calories: 100)],
    );

    expect(updated.photoUrl, '/diet/photos/photo-1');
    expect(updated.photoAsset, 'assets/images/breakfast.jpg');
    expect(updated.aiComment, '단백질이 넉넉해요');
  });

  // 서버가 보낸 음식을 저장하고 끼니 합계도 그 음식에서 다시 낸다(#1892).
  // 그래서 앱은 응답을 그대로 쓴다 — 예전에는 서버가 `foods` 를 버리면서도
  // 200 을 줘서, 앱이 보낸 값으로 응답을 덮어쓰고 있었다.
  test('수정 응답을 그대로 쓴다 — 앱이 보낸 값으로 덮어쓰지 않는다', () async {
    const editedFoods = <FoodItem>[
      FoodItem(name: '현미밥', calories: 220, carbsG: 46, proteinG: 5, fatG: 1.8),
      FoodItem(name: '닭가슴살', calories: 165, proteinG: 31, fatG: 3.6),
    ];

    final updated = await repository.updateEntry(
      id: 'diet-edit',
      foods: editedFoods,
      totalCalories: 385,
      sodiumMg: 79,
      sugarG: 2.5,
    );

    // 서버가 돌려준 값이다. 보낸 값을 그대로 되비추면 저장이 안 돼도 성공한
    // 것처럼 보인다 — 그게 이 우회가 감추고 있던 것이다.
    expect(updated.foods.single.name, '기존 음식');
    expect(updated.carbsG, 90);
    expect(updated.proteinG, 8);
    expect(updated.fatG, 7);
    expect(updated.sodiumMg, 100);
    expect(updated.sugarG, 1);
  });

  test('수정한 음식은 요청 본문에 실려 나간다', () async {
    const editedFoods = <FoodItem>[
      FoodItem(
        name: '현미밥',
        calories: 220,
        sodiumMg: 3,
        sugarG: 0.5,
        carbsG: 46,
        proteinG: 5,
        fatG: 1.8,
      ),
    ];

    await repository.updateEntry(id: 'diet-edit', foods: editedFoods);

    final Map<String, Object?> body = sentBodies.single as Map<String, Object?>;
    final List<Object?> foods = body['foods']! as List<Object?>;
    expect(foods.single, <String, Object?>{
      'name': '현미밥',
      'calories': 220,
      'sodium_mg': 3,
      'sugar_g': 0.5,
      'carbs_g': 46.0,
      'protein_g': 5.0,
      'fat_g': 1.8,
    });
  });

  test('음식을 보내지 않으면 요청에 foods 가 실리지 않는다', () async {
    await repository.updateEntry(id: 'diet-edit', mealType: 'dinner');

    final Map<String, Object?> body = sentBodies.single as Map<String, Object?>;
    expect(body.containsKey('foods'), isFalse);
    expect(body['meal_type'], 'dinner');
  });

  test('하루 조회도 서버가 준 합계를 그대로 쓴다', () async {
    await repository.updateEntry(
      id: 'diet-edit',
      foods: const <FoodItem>[
        FoodItem(
          name: '현미밥',
          calories: 220,
          carbsG: 46,
          proteinG: 5,
          fatG: 1.8,
        ),
      ],
      totalCalories: 220,
    );

    final DietDay day = await repository.fetchToday();

    expect(day.macros.carbsG, 90, reason: '앱이 기억한 값이 아니라 응답의 값이다');
    expect(day.macros.proteinG, 8);
    expect(day.macros.fatG, 7);
    expect(day.entries.single.foods.single.name, '기존 음식');
  });

  group('analyze uploads a part that matches the picked photo', () {
    late Dio uploadDio;
    late DioDietRepository uploadRepository;
    late FormData? sentForm;

    setUp(() {
      sentForm = null;
      uploadDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      uploadDio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                sentForm = options.data as FormData?;
                handler.resolve(
                  Response<Map<String, Object?>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: const <String, Object?>{
                      'entry_id': 'diet-1',
                      'analysis': <String, Object?>{
                        'foods': <Object?>[],
                        'total_calories': 0,
                        'total_sodium_mg': 0,
                        'total_sugar_g': 0,
                        'coach_comment': '',
                      },
                    },
                  ),
                );
              },
        ),
      );
      uploadRepository = DioDietRepository(uploadDio);
    });

    tearDown(() => uploadDio.close());

    MultipartFile imagePart() => sentForm!.files
        .firstWhere((MapEntry<String, MultipartFile> f) => f.key == 'image')
        .value;

    test('PNG 사진은 png 파일명·image/png 로 전송된다', () async {
      await uploadRepository.analyze(
        photo: MealPhoto.fromBytes(
          // 완전한 PNG 시그니처 8바이트 (잘린 헤더는 fromBytes 가 null 을 준다).
          Uint8List.fromList(<int>[
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
          ]),
        )!,
        mealType: 'lunch',
        idempotencyKey: 'k1',
      );

      expect(imagePart().filename, 'meal.png');
      expect(imagePart().contentType?.mimeType, 'image/png');
    });

    test('HTTP 실패는 DioException 이 아니라 AppError 로 올라온다', () async {
      // 화면이 DioException 을 타입 검사하지 않고도 415/502 를 구분할 수 있어야
      // 한다(core/errors/app_error.dart 의 레이어 규약).
      final Dio failing = Dio(BaseOptions(baseUrl: 'https://example.test'));
      failing.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response<Object?>(
                      requestOptions: options,
                      statusCode: 415,
                    ),
                  ),
                );
              },
        ),
      );
      addTearDown(failing.close);

      await expectLater(
        DioDietRepository(failing).analyze(
          photo: MealPhoto.fromBytes(
            Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0]),
          )!,
          mealType: 'lunch',
        ),
        throwsA(
          isA<ServerError>().having(
            (ServerError e) => e.statusCode,
            'statusCode',
            415,
          ),
        ),
      );
    });

    test('JPEG 사진은 jpg 파일명·image/jpeg 로 전송된다', () async {
      await uploadRepository.analyze(
        photo: MealPhoto.fromBytes(
          Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0]),
        )!,
        mealType: 'lunch',
      );

      expect(imagePart().filename, 'meal.jpg');
      expect(imagePart().contentType?.mimeType, 'image/jpeg');
    });
  });
}

/// 서버가 돌려주는 끼니 하나. 앱은 이 값을 그대로 쓴다(#1892).
const Map<String, Object?> _serverResponse = <String, Object?>{
  'id': 'diet-edit',
  'meal_type': 'lunch',
  'time_label': '12:00',
  'foods': <Object?>[
    <String, Object?>{
      'name': '기존 음식',
      'calories': 100,
      'sodium_mg': 100,
      'sugar_g': 1,
      'carbs_g': 90,
      'protein_g': 8,
      'fat_g': 7,
    },
  ],
  'total_calories': 100,
  'sodium_mg': 100,
  'sugar_g': 1,
  'carbs_g': 90,
  'protein_g': 8,
  'fat_g': 7,
};

const Map<String, Object?> _serverDayResponse = <String, Object?>{
  'entries': <Object?>[_serverResponse],
  'total_calories': 100,
  'total_sodium_mg': 100,
  'total_sugar_g': 1,
  'macros': <String, Object?>{
    'carbs_g': 90,
    'protein_g': 8,
    'fat_g': 7,
    'carbs_pct': 82,
    'protein_pct': 7,
    'fat_pct': 11,
  },
  'ai_coach_message': '서버의 오래된 응답',
};

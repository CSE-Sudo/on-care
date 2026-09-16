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

  setUp(() {
    requestedPaths = <String>[];
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requestedPaths.add(options.path);
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 200,
              data: options.path.startsWith('/diet/days/')
                  ? _staleDayResponse
                  : _staleResponse,
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
    // 수정 결과는 로컬 오버라이드가 되어 원본 항목을 통째로 갈아 끼운다.
    // 여기서 사진을 빠뜨리면 이름만 고쳐도 끼니 카드가 이모지로 떨어진다.
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
                ..._staleResponse,
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

  test('섭취량은 저장 요청에 실리고 응답에서 다시 읽힌다', () async {
    // 섭취량은 나머지 여섯 값의 기준이다. 요청에서 빠지면 다음에 이 끼니를
    // 열었을 때 양을 모르는 기록이 되어, 양으로 영양을 움직이는 길이 저장
    // 한 번에 끊긴다(#1876).
    final Dio amountDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    addTearDown(amountDio.close);
    late Map<String, Object?> sentBody;
    amountDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          sentBody = (options.data as Map<String, Object?>?) ?? const {};
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 200,
              data: <String, Object?>{
                ..._staleResponse,
                'foods': <Object?>[
                  <String, Object?>{
                    'name': '현미밥',
                    'amount_g': 210,
                    'calories': 310,
                  },
                  // 양을 못 얻은 음식과 이 필드 이전 기록이 실제로 섞여 온다.
                  <String, Object?>{'name': '김', 'calories': 5},
                ],
              },
            ),
          );
        },
      ),
    );

    final DietEntry updated = await DioDietRepository(amountDio).updateEntry(
      id: 'diet-edit',
      foods: const <FoodItem>[
        FoodItem(name: '현미밥', calories: 310, amountG: 210),
        FoodItem(name: '김', calories: 5),
      ],
    );

    final List<Object?> sentFoods = sentBody['foods']! as List<Object?>;
    expect((sentFoods.first as Map<String, Object?>)['amount_g'], 210);
    expect((sentFoods.last as Map<String, Object?>)['amount_g'], isNull);
    // 응답도 같은 값을 돌려준다 — 서버가 실은 값을 앱이 읽을 수 있어야 한다.
    expect(updated.foods.first.amountG, 210);
    expect(updated.foods.last.amountG, isNull, reason: '없는 양을 0 으로 지어내지 않는다');
  });

  test(
    'edited foods determine override macros when response is stale',
    () async {
      const editedFoods = <FoodItem>[
        FoodItem(
          name: '현미밥',
          calories: 220,
          carbsG: 46,
          proteinG: 5,
          fatG: 1.8,
        ),
        FoodItem(name: '닭가슴살', calories: 165, proteinG: 31, fatG: 3.6),
      ];

      final updated = await repository.updateEntry(
        id: 'diet-edit',
        foods: editedFoods,
        totalCalories: 385,
        sodiumMg: 79,
        sugarG: 2.5,
      );

      expect(updated.foods, same(editedFoods));
      expect(updated.carbsG, 46);
      expect(updated.proteinG, 36);
      expect(updated.fatG, closeTo(5.4, 0.001));
      expect(updated.carbsG, isNot(_staleResponse['carbs_g']));
      expect(updated.proteinG, isNot(_staleResponse['protein_g']));
      expect(updated.fatG, isNot(_staleResponse['fat_g']));
      expect(updated.sodiumMg, 79);
      expect(updated.sugarG, 2.5);
    },
  );

  test('fetchToday derives day macros from overridden entries', () async {
    const editedFoods = <FoodItem>[
      FoodItem(name: '현미밥', calories: 220, carbsG: 46, proteinG: 5, fatG: 1.8),
      FoodItem(name: '닭가슴살', calories: 165, proteinG: 31, fatG: 3.6),
    ];
    await repository.updateEntry(
      id: 'diet-edit',
      foods: editedFoods,
      totalCalories: 385,
      sodiumMg: 79,
      sugarG: 2.5,
    );

    final DietDay day = await repository.fetchToday();

    expect(day.entries.single.foods, same(editedFoods));
    expect(day.macros.carbsG, 46);
    expect(day.macros.proteinG, 36);
    expect(day.macros.fatG, closeTo(5.4, 0.001));
    expect(
      <int>[day.macros.carbsPct, day.macros.proteinPct, day.macros.fatPct],
      <int>[49, 38, 13],
    );
    expect(
      day.macros.carbsPct + day.macros.proteinPct + day.macros.fatPct,
      100,
    );
  });

  test('zero override macros return safe zero percentages', () async {
    await repository.updateEntry(
      id: 'diet-edit',
      foods: const <FoodItem>[FoodItem(name: '물', calories: 0)],
      totalCalories: 0,
      sodiumMg: 0,
      sugarG: 0,
    );

    final DietMacros macros = (await repository.fetchToday()).macros;

    expect(macros.carbsG, 0);
    expect(macros.proteinG, 0);
    expect(macros.fatG, 0);
    expect(macros.carbsPct, 0);
    expect(macros.proteinPct, 0);
    expect(macros.fatPct, 0);
  });

  test(
    'update without foods keeps returned macros and local nutrition',
    () async {
      final updated = await repository.updateEntry(
        id: 'diet-edit',
        mealType: 'dinner',
        sodiumMg: 444,
        sugarG: 5.5,
      );

      expect(updated.foods.single.name, '기존 음식');
      expect(updated.carbsG, 90);
      expect(updated.proteinG, 8);
      expect(updated.fatG, 7);
      expect(updated.sodiumMg, 444);
      expect(updated.sugarG, 5.5);
    },
  );

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

const Map<String, Object?> _staleResponse = <String, Object?>{
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

const Map<String, Object?> _staleDayResponse = <String, Object?>{
  'entries': <Object?>[_staleResponse],
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

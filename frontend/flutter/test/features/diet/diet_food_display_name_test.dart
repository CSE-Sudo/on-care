/// 영어 화면의 사진 분석 음식 이름 — 표시 이름(`display_name`). (#2850)
///
/// 서버는 공공 영양 DB 가 한국어 이름으로 매칭하므로 `name` 을 한국어로 두고,
/// 영어 화면에서 분석한 음식에만 영어 표시 이름을 함께 준다. 앱은 표시 이름이
/// 있으면 그것을 보이고, 고쳐 저장할 때는 이름을 그대로 둔 음식에 한해 원래
/// 이름과 표시 이름을 함께 되돌린다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

final Uint8List _jpegBytes = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

Map<String, Object?> _food(String name, {Object? displayName}) =>
    <String, Object?>{
      'name': name,
      'calories': 300,
      'sodium_mg': 10,
      'sugar_g': 1,
      'source': 'db',
      'display_name': ?displayName,
    };

class _FixedPicker implements MealPhotoPicker {
  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async =>
      MealPhoto.fromBytes(_jpegBytes)!;
}

/// 영어 화면에서 분석한 결과를 돌려주는 대역.
class _EnglishAnalysis extends FakeDietRepository {
  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
    String? date,
  }) async {
    final DietAnalysisResult base = await super.analyze(
      photo: photo,
      mealType: mealType,
      idempotencyKey: idempotencyKey,
    );
    final List<RecognizedFood> foods = <RecognizedFood>[
      RecognizedFood.fromJson(_food('김치찌개', displayName: 'Kimchi stew')),
      RecognizedFood.fromJson(_food('현미밥', displayName: 'Brown rice')),
    ];
    return DietAnalysisResult(
      entryId: base.entryId,
      foods: foods,
      totalCalories: 600,
      totalSodiumMg: 20,
      totalSugarG: 2,
      coachComment: 'Add a protein side next time.',
      timeLabel: base.timeLabel,
    );
  }
}

void main() {
  group('엔터티 파싱', () {
    test('저장된 음식은 표시 이름이 있으면 그것을 보인다', () {
      final FoodItem f = FoodItem.fromJson(
        _food('김치찌개', displayName: 'Kimchi stew'),
      );
      expect(f.name, '김치찌개');
      expect(f.displayName, 'Kimchi stew');
      expect(f.label, 'Kimchi stew');
    });

    test('표시 이름이 없으면 원래 이름이다 — 한국어 화면·이전 기록', () {
      final FoodItem f = FoodItem.fromJson(_food('현미밥'));
      expect(f.displayName, isNull);
      expect(f.label, '현미밥');
    });

    test('빈 표시 이름·문자열이 아닌 값은 없는 것과 같다', () {
      expect(FoodItem.fromJson(_food('현미밥', displayName: '  ')).label, '현미밥');
      expect(FoodItem.fromJson(_food('현미밥', displayName: 3)).label, '현미밥');
      expect(
        FoodItem.fromJson(_food('현미밥', displayName: ' Brown rice ')).label,
        'Brown rice',
      );
    });

    test('분석 결과의 음식도 같은 규칙이다', () {
      final DietAnalysisResult r = DietAnalysisResult.fromResponse(
        <String, Object?>{
          'entry_id': 'diet-1',
          'analysis': <String, Object?>{
            'foods': <Object?>[
              _food('김치찌개', displayName: 'Kimchi stew'),
              _food('현미밥'),
            ],
          },
        },
      );
      expect(r.foods.map((RecognizedFood f) => f.label), <String>[
        'Kimchi stew',
        '현미밥',
      ]);
      expect(r.foods.first.name, '김치찌개');
    });
  });

  group('DietFood.wireName', () {
    final DietFood shown = DietFood.fromItem(
      FoodItem.fromJson(_food('김치찌개', displayName: 'Kimchi stew')),
    );

    test('화면에는 표시 이름을 보인다', () {
      expect(shown.name, 'Kimchi stew');
    });

    test('이름을 그대로 두면 원래 이름과 표시 이름을 함께 보낸다 — 매칭 키가 영어로 덮이지 않는다', () {
      expect(shown.wireName, (name: '김치찌개', displayName: 'Kimchi stew'));
    });

    test('회원이 이름을 바꾸면 그 이름이 이름이고 표시 이름은 싣지 않는다', () {
      final DietFood renamed = DietFood(
        'Tofu stew',
        300,
        displayName: shown.displayName,
        storedName: shown.storedName,
      );
      expect(renamed.wireName, (name: 'Tofu stew', displayName: null));
    });

    test('표시 이름이 없는 음식은 적힌 이름 그대로다', () {
      final DietFood plain = DietFood.fromItem(FoodItem.fromJson(_food('현미밥')));
      expect(plain.wireName, (name: '현미밥', displayName: null));
    });
  });

  test('수정 저장 요청은 표시 이름이 있을 때만 싣는다', () async {
    final List<Object?> sent = <Object?>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions o, RequestInterceptorHandler h) {
          sent.add(o.data);
          h.resolve(
            Response<Map<String, Object?>>(
              requestOptions: o,
              statusCode: 200,
              data: <String, Object?>{
                'id': 'diet-1',
                'meal_type': 'lunch',
                'time_label': '12:00',
                'foods': <Object?>[],
                'total_calories': 0,
                'sodium_mg': 0,
                'sugar_g': 0,
                'ai_comment': '',
              },
            ),
          );
        },
      ),
    );

    await DioDietRepository(dio).updateEntry(
      id: 'diet-1',
      foods: const <FoodItem>[
        FoodItem(name: '김치찌개', calories: 300, displayName: 'Kimchi stew'),
        FoodItem(name: '현미밥', calories: 310),
      ],
    );

    final List<Object?> foods =
        (sent.single! as Map<String, Object?>)['foods']! as List<Object?>;
    expect((foods[0]! as Map<String, Object?>)['display_name'], 'Kimchi stew');
    expect((foods[0]! as Map<String, Object?>)['name'], '김치찌개');
    expect(
      (foods[1]! as Map<String, Object?>).containsKey('display_name'),
      false,
    );
  });

  testWidgets('영어 화면의 분석 결과 시트는 음식 이름을 영어로 보인다', (WidgetTester tester) async {
    useFixedKstDate(DateTime(2026, 8, 20, 9));
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
          dietRepositoryProvider.overrideWithValue(_EnglishAnalysis()),
          sessionFeatureResetOverride(),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDietAddSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a Photo'));
    await tester.pumpAndSettle();

    final String recognized = tester
        .widget<Text>(find.byKey(const Key('diet-result-recognized-foods')))
        .textSpan!
        .toPlainText()
        .replaceAll('⁠', '')
        .replaceAll(' ', ' ');
    expect(recognized, contains('Kimchi stew'));
    expect(recognized, contains('Brown rice'));
    expect(recognized, isNot(contains('김치찌개')));
  });
}

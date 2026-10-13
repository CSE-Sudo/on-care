/// 음식의 표시 이름(`display_name`). (#2850)
///
/// 서버는 공공 영양 DB 가 매칭하는 이름을 `name` 에 두고, 저장된 기록에는 표시
/// 이름이 함께 있을 수 있다. 앱은 표시 이름이 있으면 그것을 보이고, 고쳐 저장할
/// 때는 이름을 그대로 둔 음식에 한해 원래 이름과 표시 이름을 함께 되돌린다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/diet/data/repositories/dio_diet_repository.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';

Map<String, Object?> _food(String name, {Object? displayName}) =>
    <String, Object?>{
      'name': name,
      'calories': 300,
      'sodium_mg': 10,
      'sugar_g': 1,
      'source': 'db',
      'display_name': ?displayName,
    };

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

    test('표시 이름이 없으면 원래 이름이다', () {
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

    test('이름을 그대로 두면 원래 이름과 표시 이름을 함께 보낸다 — 매칭 키가 표시 이름으로 덮이지 않는다', () {
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
}

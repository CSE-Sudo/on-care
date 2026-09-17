import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/diet/domain/entities/diet_day.dart';

void main() {
  test('DietDay constructs with entries, totals and coach message', () {
    const day = DietDay(
      entries: <DietEntry>[
        DietEntry(
          mealType: MealType.breakfast,
          timeLabel: '08:00',
          totalCalories: 300,
          foods: <FoodItem>[FoodItem(name: 'oat', calories: 300)],
          sodiumMg: 100,
          sugarG: 5,
        ),
      ],
      totalCalories: 300,
      totalSodiumMg: 100,
      totalSugarG: 5,
      macros: DietMacros(carbsPct: 60, proteinPct: 20, fatPct: 20),
      aiCoachMessage: 'hello',
    );
    expect(day.entries.first.mealType, MealType.breakfast);
    expect(day.totalCalories, 300);
    expect(day.totalSodiumMg, 100);
    expect(day.aiCoachMessage, 'hello');
  });

  test('DietDay parses meal and daily macro grams from API JSON', () {
    final day = DietDay.fromJson(<String, Object?>{
      'entries': <Object?>[
        <String, Object?>{
          'id': 'diet-lunch',
          'meal_type': 'lunch',
          'time_label': '12:40',
          'foods': <Object?>[
            <String, Object?>{
              'name': '김치찌개',
              'calories': 285,
              'sodium_mg': 900,
              'sugar_g': 4,
              'carbs_g': 16,
              'protein_g': 20,
              'fat_g': 15.5,
            },
          ],
          'total_calories': 285,
          'sodium_mg': 900,
          'sugar_g': 4,
          'carbs_g': 16,
          'protein_g': 20,
          'fat_g': 15.5,
        },
      ],
      'total_calories': 285,
      'total_sodium_mg': 900,
      'total_sugar_g': 4,
      'macros': <String, Object?>{
        'carbs_g': 16,
        'protein_g': 20,
        'fat_g': 15.5,
        'carbs_pct': 23,
        'protein_pct': 29,
        'fat_pct': 48,
      },
      'ai_coach_message': 'message',
    });

    expect(day.entries.single.carbsG, 16);
    expect(day.entries.single.proteinG, 20);
    expect(day.entries.single.fatG, 15.5);
    expect(day.entries.single.foods.single.sodiumMg, 900);
    expect(day.entries.single.foods.single.carbsG, 16);
    expect(day.macros.carbsG, 16);
    expect(day.macros.proteinG, 20);
    expect(day.macros.fatG, 15.5);
    expect(day.macros.carbsPct, 23);
  });

  test('missing macro fields in legacy JSON default to zero', () {
    final day = DietDay.fromJson(<String, Object?>{
      'entries': <Object?>[
        <String, Object?>{
          'meal_type': 'breakfast',
          'time_label': '08:00',
          'foods': <Object?>[
            <String, Object?>{'name': '바나나', 'calories': 105},
          ],
          'total_calories': 105,
        },
      ],
      'total_calories': 105,
      'total_sodium_mg': 0,
      'total_sugar_g': 0,
      'ai_coach_message': '',
    });

    expect(day.entries.single.carbsG, 0);
    expect(day.entries.single.foods.single.proteinG, 0);
    expect(day.macros.carbsG, 0);
    expect(day.macros.carbsPct, 0);
  });

  test('야식 meal_type 을 다섯 번째 끼니로 읽는다', () {
    final DietDay day = DietDay.fromJson(_dayWithMealType('lateNight'));

    expect(day.entries.single.mealType, MealType.lateNight);
  });

  test('이미 저장된 snack 은 그대로 간식으로 읽힌다', () {
    // 야식이 생겨도 백필하지 않는다(#1988) — 지난 기록이 옮겨 가면 안 된다.
    final DietDay day = DietDay.fromJson(_dayWithMealType('snack'));

    expect(day.entries.single.mealType, MealType.snack);
  });

  test('앱이 모르는 meal_type 이 와도 죽지 않고 간식으로 접는다', () {
    // 앱은 저보다 새 서버를 만날 수 있다. 하루치가 통째로 파싱에서 죽는 것보다
    // 모르는 한 끼가 간식으로 보이는 편이 낫다.
    final DietDay day = DietDay.fromJson(_dayWithMealType('brunch'));

    expect(day.entries.single.mealType, MealType.snack);
  });
}

Map<String, Object?> _dayWithMealType(String mealType) => <String, Object?>{
  'entries': <Object?>[
    <String, Object?>{
      'meal_type': mealType,
      'time_label': '22:30',
      'foods': <Object?>[
        <String, Object?>{'name': '치킨', 'calories': 480},
      ],
      'total_calories': 480,
    },
  ],
  'total_calories': 480,
  'total_sodium_mg': 0,
  'total_sugar_g': 0,
  'ai_coach_message': '',
};

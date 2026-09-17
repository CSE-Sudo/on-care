/// 음식 이름으로 공공 영양 DB 에서 찾은 영양 한 벌. (#1896)
///
/// 수정 화면이 이름을 고쳤을 때 **제안**하는 데 쓴다. 덮어쓰지 않는 이유는
/// 이름 변경이 "다른 음식이다" 일 수도 "오타를 고쳤다" 일 수도 있어 앱이 둘을
/// 구분할 수 없기 때문이다 — 자동으로 갈아 끼우면 회원이 손으로 바로잡아 둔
/// 값이 소리 없이 사라진다.
library;

import 'package:oncare/features/diet/domain/entities/diet_day.dart';

class FoodNutritionSuggestion {
  const FoodNutritionSuggestion({
    required this.matchedName,
    required this.food,
  });

  /// 값을 가져온 공공 DB 의 **대표 이름**. 회원이 적은 말과 다를 수 있어
  /// (매칭이 포함 관계로도 붙는다) 무엇에 붙었는지 화면이 보여 준다.
  final String matchedName;

  /// 그 이름의 영양 한 벌. [FoodItem.amountG] 가 이 값들의 기준이라 함께 채워야
  /// 이후 내용량 변경이 #1876 의 비례 환산으로 이어진다.
  final FoodItem food;

  /// 서버 응답 → 제안. **제안할 것이 없으면 null 이다.**
  ///
  /// 못 찾았거나(`matched_name` 이 null) 양을 정할 수 없으면(`amount_g` 가 null)
  /// 아무것도 제안하지 않는다. 임의로 1인분을 가정해 확정할 수 없는 숫자를
  /// "공공 DB 근거" 로 내미는 것이 여기서 제일 나쁘다 — 서버 보정의 폴백 원칙과
  /// 같다.
  static FoodNutritionSuggestion? fromJson(Map<String, Object?> json) {
    final String? matched = json['matched_name'] as String?;
    final double? amountG = (json['amount_g'] as num?)?.toDouble();
    if (matched == null || matched.isEmpty || amountG == null || amountG <= 0) {
      return null;
    }
    return FoodNutritionSuggestion(
      matchedName: matched,
      food: FoodItem(
        name: matched,
        calories: (json['calories'] as num?)?.toInt() ?? 0,
        amountG: amountG,
        sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
        sugarG: (json['sugar_g'] as num?)?.toDouble() ?? 0,
        carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
        proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
        fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      ),
    );
  }
}

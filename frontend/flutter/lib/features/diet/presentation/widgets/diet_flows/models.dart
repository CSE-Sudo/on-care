// 식단 화면이 주고받는 끼니·음식 모델.

part of '../diet_flows.dart';

/// A single logged food item, with the per-food nutrition shown on the meal
/// card (all nutrition defaults to 0 for draft rows in the edit sheet).
///
/// 끼니 단위 탄단지는 이 값들의 합계로 만들어진다(`local_api_interceptor` 의
/// `_sumMacro`). 그래서 수정 화면이 이 필드를 하나라도 흘리면 저장한 순간
/// 그 끼니의 영양 정보가 통째로 0 이 된다(#1853).
class DietFood {
  const DietFood(
    this.name,
    this.kcal, {
    this.amountG,
    this.sodiumMg = 0,
    this.sugarG = 0,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.source = FoodSource.estimate,
    this.displayName,
    this.storedName,
  });

  /// 서버가 준 저장된 음식. 표시 이름이 있으면 그것을 이름으로 보인다(#2850).
  factory DietFood.fromItem(FoodItem f) => DietFood(
    f.label,
    f.calories,
    amountG: f.amountG,
    sodiumMg: f.sodiumMg,
    sugarG: f.sugarG,
    carbsG: f.carbsG,
    proteinG: f.proteinG,
    fatG: f.fatG,
    source: f.source,
    displayName: f.displayName,
    storedName: f.name,
  );

  /// 사진 분석이 인식한 음식. [DietFood.fromItem] 과 같은 규칙이다.
  factory DietFood.fromRecognized(RecognizedFood f) => DietFood(
    f.label,
    f.calories,
    amountG: f.amountG,
    sodiumMg: f.sodiumMg,
    sugarG: f.sugarG,
    carbsG: f.carbsG,
    proteinG: f.proteinG,
    fatG: f.fatG,
    source: f.source,
    displayName: f.displayName,
    storedName: f.name,
  );

  /// 화면에 보이고 수정 화면이 고치는 이름.
  final String name;
  final int kcal;

  /// 서버가 준 표시 이름과 저장된 원래 이름(#2850). 영어 화면에서 분석한
  /// 음식은 [name] 이 영어 표시 이름이고, [storedName] 이 공공 영양 DB 가
  /// 매칭하는 한국어 이름이다. 저장할 때 [wireName] 이 둘을 되돌린다.
  final String? displayName;
  final String? storedName;

  /// 저장할 때 보낼 이름. 표시 이름을 그대로 두었으면 원래 이름과 표시 이름을
  /// 함께 되돌려 매칭 키가 영어로 덮이지 않게 하고, 회원이 이름을 바꿨으면 그
  /// 이름이 곧 이름이다 — 표시 이름은 싣지 않는다.
  ({String name, String? displayName}) get wireName {
    final String typed = name.trim();
    final String? shown = displayName;
    if (shown != null && typed == shown && storedName != null) {
      return (name: storedName!, displayName: shown);
    }
    return (name: typed, displayName: null);
  }

  /// 먹은 양(g). 나머지 영양이 이 양을 재고 나온 값이라, 수정 화면은 이 칸
  /// 하나로 여섯 값을 함께 움직인다(#1876). 모르면 null 이다 — [FoodItem.amountG]
  /// 에 적어 둔 것과 같은 이유로 0 이 아니다.
  final double? amountG;
  final int sodiumMg;
  final double sugarG;
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 위 영양이 어디서 왔나(#2105). 수정 화면이 음식마다 따라가다 저장할 때
  /// 그대로 싣는다 — 버리면 손대지 않은 음식까지 서버 기본값으로 덮인다.
  final FoodSource source;
}

/// A nutrient chip on a meal card (`over` = above the daily target → red).
class DietTag {
  const DietTag(this.label, {this.over = false});
  final String label;
  final bool over;
}

/// One meal in the daily log. [id] is the backend entry id (null for a
/// not-yet-persisted draft) and is required to edit or delete the entry.
class DietMeal {
  const DietMeal({
    required this.mealType,
    required this.date,
    required this.time,
    required this.total,
    required this.emoji,
    required this.thumbBg,
    required this.items,
    required this.tags,
    required this.sodium,
    required this.sugar,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.aiComment = '',
    this.photoAsset,
    this.photoUrl,
    this.id,
  });

  final MealType mealType;

  /// 이 기록이 놓인 날(시각 없는 날짜). 식단 상세에서 날짜를 고치는 기준이다
  /// (#1947).
  ///
  /// `DietEntry` 에는 날짜가 없다 — 서버가 날짜별로 묶어 내려주므로 날짜는 그
  /// 목록을 **어느 날로 불렀는가** 에서 온다. 그래서 끼니를 옮기는 매퍼가
  /// 반드시 받아 오도록 필수로 둔다 — 빠뜨린 자리를 오늘로 채우면 지난 날의
  /// 기록이 상세에서 오늘로 보인다.
  final DateTime date;
  final String time;
  final int total;
  final String emoji;
  final Color thumbBg;
  final List<DietFood> items;
  final List<DietTag> tags;
  final int sodium;
  final double sugar;

  /// 그 끼니의 탄·단·지(g). 끼니 카드 아래에 한 줄로 작게 적는다 (#1170) —
  /// 하루 합계는 영양 요약 카드가 말하지만, 어느 끼니가 그 합계를 만들었는지는
  /// 끼니 단위로 봐야 알 수 있다. 트레이너 화면의 같은 카드와 짝이다.
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// Short per-meal AI feedback line shown under the food breakdown.
  final String aiComment;

  /// Bundled photo asset for the thumbnail; null falls back to [emoji].
  final String? photoAsset;

  /// API path of the photo the member uploaded (#699). Wins over
  /// [photoAsset] when present.
  final String? photoUrl;
  final String? id;
}

/// Localized meal-type badge label. The API `meal_type` string is always
/// derived from [MealType.name], never from this display label.
String mealBadge(AppLocalizations l, MealType t) => switch (t) {
  MealType.breakfast => l.dietMealBreakfast,
  MealType.lunch => l.dietMealLunch,
  MealType.dinner => l.dietMealDinner,
  MealType.snack => l.dietMealSnack,
  MealType.lateNight => l.dietMealLateNight,
};

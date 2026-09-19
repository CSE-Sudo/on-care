/// 끼니 종류. 이름이 곧 API `meal_type` 문자열이다 — 보내는 쪽도 읽는 쪽도
/// [MealType.name] 을 그대로 쓴다. 서버는 이 값을 검증하지 않는 자유 문자열
/// (`String(20)`)로 받으므로, 이름과 전송값이 갈리면 틀린 값이 조용히 저장되고
/// 트레이너 웹에서 간식으로 접힌다. 새 값을 더할 때도 이 규칙을 지킨다.
enum MealType { breakfast, lunch, dinner, snack, lateNight }

/// 서버가 준 `meal_type` → [MealType]. 모르는 값은 [MealType.snack] 으로 접는다.
///
/// 끼니는 늘어날 수 있고(#1988 의 `lateNight`), 앱은 저보다 새 서버를 만날 수
/// 있다. 그때 하루치 식단 전체가 파싱에서 죽는 것보다, 모르는 한 끼가 간식으로
/// 보이는 편이 낫다.
MealType _mealFromString(String s) => MealType.values.firstWhere(
  (m) => m.name == s,
  orElse: () => MealType.snack,
);

class FoodItem {
  const FoodItem({
    required this.name,
    required this.calories,
    this.amountG,
    this.sodiumMg = 0,
    this.sugarG = 0,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
  });
  final String name;
  final int calories;

  /// 그 음식을 얼마나 먹었나(g) — 아래 영양이 **무엇을 재고 나온 값인가** 다.
  ///
  /// 공공 영양 DB 는 100g 기준이라 서버 보정이 이 양으로 환산한다. 그래서 양이
  /// 바뀌면 나머지 여섯 값도 같은 비율로 움직여야 한다(#1876). 0 이 아니라
  /// **null** 인 것은 "안 먹었다" 와 "모른다" 가 다른 말이기 때문이다 — 양을
  /// 못 얻은 인식과 이 필드 이전 기록이 null 이고, 그때 수정 화면은 칸을 비워
  /// 두었다가 회원이 적어 넣는 값을 기준으로 삼는다.
  final double? amountG;

  /// Per-food nutrition, used by the diet-tab meal card to break a meal down
  /// food-by-food. Optional so backend payloads that omit them still parse.
  final int sodiumMg;
  final double sugarG;
  final double carbsG;
  final double proteinG;
  final double fatG;

  factory FoodItem.fromJson(Map<String, Object?> json) => FoodItem(
    name: json['name']! as String,
    calories: (json['calories']! as num).toInt(),
    // 0 이나 음수는 기준이 될 수 없다 — 없는 것과 같이 null 로 접는다.
    amountG: switch ((json['amount_g'] as num?)?.toDouble()) {
      final double g when g > 0 => g,
      _ => null,
    },
    sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
    sugarG: (json['sugar_g'] as num?)?.toDouble() ?? 0,
    carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
    proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
    fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
  );
}

class DietEntry {
  const DietEntry({
    this.id,
    required this.mealType,
    required this.timeLabel,
    required this.foods,
    required this.totalCalories,
    this.sodiumMg = 0,
    this.sugarG = 0,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.aiComment = '',
    this.photoAsset,
    this.photoUrl,
  });

  final String? id;
  final MealType mealType;
  final String timeLabel;
  final List<FoodItem> foods;
  final int totalCalories;
  final int sodiumMg;
  final double sugarG;
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// Short per-meal AI feedback shown on the diet-tab meal card. Empty when the
  /// backend hasn't produced a per-entry comment.
  final String aiComment;

  /// Bundled asset path for the meal thumbnail photo (demo data). Null falls
  /// back to the meal-type emoji.
  final String? photoAsset;

  /// API path of the photo the member actually uploaded (#699), relative to
  /// the API base. Null for entries recorded before photos were stored, and
  /// for entries whose photo could not be read. Takes precedence over
  /// [photoAsset]: the demo asset is a stand-in for exactly this.
  final String? photoUrl;

  factory DietEntry.fromJson(Map<String, Object?> json) => DietEntry(
    id: json['id'] as String?,
    mealType: _mealFromString(json['meal_type']! as String),
    timeLabel: json['time_label']! as String,
    foods: (json['foods']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(FoodItem.fromJson)
        .toList(),
    totalCalories: (json['total_calories']! as num).toInt(),
    sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
    sugarG: (json['sugar_g'] as num?)?.toDouble() ?? 0,
    carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
    proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
    fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
    aiComment: (json['ai_comment'] as String?) ?? '',
    photoAsset: json['photo_asset'] as String?,
    photoUrl: json['photo_url'] as String?,
  );
}

class DietMacros {
  const DietMacros({
    required this.carbsPct,
    required this.proteinPct,
    required this.fatPct,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
  });

  const DietMacros.zero()
    : carbsPct = 0,
      proteinPct = 0,
      fatPct = 0,
      carbsG = 0,
      proteinG = 0,
      fatG = 0;

  final int carbsPct;
  final int proteinPct;
  final int fatPct;
  final double carbsG;
  final double proteinG;
  final double fatG;

  factory DietMacros.fromJson(Map<String, Object?> json) => DietMacros(
    carbsPct: (json['carbs_pct'] as num?)?.toInt() ?? 0,
    proteinPct: (json['protein_pct'] as num?)?.toInt() ?? 0,
    fatPct: (json['fat_pct'] as num?)?.toInt() ?? 0,
    carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
    proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
    fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
  );
}

class DietDay {
  const DietDay({
    required this.entries,
    required this.totalCalories,
    required this.macros,
    required this.totalSodiumMg,
    required this.totalSugarG,
    required this.aiCoachMessage,
  });

  final List<DietEntry> entries;
  final int totalCalories;
  final DietMacros macros;
  final int totalSodiumMg;
  final double totalSugarG;
  final String aiCoachMessage;

  factory DietDay.fromJson(Map<String, Object?> json) => DietDay(
    entries: (json['entries']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(DietEntry.fromJson)
        .toList(),
    totalCalories: (json['total_calories']! as num).toInt(),
    totalSodiumMg: (json['total_sodium_mg']! as num).toInt(),
    totalSugarG: (json['total_sugar_g']! as num).toDouble(),
    macros: switch (json['macros']) {
      final Map<String, Object?> macros => DietMacros.fromJson(macros),
      _ => const DietMacros.zero(),
    },
    aiCoachMessage: json['ai_coach_message']! as String,
  );
}

/// 화면이 쓰는 하루 합계.
///
/// 끼니별 음식의 합을 먼저 보고, 그 합이 0 이면 서버가 준 하루 합계로 떨어진다.
/// 실서버 응답은 영양을 하루/끼니 단위로만 내려주기 때문이다(음식 배열에는
/// 이름과 칼로리만 들어 있다). 식단 탭의 하루 요약과 기간 뷰가 **같은 규칙**을
/// 써야 두 화면의 숫자가 어긋나지 않는다.
extension DietDayTotals on DietDay {
  List<FoodItem> get _allFoods => <FoodItem>[
    for (final DietEntry e in entries) ...e.foods,
  ];

  int get effectiveCalories {
    final int sum = _allFoods.fold<int>(
      0,
      (int a, FoodItem f) => a + f.calories,
    );
    return sum > 0 ? sum : totalCalories;
  }

  int get effectiveSodiumMg {
    final int sum = _allFoods.fold<int>(
      0,
      (int a, FoodItem f) => a + f.sodiumMg,
    );
    return sum > 0 ? sum : totalSodiumMg;
  }

  double get effectiveSugarG {
    final double sum = _allFoods.fold<double>(
      0,
      (double a, FoodItem f) => a + f.sugarG,
    );
    return sum > 0 ? sum : totalSugarG;
  }

  /// 탄단지도 같은 규칙으로 접는다 — 음식 → 끼니 → 하루 합계 순으로 내려간다.
  ///
  /// 하루 요약 카드는 `macros` 를 그대로 읽는데, 기간 뷰가 음식만 보고 계산하면
  /// 실서버 응답(음식에 영양이 없는 경우)에서 같은 날이 두 화면에서 다르게
  /// 나온다. 세 단계 모두를 거치는 이유다.
  double get effectiveCarbsG => _macro(
    (FoodItem f) => f.carbsG,
    (DietEntry e) => e.carbsG,
    macros.carbsG,
  );

  double get effectiveProteinG => _macro(
    (FoodItem f) => f.proteinG,
    (DietEntry e) => e.proteinG,
    macros.proteinG,
  );

  double get effectiveFatG =>
      _macro((FoodItem f) => f.fatG, (DietEntry e) => e.fatG, macros.fatG);

  double _macro(
    double Function(FoodItem) fromFood,
    double Function(DietEntry) fromEntry,
    double dayTotal,
  ) {
    final double foods = _allFoods.fold<double>(
      0,
      (double a, FoodItem f) => a + fromFood(f),
    );
    if (foods > 0) return foods;
    final double meals = entries.fold<double>(
      0,
      (double a, DietEntry e) => a + fromEntry(e),
    );
    return meals > 0 ? meals : dayTotal;
  }
}

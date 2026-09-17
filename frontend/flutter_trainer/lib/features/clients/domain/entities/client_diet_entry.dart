/// 그 끼니의 음식 하나 — 회원 앱 끼니 카드가 한 줄로 적는 값이다. (#1166)
///
/// 이름만 이어 붙인 [ClientDietEntry.items] 와 달리, 음식마다 칼로리·나트륨·
/// 당류를 들고 있다. 같은 2,000kcal 이 밥에서 왔는지 기름에서 왔는지는 끼니
/// 합계만 봐서는 알 수 없다.
class ClientDietFood {
  /// Creates one food row.
  const ClientDietFood({
    required this.name,
    this.calories = 0,
    this.sodiumMg = 0,
    this.sugarG = 0,
  });

  /// `{name, calories, sodium_mg, sugar_g}` — 회원 앱 `DietFood` 와 같은 키다.
  /// 두 앱이 같은 `foods_json` 을 읽으므로 키가 갈리면 한쪽만 비어 보인다.
  factory ClientDietFood.fromJson(Map<String, Object?> json) => ClientDietFood(
    name: (json['name'] as String?) ?? '',
    calories: (json['calories'] as num?)?.toInt() ?? 0,
    sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
    sugarG: (json['sugar_g'] as num?)?.toDouble() ?? 0,
  );

  final String name;
  final int calories;
  final int sodiumMg;
  final double sugarG;
}

/// One meal in a client's day (아침/점심/저녁/간식/야식), as shown on the 식단
/// sub-tab. Decoded from the drift `ClientDietEntries` row.
class ClientDietEntry {
  /// Creates a meal entry.
  const ClientDietEntry({
    this.id = '',
    required this.meal,
    required this.items,
    required this.calories,
    required this.sodiumMg,
    this.timeLabel = '',
    this.foods = const <ClientDietFood>[],
    this.sugarG = 0,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.photoUrl,
    this.photoAsset,
  });

  /// The backing `DietEntry.id`. 같은 날 같은 [meal] 라벨(예: 간식 두 번)이
  /// meal_type 중복을 막는 제약 없이 저장될 수 있어, 목록 위젯의 키로 [meal]
  /// 대신 이 값을 쓴다.
  final String id;

  /// Meal label (아침 | 점심 | 저녁 | 간식 | 야식).
  final String meal;

  /// Foods eaten, comma-joined (e.g. "오트밀, 바나나").
  final String items;

  /// Calories for this meal (kcal).
  final int calories;

  /// Sodium for this meal (mg).
  final int sodiumMg;

  /// 먹은 시각 문구(`08:30`). 회원 앱 끼니 카드가 끼니 배지 옆에 적는 값이다.
  /// 없으면(옛 기록·옛 시드) 아무것도 적지 않는다. (#1166)
  final String timeLabel;

  /// 음식별 영양. 비어 있으면 예전처럼 [items] 한 줄만 읽는다. (#1166)
  final List<ClientDietFood> foods;

  /// 그 끼니의 당류(g). 나트륨과 나란히 읽는 값이다(#1025).
  final double sugarG;

  /// Carbohydrates in this meal (g).
  final double carbsG;

  /// Protein in this meal (g).
  final double proteinG;

  /// Fat in this meal (g).
  final double fatG;

  /// API path of the photo the member uploaded for this meal (#699),
  /// relative to the API base. Null when the member recorded the meal before
  /// photos were stored, or the photo could not be saved — the card then
  /// reads exactly as it did before.
  ///
  /// 담당 트레이너 전용 경로다(`/trainer/clients/<id>/diet/photos/<photo>`).
  /// 회원 앱이 받는 경로와 다르며, 접근 판정은 서버가 담당 링크로 한다.
  final String? photoUrl;

  /// 데모에서 이 끼니로 보여 줄 번들 이미지 경로. 실 API 모드에서는 늘 null
  /// 이고 [photoUrl] 이 쓰인다 — 데모에는 회원이 올린 사진을 받아 올 백엔드가
  /// 없어 사진이 한 장도 뜨지 않았다(#819).
  final String? photoAsset;
}

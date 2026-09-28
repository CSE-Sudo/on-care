/// 4주 추천 메뉴 리스트 — 회원 앱·트레이너 웹 데모가 함께 쓴다. (#2250, #2379)
///
/// 회원 앱 데모는 `오늘` 다음 식사를 여기서 고르고, 트레이너 웹 데모는 회원에게 추천할
/// AI 후보를 여기서 낸다. 두 앱이 각자 들고 있으면 같은 회원에게 다른 메뉴를 말한다.
library;

/// 추천 메뉴 한 개.
typedef DemoPlanMenu = ({String slot, String name, String tag, String keyword});

/// 서버가 기록 없는 회원에게 만드는 카탈로그 리스트(`diet_menu_plan.rules_plan`).
/// 공유 사례 파일의 `demo_plan` 과 같은지 테스트가 본다.
const Map<String, List<DemoPlanMenu>>
kDemoMenuPlan = <String, List<DemoPlanMenu>>{
  'ko': <DemoPlanMenu>[
    (slot: 'breakfast', name: '그릭요거트 볼', tag: 'protein_high', keyword: '고단백'),
    (slot: 'breakfast', name: '현미 누룽지와 달걀', tag: 'sodium_low', keyword: '저나트륨'),
    (slot: 'breakfast', name: '바나나 오트밀', tag: 'fiber_high', keyword: '식이섬유'),
    (slot: 'breakfast', name: '과일 요거트 스무디', tag: 'calorie_low', keyword: '가벼운'),
    (slot: 'breakfast', name: '요거트와 견과', tag: 'sugar_low', keyword: '저당'),
    (slot: 'lunch', name: '닭가슴살 샐러드', tag: 'protein_high', keyword: '고단백'),
    (slot: 'lunch', name: '두부 스테이크 정식', tag: 'sodium_low', keyword: '저나트륨'),
    (slot: 'lunch', name: '현미 비빔밥', tag: 'fiber_high', keyword: '식이섬유'),
    (slot: 'lunch', name: '닭안심 샐러드 랩', tag: 'calorie_low', keyword: '가벼운'),
    (slot: 'lunch', name: '곤약 채소 비빔밥', tag: 'sugar_low', keyword: '저당'),
    (slot: 'dinner', name: '구운 고등어 정식', tag: 'protein_high', keyword: '고단백'),
    (slot: 'dinner', name: '연두부 채소찜', tag: 'sodium_low', keyword: '저나트륨'),
    (slot: 'dinner', name: '잡곡밥과 나물 반찬', tag: 'fiber_high', keyword: '식이섬유'),
    (slot: 'dinner', name: '두부 닭가슴살볼', tag: 'calorie_low', keyword: '가벼운'),
    (slot: 'dinner', name: '돼지 안심 수육', tag: 'sugar_low', keyword: '저당'),
    (slot: 'snack', name: '그릭요거트', tag: 'protein_high', keyword: '고단백'),
    (slot: 'snack', name: '방울토마토', tag: 'calorie_low', keyword: '가벼운'),
    (slot: 'snack', name: '무가당 두유', tag: 'sugar_low', keyword: '저당'),
  ],
  'en': <DemoPlanMenu>[
    (
      slot: 'breakfast',
      name: 'Greek yogurt bowl',
      tag: 'protein_high',
      keyword: 'High protein',
    ),
    (
      slot: 'breakfast',
      name: 'Brown rice porridge & egg',
      tag: 'sodium_low',
      keyword: 'Low sodium',
    ),
    (
      slot: 'breakfast',
      name: 'Banana oatmeal',
      tag: 'fiber_high',
      keyword: 'High fiber',
    ),
    (
      slot: 'breakfast',
      name: 'Fruit yogurt smoothie',
      tag: 'calorie_low',
      keyword: 'Light',
    ),
    (
      slot: 'breakfast',
      name: 'Plain yogurt & nuts',
      tag: 'sugar_low',
      keyword: 'Low sugar',
    ),
    (
      slot: 'lunch',
      name: 'Chicken breast salad',
      tag: 'protein_high',
      keyword: 'High protein',
    ),
    (
      slot: 'lunch',
      name: 'Tofu steak set',
      tag: 'sodium_low',
      keyword: 'Low sodium',
    ),
    (
      slot: 'lunch',
      name: 'Brown rice bibimbap',
      tag: 'fiber_high',
      keyword: 'High fiber',
    ),
    (
      slot: 'lunch',
      name: 'Chicken tender wrap',
      tag: 'calorie_low',
      keyword: 'Light',
    ),
    (
      slot: 'lunch',
      name: 'Konjac veggie bibimbap',
      tag: 'sugar_low',
      keyword: 'Low sugar',
    ),
    (
      slot: 'dinner',
      name: 'Grilled mackerel set',
      tag: 'protein_high',
      keyword: 'High protein',
    ),
    (
      slot: 'dinner',
      name: 'Steamed soft tofu & veggies',
      tag: 'sodium_low',
      keyword: 'Low sodium',
    ),
    (
      slot: 'dinner',
      name: 'Multigrain rice & namul',
      tag: 'fiber_high',
      keyword: 'High fiber',
    ),
    (
      slot: 'dinner',
      name: 'Chicken tofu patties',
      tag: 'calorie_low',
      keyword: 'Light',
    ),
    (
      slot: 'dinner',
      name: 'Boiled pork tenderloin',
      tag: 'sugar_low',
      keyword: 'Low sugar',
    ),
    (
      slot: 'snack',
      name: 'Greek yogurt',
      tag: 'protein_high',
      keyword: 'High protein',
    ),
    (
      slot: 'snack',
      name: 'Cherry tomatoes',
      tag: 'calorie_low',
      keyword: 'Light',
    ),
    (
      slot: 'snack',
      name: 'Unsweetened soy milk',
      tag: 'sugar_low',
      keyword: 'Low sugar',
    ),
  ],
};

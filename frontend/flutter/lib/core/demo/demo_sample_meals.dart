import 'dart:typed_data';

import 'package:demo_fixture/demo_fixture.dart';

/// 데모 식단 인식이 돌려주는 끼니(#3423).
///
/// 목업은 사진을 볼 수 없다. 그래서 두 갈래로 답한다.
///
///  * **샘플 사진** — 식단 추가 시트가 내놓는 데모 음식 사진이다. 고른 사진의
///    바이트를 [rememberDemoSamplePhoto] 로 적어 두면, 분석이 같은 바이트를 받아
///    [demoSampleMealOf] 로 그 사진의 끼니를 찾는다. 사진과 결과가 맞는다.
///  * **직접 올린 사진** — 끼니 종류에 맞는 예시([demoExampleMealFor])다. 사진과
///    맞지 않으므로 결과 화면이 예시임을 알린다.
///
/// 음식·영양·코멘트는 시드 끼니와 같은 픽스처 템플릿에서 온다 — 따로 적지 않는다.
final List<FixtureMeal> _templates = DemoFixture.load().mealTemplates;

/// 샘플 사진으로 내놓는 끼니. 사진 한 장에 끼니 하나다 — 같은 사진을 쓰는
/// 템플릿(점심·저녁 된장찌개)은 먼저 나온 것만 남긴다.
final List<FixtureMeal> demoSampleMeals = () {
  final Set<String> seen = <String>{};
  return <FixtureMeal>[
    for (final FixtureMeal meal in _templates)
      if (seen.add(meal.photoAsset)) meal,
  ];
}();

/// 끼니 종류별 예시 후보. 하루 합계를 크게 흔드는 끼니(짬뽕의 나트륨, 삼겹살·
/// 케이크의 열량·당류)는 뺐다 — 한 번 올렸다고 식단 탭 카드가 경고색으로
/// 뒤집히면 시연이 그 이야기로 흘러간다.
const Map<String, List<String>> _exampleSlugs = <String, List<String>>{
  'breakfast': <String>[
    'breakfast-oatmeal-banana',
    'breakfast-greek-yogurt-nuts',
    'breakfast-egg-strawberry',
  ],
  'lunch': <String>[
    'lunch-bibimbap',
    'lunch-chicken-salad',
    'lunch-doenjang-rice',
  ],
  'dinner': <String>['dinner-salmon-brown-rice', 'dinner-doenjang-rice'],
  'snack': <String>['snack-coffee-nuts'],
  'lateNight': <String>['breakfast-greek-yogurt-nuts'],
};

/// 방금 고른 샘플 사진의 지문 → 끼니 템플릿 이름. 앱이 켜져 있는 동안만 든다.
final Map<int, String> _sampleSlugByPrint = <int, String>{};

/// [bytes] 가 [meal] 의 샘플 사진임을 적어 둔다.
void rememberDemoSamplePhoto(FixtureMeal meal, Uint8List bytes) {
  _sampleSlugByPrint[_print(bytes)] = meal.slug;
}

/// [bytes] 가 샘플 사진이면 그 끼니. 직접 올린 사진이면 null 이다.
FixtureMeal? demoSampleMealOf(Uint8List? bytes) {
  if (bytes == null || _sampleSlugByPrint.isEmpty) return null;
  final String? slug = _sampleSlugByPrint[_print(bytes)];
  if (slug == null) return null;
  return _bySlug(slug);
}

/// 직접 올린 사진에 돌려줄 예시 끼니. 같은 사진은 늘 같은 끼니로 읽히고, 다른
/// 사진은 후보 안에서 갈린다 — 올릴 때마다 한 가지만 나오지 않게 한다.
FixtureMeal demoExampleMealFor(String mealType, Uint8List? bytes) {
  final List<String> slugs = _exampleSlugs[mealType] ?? _exampleSlugs['lunch']!;
  return _bySlug(slugs[(bytes?.length ?? 0) % slugs.length])!;
}

FixtureMeal? _bySlug(String slug) {
  for (final FixtureMeal meal in _templates) {
    if (meal.slug == slug) return meal;
  }
  return null;
}

/// 길이와 FNV-1a 해시를 묶은 지문. 사진 열두 장을 가리는 데 쓴다.
int _print(Uint8List bytes) {
  int hash = 0x811c9dc5;
  for (final int byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return Object.hash(bytes.length, hash);
}

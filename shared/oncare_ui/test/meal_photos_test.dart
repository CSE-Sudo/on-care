// 식단 추천 메뉴 사진 고르기 (#2435).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 서버 카탈로그(`backend/app/data/diet_menu_catalog.py`) 36개 — 한국어·영어·끼니.
const List<(String, String, String)> _catalog = <(String, String, String)>[
  ('그릭요거트 볼', 'Greek yogurt bowl', 'breakfast'),
  ('삶은 달걀과 고구마', 'Boiled eggs & sweet potato', 'breakfast'),
  ('바나나 오트밀', 'Banana oatmeal', 'breakfast'),
  ('두부 스크램블', 'Tofu scramble', 'breakfast'),
  ('현미 누룽지와 달걀', 'Brown rice porridge & egg', 'breakfast'),
  ('과일 요거트 스무디', 'Fruit yogurt smoothie', 'breakfast'),
  ('요거트와 견과', 'Plain yogurt & nuts', 'breakfast'),
  ('닭가슴살 샌드위치', 'Chicken breast sandwich', 'breakfast'),
  ('채소 달걀말이', 'Veggie rolled omelet', 'breakfast'),
  ('연어 베이글 반쪽', 'Half salmon bagel', 'breakfast'),
  ('현미 비빔밥', 'Brown rice bibimbap', 'lunch'),
  ('닭가슴살 샐러드', 'Chicken breast salad', 'lunch'),
  ('연어 포케', 'Salmon poke bowl', 'lunch'),
  ('두부 스테이크 정식', 'Tofu steak set', 'lunch'),
  ('두부 버섯 덮밥', 'Tofu mushroom rice bowl', 'lunch'),
  ('닭안심 샐러드 랩', 'Chicken tender wrap', 'lunch'),
  ('통밀 샐러드 파스타', 'Whole wheat salad pasta', 'lunch'),
  ('닭가슴살 도시락', 'Chicken breast lunchbox', 'lunch'),
  ('소고기 채소 덮밥', 'Beef & veggie rice bowl', 'lunch'),
  ('곤약 채소 비빔밥', 'Konjac veggie bibimbap', 'lunch'),
  ('구운 고등어 정식', 'Grilled mackerel set', 'dinner'),
  ('연두부 채소찜', 'Steamed soft tofu & veggies', 'dinner'),
  ('닭가슴살 채소볶음', 'Chicken breast stir-fry', 'dinner'),
  ('연어 스테이크', 'Salmon steak', 'dinner'),
  ('흰살생선 찜', 'Steamed white fish', 'dinner'),
  ('두부 닭가슴살볼', 'Chicken tofu patties', 'dinner'),
  ('잡곡밥과 나물 반찬', 'Multigrain rice & namul', 'dinner'),
  ('돼지 안심 수육', 'Boiled pork tenderloin', 'dinner'),
  ('소고기 샤브샤브', 'Beef shabu-shabu', 'dinner'),
  ('곤약 두부 비빔면', 'Konjac tofu noodles', 'dinner'),
  ('그릭요거트', 'Greek yogurt', 'snack'),
  ('삶은 달걀 2개', 'Two boiled eggs', 'snack'),
  ('무가당 두유', 'Unsweetened soy milk', 'snack'),
  ('방울토마토', 'Cherry tomatoes', 'snack'),
  ('바나나 1개', 'One banana', 'snack'),
  ('견과류 한 줌', 'Handful of nuts', 'snack'),
];

void main() {
  test('카탈로그 36개는 한국어·영어 모두 사진이 있고, 그 파일이 있다', () {
    expect(_catalog, hasLength(36));
    for (final (String ko, String en, String slot) in _catalog) {
      final String? a = AppMealPhotos.assetFor(ko, slot: slot);
      final String? b = AppMealPhotos.assetFor(en, slot: slot);
      expect(a, isNotNull, reason: ko);
      expect(b, a, reason: '$ko / $en');
      expect(File(a!).existsSync(), isTrue, reason: a);
    }
  });

  test('모든 사진 파일이 어딘가에서 쓰인다 — 쓰지 않는 에셋을 싣지 않는다', () {
    final Set<String> used = <String>{
      for (final (String ko, String _, String slot) in _catalog)
        AppMealPhotos.idFor(ko, slot: slot)!,
    };
    final Set<String> files = <String>{
      for (final FileSystemEntity f in Directory('assets/meals').listSync())
        f.uri.pathSegments.last.replaceAll('.jpg', ''),
    };
    expect(used, files);
  });

  test('AI 가 지은 이름은 재료·요리 낱말로 대표 사진을 고른다', () {
    const Map<String, String> cases = <String, String>{
      '현미 닭가슴살 덮밥': 'chicken-breast-bowl',
      '고등어 무조림 정식': 'grilled-mackerel-set',
      '연어 아보카도 베이글': 'salmon-bagel',
      '훈제연어 샐러드': 'salmon-steak',
      '닭가슴살 시저 샐러드': 'chicken-salad',
      '대구 맑은탕': 'white-fish-steamed',
      '소불고기 덮밥': 'beef-veggie-bowl',
      '돼지 앞다리 보쌈': 'pork-suyuk',
      '곤약 냉면': 'konjac-noodles',
      'Veggie tofu bowl': 'tofu-mushroom-bowl',
      'Oat milk latte with nuts': 'banana-oatmeal',
      '두부 곤약 비빔밥': 'brown-rice-bibimbap',
      '단호박 오트밀 죽': 'rice-porridge-egg',
      'Grilled chicken quinoa bowl': 'chicken-breast-bowl',
      'Baked cod with vegetables': 'white-fish-steamed',
    };
    cases.forEach((String name, String id) {
      expect(AppMealPhotos.idFor(name), id, reason: name);
    });
  });

  test('간식이면 같은 재료라도 간식 사진을 먼저', () {
    expect(AppMealPhotos.idFor('그릭요거트 한 컵'), 'greek-yogurt-bowl');
    expect(
      AppMealPhotos.idFor('그릭요거트 한 컵', slot: 'snack'),
      'snack-greek-yogurt',
    );
    expect(AppMealPhotos.idFor('구운 달걀', slot: 'snack'), 'snack-boiled-eggs');
    expect(AppMealPhotos.idFor('바나나', slot: 'snack'), 'snack-banana');
  });

  test('맞는 낱말이 없으면 사진 없음 — 화면은 끼니 아이콘', () {
    expect(AppMealPhotos.idFor('미역국 정식'), isNull);
    expect(AppMealPhotos.idFor(''), isNull);
  });
}

import 'package:flutter/widgets.dart';

/// 식단 추천 메뉴 사진 — 메뉴 이름으로 고른다. (#2435)
///
/// 트레이너가 확정하는 추천 메뉴는 카탈로그 키가 아니라 **이름**으로 온다. 서버가
/// AI 에게 받은 4주 메뉴 리스트(#2250)는 회원마다 이름이 달라 메뉴마다 사진을 둘 수
/// 없다. 대신 건강식은 재료·요리 몇 가지로 대부분 설명되므로 **대표 사진**을 두고,
///
///  1. 고정 카탈로그(`backend/app/data/diet_menu_catalog.py`) 이름과 같으면 그 사진,
///  2. 아니면 이름 속 재료·요리 낱말을 [_keywords] 순서대로 찾아 첫 사진,
///  3. 아무것도 안 맞으면 null — 화면은 끼니 아이콘을 그린다.
///
/// 회원 앱 홈 `트레이너 추천` 과 트레이너 웹 `AI 식단 추천` 이 같은 규칙으로 같은
/// 사진을 고른다. 그림은 이 패키지의 `assets/meals/<id>.jpg` 다.
abstract final class AppMealPhotos {
  /// 이 패키지 에셋이라 `Image.asset(…, package: AppMealPhotos.package)` 로 읽는다.
  static const String package = 'oncare_ui';

  static String assetOf(String id) => 'assets/meals/$id.jpg';

  /// [name] 에 맞는 사진의 에셋 경로. 없으면 null.
  ///
  /// [slot] 이 `snack` 이면 같은 재료라도 간식 사진(작은 그릇)을 먼저 본다 —
  /// `그릭요거트` 는 아침이면 토핑 볼, 간식이면 한 컵이다.
  static String? assetFor(String name, {String? slot}) {
    final String? id = idFor(name, slot: slot);
    return id == null ? null : assetOf(id);
  }

  /// [assetFor] 의 사진 id(`grilled-mackerel-set` …).
  static String? idFor(String name, {String? slot}) {
    final String key = _norm(name);
    if (key.isEmpty) return null;
    final String? exact = _catalog[key];
    if (exact != null) return exact;
    final bool snack = slot == 'snack';
    final String lower = name.toLowerCase();
    for (final (List<String> words, String id, String? snackId) in _keywords) {
      if (words.any((String w) => _has(key, lower, w))) {
        return snack && snackId != null ? snackId : id;
      }
    }
    return null;
  }

  static final RegExp _ascii = RegExp(r'^[a-z ]+$');

  /// 한국어 낱말은 띄어쓰기를 무시한 글자 조각으로 찾는다(`훈제연어` 의 `연어`).
  /// 영어 낱말은 **단어 첫머리**에서만 찾는다 — 조각으로 찾으면 `veggie` 의 `egg`,
  /// `boat` 의 `oat` 가 잡힌다. 끝은 열어 둬 복수형(`eggs`·`noodles`)도 잡는다.
  static bool _has(String key, String lower, String word) {
    if (!_ascii.hasMatch(word)) return key.contains(_norm(word));
    final String pattern = word.split(' ').map(RegExp.escape).join(r'[\s-]*');
    return RegExp(r'\b' + pattern).hasMatch(lower);
  }

  static String _norm(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 카탈로그 36개 — 한국어·영어 이름 → 사진. 서버 카탈로그를 바꾸면 함께 고친다.
  static final Map<String, String> _catalog = <String, String>{
    for (final (List<String> names, String id) in <(List<String>, String)>[
      // 아침
      (<String>['그릭요거트 볼', 'Greek yogurt bowl'], 'greek-yogurt-bowl'),
      (
        <String>['삶은 달걀과 고구마', 'Boiled eggs & sweet potato'],
        'boiled-eggs-sweet-potato',
      ),
      (<String>['바나나 오트밀', 'Banana oatmeal'], 'banana-oatmeal'),
      (<String>['두부 스크램블', 'Tofu scramble'], 'tofu-scramble'),
      (
        <String>['현미 누룽지와 달걀', 'Brown rice porridge & egg'],
        'rice-porridge-egg',
      ),
      (<String>['과일 요거트 스무디', 'Fruit yogurt smoothie'], 'yogurt-smoothie'),
      (<String>['요거트와 견과', 'Plain yogurt & nuts'], 'greek-yogurt-bowl'),
      (<String>['닭가슴살 샌드위치', 'Chicken breast sandwich'], 'chicken-sandwich'),
      (<String>['채소 달걀말이', 'Veggie rolled omelet'], 'egg-roll-omelet'),
      (<String>['연어 베이글 반쪽', 'Half salmon bagel'], 'salmon-bagel'),
      // 점심
      (<String>['현미 비빔밥', 'Brown rice bibimbap'], 'brown-rice-bibimbap'),
      (<String>['닭가슴살 샐러드', 'Chicken breast salad'], 'chicken-salad'),
      (<String>['연어 포케', 'Salmon poke bowl'], 'salmon-poke'),
      (<String>['두부 스테이크 정식', 'Tofu steak set'], 'tofu-steak-set'),
      (<String>['두부 버섯 덮밥', 'Tofu mushroom rice bowl'], 'tofu-mushroom-bowl'),
      (<String>['닭안심 샐러드 랩', 'Chicken tender wrap'], 'chicken-wrap'),
      (<String>['통밀 샐러드 파스타', 'Whole wheat salad pasta'], 'whole-wheat-pasta'),
      (<String>['닭가슴살 도시락', 'Chicken breast lunchbox'], 'chicken-breast-bowl'),
      (<String>['소고기 채소 덮밥', 'Beef & veggie rice bowl'], 'beef-veggie-bowl'),
      (<String>['곤약 채소 비빔밥', 'Konjac veggie bibimbap'], 'konjac-bibimbap'),
      // 저녁
      (<String>['구운 고등어 정식', 'Grilled mackerel set'], 'grilled-mackerel-set'),
      (<String>['연두부 채소찜', 'Steamed soft tofu & veggies'], 'soft-tofu-steamed'),
      (
        <String>['닭가슴살 채소볶음', 'Chicken breast stir-fry'],
        'chicken-breast-stirfry',
      ),
      (<String>['연어 스테이크', 'Salmon steak'], 'salmon-steak'),
      (<String>['흰살생선 찜', 'Steamed white fish'], 'white-fish-steamed'),
      (<String>['두부 닭가슴살볼', 'Chicken tofu patties'], 'chicken-breast-bowl'),
      (<String>['잡곡밥과 나물 반찬', 'Multigrain rice & namul'], 'multigrain-namul'),
      (<String>['돼지 안심 수육', 'Boiled pork tenderloin'], 'pork-suyuk'),
      (<String>['소고기 샤브샤브', 'Beef shabu-shabu'], 'beef-shabu'),
      (<String>['곤약 두부 비빔면', 'Konjac tofu noodles'], 'konjac-noodles'),
      // 간식
      (<String>['그릭요거트', 'Greek yogurt'], 'snack-greek-yogurt'),
      (<String>['삶은 달걀 2개', 'Two boiled eggs'], 'snack-boiled-eggs'),
      (<String>['무가당 두유', 'Unsweetened soy milk'], 'snack-soy-milk'),
      (<String>['방울토마토', 'Cherry tomatoes'], 'snack-cherry-tomatoes'),
      (<String>['바나나 1개', 'One banana'], 'snack-banana'),
      (<String>['견과류 한 줌', 'Handful of nuts'], 'snack-nuts'),
    ])
      for (final String n in names) _norm(n): id,
  };

  /// AI 가 지은 이름용 — (낱말, 사진, 간식이면 쓸 사진). **순서가 규칙이다**: 더 구체적인
  /// 요리·재료가 먼저다. `연어 베이글` 은 `연어` 보다 `베이글` 이, `닭가슴살 샐러드` 는
  /// `닭` 보다 `샐러드` 가, `곤약 비빔밥` 은 `곤약` 보다 `비빔밥` 이 먼저 잡힌다.
  static const List<(List<String>, String, String?)>
  _keywords = <(List<String>, String, String?)>[
    (<String>['고등어', 'mackerel'], 'grilled-mackerel-set', null),
    (<String>['베이글', 'bagel'], 'salmon-bagel', null),
    (<String>['포케', 'poke'], 'salmon-poke', null),
    (<String>['연어', 'salmon'], 'salmon-steak', null),
    (
      <String>['흰살', '생선', '대구', '동태', '광어', 'fish', 'cod'],
      'white-fish-steamed',
      null,
    ),
    (<String>['샤브', 'shabu'], 'beef-shabu', null),
    (<String>['소고기', '쇠고기', '불고기', 'beef'], 'beef-veggie-bowl', null),
    (<String>['수육', '돼지', '보쌈', 'pork'], 'pork-suyuk', null),
    (<String>['두부스테이크', 'tofu steak'], 'tofu-steak-set', null),
    (<String>['스크램블', 'scramble'], 'tofu-scramble', null),
    (<String>['연두부', 'soft tofu'], 'soft-tofu-steamed', null),
    (<String>['샌드위치', 'sandwich', '토스트', 'toast'], 'chicken-sandwich', null),
    (<String>['랩', 'wrap', '부리또', 'burrito'], 'chicken-wrap', null),
    (<String>['파스타', 'pasta'], 'whole-wheat-pasta', null),
    (<String>['비빔밥', 'bibimbap'], 'brown-rice-bibimbap', null),
    (<String>['샐러드', 'salad'], 'chicken-salad', null),
    (<String>['볶음', 'stir'], 'chicken-breast-stirfry', null),
    (<String>['닭', '치킨', 'chicken'], 'chicken-breast-bowl', null),
    (<String>['두부', 'tofu'], 'tofu-mushroom-bowl', null),
    (
      <String>['달걀말이', '계란말이', '오믈렛', 'omelet', 'omelette'],
      'egg-roll-omelet',
      null,
    ),
    (<String>['고구마', 'sweet potato'], 'boiled-eggs-sweet-potato', null),
    (<String>['누룽지', '죽', 'porridge'], 'rice-porridge-egg', null),
    (<String>['오트밀', '오트', 'oat'], 'banana-oatmeal', null),
    (<String>['스무디', 'smoothie', '셰이크', 'shake'], 'yogurt-smoothie', null),
    (
      <String>['요거트', '요구르트', 'yogurt'],
      'greek-yogurt-bowl',
      'snack-greek-yogurt',
    ),
    (<String>['곤약', '면', 'noodle', '국수'], 'konjac-noodles', null),
    (<String>['나물', '잡곡', 'namul', 'multigrain'], 'multigrain-namul', null),
    (
      <String>['달걀', '계란', 'egg'],
      'boiled-eggs-sweet-potato',
      'snack-boiled-eggs',
    ),
    (<String>['두유', 'soy milk'], 'snack-soy-milk', null),
    (<String>['토마토', 'tomato'], 'snack-cherry-tomatoes', null),
    (<String>['바나나', 'banana'], 'banana-oatmeal', 'snack-banana'),
    (<String>['견과', '아몬드', '호두', 'nut', 'almond'], 'snack-nuts', null),
    (<String>['덮밥', '도시락', 'bowl', 'lunchbox'], 'chicken-breast-bowl', null),
  ];
}

/// 메뉴 사진 한 장 — [AppMealPhotos] 가 고른 에셋. 에셋이 없으면(에셋 목록이 바뀐
/// 경우) [fallback] 을 그린다.
class AppMealPhoto extends StatelessWidget {
  const AppMealPhoto({
    super.key,
    required this.asset,
    required this.fallback,
    this.width,
    this.height,
    this.semanticLabel,
  });

  final String asset;
  final Widget fallback;
  final double? width;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    package: AppMealPhotos.package,
    width: width,
    height: height,
    fit: BoxFit.cover,
    semanticLabel: semanticLabel,
    errorBuilder: (BuildContext context, Object _, StackTrace? _) => fallback,
  );
}

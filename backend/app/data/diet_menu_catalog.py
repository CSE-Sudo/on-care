"""끼니별 추천 메뉴 리스트의 **내장 카탈로그** — AI 가 실패했을 때 채우는 쪽. (#2250)

추천 메뉴 리스트는 AI 에게 받는다(`diet_menu_plan`). 그런데 키가 없거나, AI 가
늦거나, 끼니 하나를 모자라게 주면 리스트가 비고 `오늘` 조언이 다음 식사를 말하지
못한다. 그 빈자리를 여기 메뉴로 채운다 — **AI 는 품질을 올리는 층이지 가용성의
전제가 아니다**(홈 추천 식단과 같은 원칙).

끼니마다 리스트에 드는 개수(아침·점심·저녁 5, 간식 3)보다 **넉넉히** 둔다. 새
리스트는 이전 리스트의 메뉴를 빼고 만들어야 해서, 같은 수만 있으면 두 번째
리스트부터 채울 메뉴가 없다.

영양 값은 1인분 기준 **대략의 추정치**다. 화면에 수치로 내보내지 않고, 오늘의
부족·초과를 메우는 메뉴를 고를 때 순서를 정하는 데만 쓴다.
"""
from __future__ import annotations

from dataclasses import dataclass

#: 끼니 이름. 식단 기록의 `meal_type` 과 같은 말이다(야식은 추천하지 않는다).
SLOT_BREAKFAST = "breakfast"
SLOT_LUNCH = "lunch"
SLOT_DINNER = "dinner"
SLOT_SNACK = "snack"
SLOTS = (SLOT_BREAKFAST, SLOT_LUNCH, SLOT_DINNER, SLOT_SNACK)

#: 끼니마다 리스트에 드는 메뉴 수. 간식은 저녁까지 먹고도 부족분이 남았을 때만
#: 쓰므로 적게 둔다.
SLOT_COUNTS = {SLOT_BREAKFAST: 5, SLOT_LUNCH: 5, SLOT_DINNER: 5, SLOT_SNACK: 3}

#: 추천 이유 태그. 메뉴 하나에 하나다 — "무엇을 채우려고 추천했나" 가 하나여야
#: `오늘` 조언이 "그 이유가 충족되면 다른 메뉴로" 바꿀 수 있다.
TAG_SODIUM_LOW = "sodium_low"
TAG_PROTEIN_HIGH = "protein_high"
TAG_CALORIE_LOW = "calorie_low"
TAG_CALORIE_HIGH = "calorie_high"
TAG_SUGAR_LOW = "sugar_low"
TAG_FIBER_HIGH = "fiber_high"
TAGS = (
    TAG_PROTEIN_HIGH, TAG_SODIUM_LOW, TAG_FIBER_HIGH,
    TAG_CALORIE_LOW, TAG_SUGAR_LOW, TAG_CALORIE_HIGH,
)

#: 태그의 기본 키워드. AI 가 키워드를 빠뜨리거나 너무 길게 주면 이것을 쓴다.
TAG_KEYWORDS = {
    "ko": {
        TAG_SODIUM_LOW: "저나트륨",
        TAG_PROTEIN_HIGH: "고단백",
        TAG_CALORIE_LOW: "가벼운",
        TAG_CALORIE_HIGH: "든든한",
        TAG_SUGAR_LOW: "저당",
        TAG_FIBER_HIGH: "식이섬유",
    },
    "en": {
        TAG_SODIUM_LOW: "Low sodium",
        TAG_PROTEIN_HIGH: "High protein",
        TAG_CALORIE_LOW: "Light",
        TAG_CALORIE_HIGH: "Filling",
        TAG_SUGAR_LOW: "Low sugar",
        TAG_FIBER_HIGH: "High fiber",
    },
}


@dataclass(frozen=True)
class CatalogMenu:
    slot: str
    name_ko: str
    name_en: str
    tag: str
    kcal: int
    protein_g: int
    sodium_mg: int

    def name(self, lang: str) -> str:
        return self.name_en if lang == "en" else self.name_ko


CATALOG: tuple[CatalogMenu, ...] = (
    # 아침
    CatalogMenu(SLOT_BREAKFAST, "그릭요거트 볼", "Greek yogurt bowl", TAG_PROTEIN_HIGH, 220, 18, 80),
    CatalogMenu(SLOT_BREAKFAST, "삶은 달걀과 고구마", "Boiled eggs & sweet potato", TAG_PROTEIN_HIGH, 300, 14, 150),
    CatalogMenu(SLOT_BREAKFAST, "바나나 오트밀", "Banana oatmeal", TAG_FIBER_HIGH, 320, 10, 60),
    CatalogMenu(SLOT_BREAKFAST, "두부 스크램블 토스트", "Tofu scramble toast", TAG_PROTEIN_HIGH, 330, 20, 380),
    CatalogMenu(SLOT_BREAKFAST, "현미 누룽지와 달걀", "Brown rice porridge & egg", TAG_SODIUM_LOW, 280, 10, 150),
    CatalogMenu(SLOT_BREAKFAST, "과일 요거트 스무디", "Fruit yogurt smoothie", TAG_CALORIE_LOW, 200, 8, 70),
    CatalogMenu(SLOT_BREAKFAST, "플레인 요거트와 견과", "Plain yogurt & nuts", TAG_SUGAR_LOW, 260, 12, 60),
    CatalogMenu(SLOT_BREAKFAST, "닭가슴살 샌드위치", "Chicken breast sandwich", TAG_PROTEIN_HIGH, 380, 28, 620),
    CatalogMenu(SLOT_BREAKFAST, "채소 달걀말이", "Veggie rolled omelet", TAG_SODIUM_LOW, 250, 15, 300),
    CatalogMenu(SLOT_BREAKFAST, "연어 베이글 반쪽", "Half salmon bagel", TAG_CALORIE_HIGH, 450, 22, 700),
    # 점심
    CatalogMenu(SLOT_LUNCH, "현미 비빔밥", "Brown rice bibimbap", TAG_FIBER_HIGH, 550, 18, 700),
    CatalogMenu(SLOT_LUNCH, "닭가슴살 샐러드", "Chicken breast salad", TAG_PROTEIN_HIGH, 380, 32, 520),
    CatalogMenu(SLOT_LUNCH, "연어 포케", "Salmon poke bowl", TAG_PROTEIN_HIGH, 560, 28, 650),
    CatalogMenu(SLOT_LUNCH, "두부 스테이크 정식", "Tofu steak set", TAG_SODIUM_LOW, 480, 24, 600),
    CatalogMenu(SLOT_LUNCH, "두부 버섯 덮밥", "Tofu mushroom rice bowl", TAG_SODIUM_LOW, 500, 20, 550),
    CatalogMenu(SLOT_LUNCH, "닭안심 샐러드 랩", "Chicken tender wrap", TAG_CALORIE_LOW, 420, 26, 600),
    CatalogMenu(SLOT_LUNCH, "통밀 샐러드 파스타", "Whole wheat salad pasta", TAG_FIBER_HIGH, 520, 16, 500),
    CatalogMenu(SLOT_LUNCH, "닭가슴살 현미 도시락", "Chicken & brown rice box", TAG_PROTEIN_HIGH, 520, 35, 550),
    CatalogMenu(SLOT_LUNCH, "소고기 채소 덮밥", "Beef & veggie rice bowl", TAG_CALORIE_HIGH, 650, 30, 800),
    CatalogMenu(SLOT_LUNCH, "곤약 채소 비빔밥", "Konjac veggie bibimbap", TAG_SUGAR_LOW, 380, 12, 500),
    # 저녁
    CatalogMenu(SLOT_DINNER, "구운 고등어 정식", "Grilled mackerel set", TAG_PROTEIN_HIGH, 600, 32, 650),
    CatalogMenu(SLOT_DINNER, "연두부 채소찜", "Steamed soft tofu & veggies", TAG_SODIUM_LOW, 300, 18, 350),
    CatalogMenu(SLOT_DINNER, "닭가슴살 채소볶음", "Chicken breast stir-fry", TAG_PROTEIN_HIGH, 450, 35, 600),
    CatalogMenu(SLOT_DINNER, "연어 스테이크와 채소", "Salmon steak & veggies", TAG_PROTEIN_HIGH, 520, 30, 400),
    CatalogMenu(SLOT_DINNER, "흰살생선 찜", "Steamed white fish", TAG_SODIUM_LOW, 380, 30, 300),
    CatalogMenu(SLOT_DINNER, "닭가슴살 두부 샐러드", "Chicken & tofu salad", TAG_CALORIE_LOW, 350, 30, 450),
    CatalogMenu(SLOT_DINNER, "잡곡밥과 나물 반찬", "Multigrain rice & namul", TAG_FIBER_HIGH, 480, 14, 550),
    CatalogMenu(SLOT_DINNER, "돼지 안심 수육", "Boiled pork tenderloin", TAG_SUGAR_LOW, 480, 34, 400),
    CatalogMenu(SLOT_DINNER, "소고기 샤브샤브", "Beef shabu-shabu", TAG_CALORIE_HIGH, 560, 32, 800),
    CatalogMenu(SLOT_DINNER, "곤약 두부 비빔면", "Konjac tofu noodles", TAG_CALORIE_LOW, 330, 14, 600),
    # 간식
    CatalogMenu(SLOT_SNACK, "그릭요거트", "Greek yogurt", TAG_PROTEIN_HIGH, 120, 10, 40),
    CatalogMenu(SLOT_SNACK, "삶은 달걀 2개", "Two boiled eggs", TAG_PROTEIN_HIGH, 150, 12, 140),
    CatalogMenu(SLOT_SNACK, "무가당 두유", "Unsweetened soy milk", TAG_SUGAR_LOW, 90, 7, 90),
    CatalogMenu(SLOT_SNACK, "방울토마토", "Cherry tomatoes", TAG_CALORIE_LOW, 30, 1, 10),
    CatalogMenu(SLOT_SNACK, "바나나 1개", "One banana", TAG_CALORIE_HIGH, 100, 1, 0),
    CatalogMenu(SLOT_SNACK, "견과류 한 줌", "Handful of nuts", TAG_CALORIE_HIGH, 170, 5, 0),
)


def for_slot(slot: str) -> list[CatalogMenu]:
    return [m for m in CATALOG if m.slot == slot]

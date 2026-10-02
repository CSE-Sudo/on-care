"""
홈 "AI 추천 식단" 요리 카탈로그 — 추천의 선택지 집합.

추천 파이프라인은 **자유 생성이 아니라 이 카탈로그에서 고르는** 방식이다. 이유:
앱의 추천 카드는 요리별 번들 이미지(assets/images/rec-*.jpg)와 로케일별 문구
(app_ko/app_en.arb 의 homeMeal*)를 갖는다. LLM 이 임의의 요리명을 생성하면 대응하는
사진이 없고, 생성 문구는 로케일을 따르지 않아 영어 화면에 한국어가 섞인다.

그래서 계약은 "서버는 key 만 고르고, 그리기는 앱이 한다"이다:
- 서버 → `key` (+ 선택 근거 `reason_key`, 선택적으로 LLM 이 쓴 `reason_text`)
- 앱   → key 로 에셋·배경색·태그색·l10n 문자열을 찾아 지금과 동일하게 렌더

따라서 여기 `key` 는 **앱과 공유하는 계약**이다. 항목을 추가하려면 세 곳이 같이
늘어야 한다: (1) 이 카탈로그, (2) assets/images/rec-*, (3) app_ko/app_en.arb 문구.
셋 중 하나라도 빠지면 앱이 그 key 를 그리지 못하므로, 앱은 모르는 key 를 조용히
버리고 폴백 순서를 채운다.

`DEFAULT_ORDER` 는 개인화 근거가 없을 때(신규 가입자·LLM 실패) 쓰는 순서이며,
현재 홈 화면의 하드코딩 순서와 동일하다. 즉 폴백 = 지금 화면.
"""
from __future__ import annotations

from dataclasses import dataclass, field


#: 추천 이유 코드. 앱이 l10n 문구(homeMealReason*)로 번역하므로 문자열이 아니라
#: 코드로 주고받는다. 앱의 매핑 테이블과 값이 일치해야 한다.
REASON_SODIUM = "sodium"      # 나트륨 조절에 좋아요
REASON_GLUCOSE = "glucose"    # 혈당 안정에 도움돼요
REASON_OMEGA = "omega"        # 오메가3 + 식이섬유
REASON_LOW_CAL = "low_cal"    # 칼로리 낮고 포만감↑
REASON_FIBER = "fiber"        # 식이섬유가 풍부해요


@dataclass(frozen=True)
class MealItem:
    """카탈로그 한 항목.

    `tags` 는 LLM 프롬프트에 넣는 성격 표시이고, `nutrition` 은 1인분 기준 근사치다.
    정확한 영양 계산이 목적이 아니라 "왜 이걸 골랐는지"를 LLM 과 규칙 폴백이 같은
    근거로 판단하게 하려는 용도다.
    """

    key: str
    tags: tuple[str, ...]
    default_reason: str
    #: 1인분 근사 영양 — (kcal, 나트륨mg, 당류g, 단백질g, 식이섬유g)
    calories: int
    sodium_mg: int
    sugar_g: float
    protein_g: float
    fiber_g: float
    #: 이 요리가 특히 유리한 상황. 규칙 폴백의 점수 가중치로 쓰인다.
    #:
    #: 값은 반드시 `diet_recommendation_service.build_context` 가 **실제로 만들어 내는**
    #: 신호여야 한다. 생성되지 않는 신호를 적어 두면 점수에 영영 반영되지 않으면서
    #: 코드를 읽는 사람만 헷갈린다(전에 `fiber_low` 가 그랬다 — 식이섬유는 DietEntry 에
    #: 컬럼 자체가 없어 신호를 만들 수 없다). 불일치는 테스트가 잡는다.
    good_for: tuple[str, ...] = field(default=())


#: 현재 홈 화면에 있는 5종. 순서 = 현재 화면 순서(= DEFAULT_ORDER).
CATALOG: tuple[MealItem, ...] = (
    MealItem(
        key="chicken_salad",
        tags=("저나트륨", "고단백", "샐러드"),
        default_reason=REASON_SODIUM,
        calories=320, sodium_mg=290, sugar_g=6.0, protein_g=31.0, fiber_g=5.0,
        good_for=("sodium_high", "protein_low"),
    ),
    MealItem(
        key="brown_rice_box",
        tags=("저GI", "정식", "복합탄수"),
        default_reason=REASON_GLUCOSE,
        calories=520, sodium_mg=610, sugar_g=7.0, protein_g=22.0, fiber_g=7.0,
        good_for=("sugar_high", "calorie_low"),
    ),
    MealItem(
        key="salmon",
        tags=("고단백", "오메가3", "구이"),
        default_reason=REASON_OMEGA,
        calories=480, sodium_mg=430, sugar_g=3.0, protein_g=38.0, fiber_g=4.0,
        good_for=("protein_low", "sodium_high"),
    ),
    MealItem(
        key="tofu",
        tags=("저칼로리", "식물성단백", "볶음"),
        default_reason=REASON_LOW_CAL,
        calories=280, sodium_mg=520, sugar_g=5.0, protein_g=19.0, fiber_g=6.0,
        good_for=("calorie_high",),
    ),
    MealItem(
        key="namul_bibimbap",
        tags=("고식이섬유", "채식", "한식"),
        default_reason=REASON_FIBER,
        calories=560, sodium_mg=720, sugar_g=9.0, protein_g=16.0, fiber_g=11.0,
        good_for=("sugar_high",),
    ),
)

#: 개인화 근거가 없을 때 쓰는 순서. 현재 홈 화면 하드코딩 순서와 동일하다.
DEFAULT_ORDER: tuple[str, ...] = tuple(item.key for item in CATALOG)

#: 한 번에 노출하는 카드 수. 앱 캐러셀이 항상 이 개수를 그린다(부족하면 폴백으로 보충).
RECOMMENDATION_COUNT = len(CATALOG)

_BY_KEY: dict[str, MealItem] = {item.key: item for item in CATALOG}


def get(key: str) -> MealItem | None:
    """카탈로그 조회. LLM 이 지어낸 key 를 걸러내는 게이트로도 쓴다."""
    return _BY_KEY.get(key)

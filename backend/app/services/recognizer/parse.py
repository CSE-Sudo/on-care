"""비전 모델 응답(JSON) → 인식 결과. 두 인식기(Gemini·LiteLLM)가 같이 쓴다. (#3090)

모델 응답은 **외부 입력**이다. 음수·거대값·문자열·긴 문장이 올 수 있고, 그
값이 그대로 끼니 합계·트레이너 화면·개인 RAG 문서로 흘러간다. 그래서 여기서

- 영양 수치는 음수·비유한값·현실적 상한 초과를 "모름"(None)으로 눕힌다. 한 칸의
  이상값 때문에 그 음식이나 끼니 전체를 잃지 않게 하려는 것이다.
- 그래도 검증을 통과하지 못하는 항목(예: 확신도 1.5)은 **그 항목만** 뺀다. 예전에는
  `ValidationError` 하나가 사진 전체를 502 로 만들었다.
- 이름·식단평·항목 수는 상한까지만 받는다.

상한은 "모델이 지어낸 값" 을 거르는 선이다. 공공 DB 보강(`nutrition/enrich.py`)이
DB 밀도 × 양으로 다시 계산한 값은 이 상한을 거치지 않는다 — 양(`amount_g`)에
상한을 둬서 그 계산도 저장 컬럼(`Integer`) 범위 안에 머문다.

두 엔진의 변환 규칙이 갈리면 같은 사진이 엔진에 따라 다른 끼니가 되므로 한 곳에 둔다.
"""
from __future__ import annotations

import math
from typing import Any

from pydantic import ValidationError

from app.schemas.diet import RecognizedFood
from app.services.recognizer.locale_prompt import DISPLAY_NAME_MAX, display_name_of

#: 음식 이름 최대 길이. 표시 이름과 같다 — 카드·트레이너 목록이 같은 폭을 쓴다.
NAME_MAX = DISPLAY_NAME_MAX
#: 식단평 최대 길이. 프롬프트는 2~3문장을 요구한다.
COACH_COMMENT_MAX = 300
#: 한 사진에서 받는 음식 항목 수 상한.
FOODS_MAX = 20

#: 한 음식 항목의 현실적 상한. 넘으면 모델이 지어낸 값으로 보고 "모름" 으로 둔다.
CALORIES_MAX = 5000  # kcal
SODIUM_MG_MAX = 20000  # mg
MACRO_G_MAX = 1000.0  # 탄수화물·단백질·지방·당류 g
AMOUNT_G_MAX = 5000.0  # 사진에 담긴 양 g

UNKNOWN_FOOD_NAME = "알 수 없음"


def _finite(v: Any) -> float | None:
    if v is None or isinstance(v, bool):
        return None
    try:
        value = float(v)
    except (TypeError, ValueError, OverflowError):
        return None
    return value if math.isfinite(value) else None


def as_bounded_int(v: Any, upper: int) -> int | None:
    """0 이상 ``upper`` 이하 정수. 음수·비유한값·초과는 None."""
    value = _finite(v)
    if value is None or value < 0 or value > upper:
        return None
    return round(value)


def as_macro_float(v: Any, upper: float = MACRO_G_MAX) -> float | None:
    """0 이상 ``upper`` 이하 소수(g). 음수·비유한값·초과는 None."""
    value = _finite(v)
    if value is None or value < 0 or value > upper:
        return None
    return value


def as_amount_g(v: Any) -> float | None:
    """사진에 담긴 양(g). 0·음수·비유한값·상한 초과는 "모름"(None). (#2090)

    `RecognizedFood.amount_g` 는 `gt=0` 이라 0 을 그대로 넘기면 검증 오류가 난다.
    모델이 0 을 줬다는 건 양을 모른다는 뜻이다 — 보정이 알려진 1회 섭취량으로
    폴백하거나 추정치를 유지한다.
    """
    value = _finite(v)
    if value is None or value <= 0 or value > AMOUNT_G_MAX:
        return None
    return value


def as_float(v: Any) -> float | None:
    """확신도. 범위는 스키마가 본다 — 벗어나면 그 항목을 뺀다."""
    if v is None or isinstance(v, bool):
        return None
    try:
        return float(v)
    except (TypeError, ValueError, OverflowError):
        return None


def clean_text(v: Any, limit: int) -> str:
    """문자열이면 공백을 한 칸으로 접고 ``limit`` 자까지. 아니면 빈 문자열."""
    if not isinstance(v, str):
        return ""
    return " ".join(v.split())[:limit]


def food_from(item: Any) -> RecognizedFood | None:
    """모델이 준 음식 한 항목 → RecognizedFood. 읽을 수 없으면 None(그 항목만 뺀다)."""
    if not isinstance(item, dict):
        return None
    try:
        return RecognizedFood(
            name=clean_text(item.get("name"), NAME_MAX) or UNKNOWN_FOOD_NAME,
            display_name=display_name_of(item),
            amount_g=as_amount_g(item.get("amount_g")),
            calories=as_bounded_int(item.get("calories"), CALORIES_MAX),
            carbs_g=as_macro_float(item.get("carbs_g")),
            protein_g=as_macro_float(item.get("protein_g")),
            fat_g=as_macro_float(item.get("fat_g")),
            sodium_mg=as_bounded_int(item.get("sodium_mg"), SODIUM_MG_MAX),
            # 당류는 계약상 소수지만 인식기는 정수로 받아 왔다(프롬프트가 정수를 요구).
            sugar_g=as_bounded_int(item.get("sugar_g"), int(MACRO_G_MAX)),
            confidence=as_float(item.get("confidence")),
        )
    except ValidationError:
        return None


def parse_payload(data: Any) -> tuple[list[RecognizedFood], str]:
    """``json.loads`` 결과 → (음식 목록, 식단평). 모양이 틀리면 빈 결과.

    최상위가 객체가 아니거나 ``foods`` 가 목록이 아니면 음식이 없는 것으로 본다 —
    부르는 쪽(`POST /diet/analyze`)이 "음식 없음" 422 로 답한다.
    """
    if not isinstance(data, dict):
        return [], ""
    coach_comment = clean_text(data.get("coach_comment"), COACH_COMMENT_MAX)
    raw_foods = data.get("foods")
    if not isinstance(raw_foods, list):
        return [], coach_comment
    foods: list[RecognizedFood] = []
    for item in raw_foods:
        food = food_from(item)
        if food is None:
            continue
        foods.append(food)
        if len(foods) >= FOODS_MAX:
            break
    return foods, coach_comment

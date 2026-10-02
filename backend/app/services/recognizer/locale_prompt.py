"""사진 인식 프롬프트의 화면 언어 지시. (#2850)

인식기 프롬프트는 음식 이름과 식단평을 한국어로 받도록 짜여 있다. 음식 이름은
공공 식품영양성분 DB 보강(`nutrition/enrich.py`)이 **한국어 이름으로** 매칭하므로
바꿀 수 없다. 그래서 영어 화면이면 이름은 그대로 두고 화면에 보일 영어 이름
(`display_name`)을 한 칸 더 받고, 식단평만 영어로 받는다.

프롬프트 본문은 고치지 않고 **끝에 덧붙인다** — 본문은 엔진마다 따로 다듬어지고,
언어 규칙은 두 엔진이 같아야 하기 때문이다.
"""
from __future__ import annotations

from typing import Any

from app.core.locale import Locale, current_locale

#: 표시 이름의 최대 길이. 모델이 설명을 늘어놓아도 카드가 깨지지 않게 자른다.
DISPLAY_NAME_MAX = 80

_EN_INSTRUCTION = """

[화면 언어: 영어]
회원이 앱을 영어로 쓰고 있습니다. 아래 두 가지만 바꿔 응답하세요.
- foods 의 각 항목에 "display_name" 을 더해 그 음식의 자연스러운 영어 이름을 적으세요
  (예: "Kimchi stew", "Brown rice"). "name" 은 영양 DB 매칭용이니 **지금처럼 한국어**로 두세요.
- "coach_comment" 는 한국어가 아니라 **영어**로 2~3문장 쓰세요. 다른 규칙은 같습니다."""


def localized_prompt(base: str, locale: Locale | None = None) -> str:
    """요청 언어에 맞춘 인식 프롬프트. 한국어면 ``base`` 그대로다."""
    if (locale or current_locale()) == "en":
        return base + _EN_INSTRUCTION
    return base


def display_name_of(food: Any) -> str | None:
    """모델이 준 음식 한 항목의 표시 이름. 비었거나 문자열이 아니면 없다(None)."""
    if not isinstance(food, dict):
        return None
    value = food.get("display_name")
    if not isinstance(value, str):
        return None
    value = " ".join(value.split())
    if not value:
        return None
    return value[:DISPLAY_NAME_MAX]

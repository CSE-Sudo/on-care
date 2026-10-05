"""홈 AI 조언·추천 식단 문장이 요청 언어를 따른다(#2721, #2722). DB 없이 돈다.

헤더가 없으면 지금까지처럼 한국어다.
"""
from __future__ import annotations

import re
from contextlib import contextmanager

from app.api.v1.dashboard import _build_sodium_warning
from app.core.locale import _request_locale_ctx
from app.services import diet_recommendation_service as reco

_HANGUL = re.compile("[가-힣]")


@contextmanager
def _english():
    token = _request_locale_ctx.set("en")
    try:
        yield
    finally:
        _request_locale_ctx.reset(token)


def test_sodium_warning_follows_the_locale():
    assert _build_sodium_warning(2500, []).startswith("오늘 나트륨이")
    with _english():
        plain = _build_sodium_warning(2500, [])
        named = _build_sodium_warning(2500, ["라면", "김치"])
    assert not _HANGUL.search(plain)
    assert "2,500 mg" in plain
    # 음식 이름은 회원이 적은 그대로 둔다.
    assert named == "Sodium is high from 라면 and 김치."


def _ctx() -> reco.NutritionContext:
    return reco.NutritionContext(
        days_with_data=3,
        avg_sodium_mg=2600,
        avg_sugar_g=20.0,
        avg_calories=1800,
        avg_protein_g=60.0,
        sodium_limit_mg=2000,
        sugar_limit_g=50,
        calorie_limit=2000,
        conditions="",
        goals="",
        signals=("sodium_high",),
    )


def test_recommendation_prompt_asks_for_english_only_in_english():
    system_ko, _ = reco._build_prompt(_ctx())
    assert "Output language" not in system_ko
    with _english():
        system_en, _ = reco._build_prompt(_ctx())
    assert system_en.startswith(system_ko)
    assert "Output language" in system_en

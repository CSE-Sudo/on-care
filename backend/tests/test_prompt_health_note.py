"""건강상태·주의사항 글을 싣는 프롬프트는 그 칸의 경계를 함께 싣는다 (#1642).

`HealthProfile.conditions` 에는 건강 목표 칩과 함께 회원·담당 트레이너가 직접 적은
글이 들어간다. 그 값이 다섯 프롬프트에 그대로 실리는데 이 칸을 가리키는 경계가
없었다 — 대화 인용·트레이너 메모·음식 이름에는 있고 여기만 빠져 있었다.

경계는 칸 이름을 직접 가리키므로, 프롬프트 쪽 칸 이름이 바뀌면 경계가 가리키는
대상이 사라진다. 그 어긋남도 여기서 잡는다.
"""
from __future__ import annotations

import inspect

import pytest

from app.services import (
    diet_ai_sentence,
    diet_coach_inputs,
    diet_menu_plan,
    diet_recommendation_service,
    trainer_routine_options_service,
)
from app.services.coach import chat as coach_chat
from app.services.coach import prompt_safety
from tests.prompt_registry import ALL_PROMPTS

_NOTE = "무릎 통증으로 러닝 자제"


class _Profile:
    """`build_prompt` 가 읽는 칸만 가진 프로필."""

    conditions = f"체중 감량, {_NOTE}"


def _sentence_user() -> str:
    _, user = diet_ai_sentence.build_prompt(
        limit=40, finding="이번 주 나트륨을 3일 넘겼다.",
        records=["월 점심: 짬뽕"], notes=[], goal=_Profile.conditions,
    )
    return user


def _menu_plan_user() -> str:
    _, user = diet_menu_plan.build_prompt(
        profile=_Profile(),
        targets=diet_coach_inputs.DietTargets(2000, 80, 2000, 50),
        recent=diet_coach_inputs.DietDigest(0, 0, 0, 0, 0, {}, []),
        needs=[], notes=[], previous=(),
    )
    return user


def _recommendation_user() -> str:
    ctx = diet_recommendation_service.NutritionContext(
        days_with_data=3, avg_sodium_mg=2850, avg_sugar_g=10.0,
        avg_calories=1500, avg_protein_g=60.0, sodium_limit_mg=2000,
        sugar_limit_g=50, calorie_limit=2000, conditions=_Profile.conditions,
        goals="체중 감량", signals=("sodium_high",),
    )
    _, user = diet_recommendation_service._build_prompt(ctx)
    return user


#: 건강상태·주의사항 글을 싣는 프롬프트.
_CARRIERS = (
    "coach_chat", "diet_sentence", "diet_menu_plan", "diet_recommendation",
    "routine_options",
)


@pytest.mark.parametrize("name", _CARRIERS)
def test_prompts_that_carry_health_notes_state_the_boundary(name):
    assert prompt_safety.HEALTH_NOTE_GUARD in ALL_PROMPTS[name]()


@pytest.mark.parametrize("name", sorted(set(ALL_PROMPTS) - set(_CARRIERS)))
def test_prompts_without_health_notes_do_not_carry_the_boundary(name):
    """싣지 않는 칸의 경계를 적으면 모델이 없는 입력을 찾는다."""
    assert prompt_safety.HEALTH_NOTE_GUARD not in ALL_PROMPTS[name]()


@pytest.mark.parametrize("label", prompt_safety.HEALTH_NOTE_LABELS)
def test_the_boundary_names_every_label(label):
    assert label in prompt_safety.HEALTH_NOTE_GUARD


@pytest.mark.parametrize(
    "build, label",
    [
        (_sentence_user, "[목표]"),
        (_menu_plan_user, "건강 목표"),
        (_recommendation_user, "건강 상태"),
    ],
)
def test_diet_prompts_put_the_note_under_a_label_the_boundary_names(build, label):
    """회원·트레이너가 적은 글이 경계가 가리키는 칸 아래에 실제로 들어간다."""
    assert label in prompt_safety.HEALTH_NOTE_LABELS
    line = next(ln for ln in build().splitlines() if _NOTE in ln)
    assert label in line


def test_coach_chat_profile_line_uses_a_label_the_boundary_names():
    """챗은 프로필을 DB 에서 읽어 조립한다 — 칸 이름이 바뀌면 여기서 잡는다."""
    assert 'f"건강 상태: {profile.conditions' in inspect.getsource(coach_chat)
    assert "건강 상태" in prompt_safety.HEALTH_NOTE_LABELS


def test_routine_prompt_refers_to_conditions_by_the_named_key():
    assert "member_analysis.conditions" in trainer_routine_options_service._SYSTEM_PROMPT
    assert "conditions" in prompt_safety.HEALTH_NOTE_LABELS


def test_the_boundary_keeps_health_notes_in_play():
    """통증·부상은 반영해야 하는 주의사항이다 — 전부 무시하라고 하지 않는다."""
    guard = prompt_safety.HEALTH_NOTE_GUARD
    assert "반영" in guard
    assert "그 부분만 무시" in guard

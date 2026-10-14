"""식단을 평가하는 프롬프트는 같은 축으로 본다 (#1642).

식단 도메인 코치는 나트륨·당류만, 사진 식단평과 식단 계획은 칼로리·단백질·나트륨·
당류를 기준으로 삼아 같은 식단을 화면마다 다른 잣대로 평가했다. 축은
`grounding.DIET_AXIS` 한 곳에 있고, 프롬프트가 근거 삼으라고 하는 값을 실제로
적재하는지도 여기서 대조한다.

사진 인식 프롬프트가 엔진마다 따로 있던 것도 같은 문제였다 — 엔진을 바꾸면 같은
사진의 식단평이 달라졌다.
"""
from __future__ import annotations

import pytest

from app.services import diet_coach_inputs, diet_menu_plan
from app.services.coach import chat as coach_chat
from app.services.coach import domain_coaches, grounding, personal_ingest
from app.services.recognizer import gemini as gemini_recognizer
from app.services.recognizer import litellm_vision
from app.services.recognizer import prompt as recognizer_prompt


def test_the_axis_is_calories_protein_sodium_sugar():
    assert grounding.DIET_AXIS == ("칼로리", "단백질", "나트륨", "당류")
    assert grounding.DIET_AXIS_PHRASE == "칼로리·단백질·나트륨·당류"


def test_diet_coach_reads_diet_on_the_shared_axis():
    assert f"{grounding.DIET_AXIS_PHRASE} 관리를 중심으로" in domain_coaches._DIET_SYSTEM


def test_diet_coach_no_longer_narrows_to_sodium_and_sugar():
    """나트륨·당류만 보던 것은 폐기된 스타트 단계 타깃의 기준이다."""
    assert ", 나트륨·당류 관리를 중심으로" not in domain_coaches._DIET_SYSTEM


def test_photo_comment_reads_diet_on_the_shared_axis():
    assert f"식단 목표({grounding.DIET_AXIS_PHRASE})" in recognizer_prompt.RECOGNITION_PROMPT


@pytest.mark.parametrize("topic", grounding.DIET_AXIS)
def test_coach_chat_lists_every_axis_topic(topic):
    assert topic in coach_chat._SYSTEM


def test_menu_plan_hands_over_a_target_for_every_axis():
    """식단 계획은 축마다 하루 목표를 넘긴다 — 축이 늘면 목표 줄도 늘어야 한다."""
    _, user = diet_menu_plan.build_prompt(
        profile=None,
        targets=diet_coach_inputs.DietTargets(2000, 80, 2000, 50),
        recent=diet_coach_inputs.DietDigest(0, 0, 0, 0, 0, {}, []),
        needs=[], notes=[], previous=(),
    )
    target_line = next(ln for ln in user.splitlines() if ln.startswith("- 칼로리"))
    for topic in grounding.DIET_AXIS:
        assert topic in target_line


# ---- 적재: 프롬프트가 근거 삼으라는 값이 문서에 실제로 있다 ----


def _doc(**overrides) -> str:
    fields = dict(
        date="2026-10-14", foods=[{"name": "닭가슴살 샐러드"}],
        total_calories=420, sodium_mg=610, sugar_g=6.0, protein_g=38.0,
    )
    fields.update(overrides)
    return personal_ingest.diet_text(**fields)


@pytest.mark.parametrize(
    "topic, written",
    [("칼로리", "420kcal"), ("단백질", "단백질 38.0g"), ("나트륨", "나트륨 610mg"), ("당류", "당류 6.0g")],
)
def test_the_diet_document_carries_every_axis(topic, written):
    assert topic in grounding.DIET_AXIS
    assert written in _doc()


def test_every_axis_has_a_written_value():
    """축만 늘리고 적재를 잊으면 여기서 잡는다 — 위 표가 축을 전부 덮는다."""
    covered = {"칼로리", "단백질", "나트륨", "당류"}
    assert set(grounding.DIET_AXIS) == covered


def test_protein_is_cut_to_one_decimal():
    """float 을 그대로 찍으면 29.497999999999998 이 근거 문장에 들어간다."""
    assert "단백질 29.5g" in _doc(protein_g=29.497999999999998)


def test_unknown_protein_is_left_out_not_written_as_zero():
    """모르는 값을 0 으로 적으면 코치가 단백질을 안 먹었다고 답한다."""
    doc = _doc(protein_g=None)
    assert "단백질" not in doc
    assert "420kcal, 나트륨 610mg" in doc


def test_protein_is_optional_for_older_callers():
    doc = personal_ingest.diet_text(
        date="2026-10-14", foods=[], total_calories=1, sodium_mg=1, sugar_g=1.0
    )
    assert "단백질" not in doc


def test_zero_protein_is_a_real_value():
    """기록된 0g 은 모르는 값과 다르다 — 그대로 적는다."""
    assert "단백질 0.0g" in _doc(protein_g=0.0)


def test_record_diet_passes_protein_through(monkeypatch):
    seen = {}

    def fake_safe(db, user_id, text, **kwargs):
        seen["text"] = text

    monkeypatch.setattr(personal_ingest, "_safe", fake_safe)
    personal_ingest.record_diet(
        None, "u1", date="2026-10-14", foods=[{"name": "두부"}],
        total_calories=200, sodium_mg=300, sugar_g=2.0, protein_g=18.0,
    )
    assert "단백질 18.0g" in seen["text"]


# ---- 사진 인식 프롬프트는 엔진과 무관하게 하나다 ----


def test_both_engines_send_the_same_prompt():
    assert gemini_recognizer._PROMPT is recognizer_prompt.RECOGNITION_PROMPT
    assert litellm_vision._PROMPT is recognizer_prompt.RECOGNITION_PROMPT


def test_the_shared_prompt_keeps_the_recognition_contract():
    """합치면서 한쪽에만 있던 규칙이 빠지지 않았다."""
    prompt = recognizer_prompt.RECOGNITION_PROMPT
    for key in (
        "foods", "name", "amount_g", "calories", "carbs_g", "protein_g", "fat_g",
        "sodium_mg", "sugar_g", "confidence", "coach_comment",
    ):
        assert f'"{key}"' in prompt
    assert "음식이 보이지 않으면" in prompt and "빈 배열" in prompt
    assert "사진에 실제로 담긴 양" in prompt
    assert "null" in prompt

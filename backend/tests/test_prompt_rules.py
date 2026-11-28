"""문장을 만드는 프롬프트는 같은 답변 규칙을 싣는다 (#1642).

의학적 조언을 막는 문구가 프롬프트마다 다른 표현으로 적혀 있었고, 운동 도메인
코치에는 진단 금지도 근거 없는 단정 금지도 없었다. 회원에게 보이는 문장의 어투도
식단 조언 한 문장만 해요체를 명시해 화면마다 말끝이 달랐다.

두 문구는 `prompt_rules` 에 있고, 새 프롬프트가 빼먹으면 여기서 잡는다.
"""
from __future__ import annotations

import pytest

from app.services.coach import prompt_rules
from tests.prompt_registry import (
    ALL_PROMPTS,
    MEMBER_SENTENCE_PROMPTS,
    SENTENCE_PROMPTS,
)

#: 공통 문구로 옮기기 전에 프롬프트마다 따로 적혀 있던 표현.
_OLD_MEDICAL_WORDINGS = (
    "근거 없는 단정이나 의학적 진단은 피하고",
    "근거 없는 단정은 피하고",
    "의학적 진단이나 치료를 단정하지 말고",
    "의학적 진단·치료를 단정하지 않는다",
    "의학적 진단·치료를 단정하지 마라",
    "질환 이름을 꺼내거나 진단하지 마세요",
)


@pytest.mark.parametrize("name", sorted(SENTENCE_PROMPTS))
def test_every_sentence_prompt_carries_the_medical_guard(name):
    """문장을 만드는 프롬프트는 모두 같은 의학적 조언 금지 문구를 싣는다."""
    assert prompt_rules.MEDICAL_GUARD in SENTENCE_PROMPTS[name]()


@pytest.mark.parametrize("name", sorted(SENTENCE_PROMPTS))
def test_the_medical_guard_is_stated_once(name):
    """같은 문구를 두 번 싣지 않는다 — 조립 과정에서 겹쳐 들어가면 잡는다."""
    assert SENTENCE_PROMPTS[name]().count(prompt_rules.MEDICAL_GUARD) == 1


@pytest.mark.parametrize("name", sorted(ALL_PROMPTS))
def test_no_prompt_keeps_a_private_medical_wording(name):
    """옛 표현이 공통 문구 옆에 남아 있지 않다.

    남아 있으면 같은 뜻을 두 가지로 말하게 되고, 한쪽만 고쳤을 때 어느 쪽이 기준인지
    알 수 없다.
    """
    prompt = ALL_PROMPTS[name]()
    for wording in _OLD_MEDICAL_WORDINGS:
        assert wording not in prompt, f"{name} 프롬프트에 옛 표현이 남았다: {wording}"


@pytest.mark.parametrize("name", sorted(MEMBER_SENTENCE_PROMPTS))
def test_member_visible_sentences_share_one_voice(name):
    """회원에게 그대로 보이는 문장을 쓰는 프롬프트는 같은 어투 문구를 싣는다."""
    assert prompt_rules.MEMBER_VOICE in MEMBER_SENTENCE_PROMPTS[name]()


@pytest.mark.parametrize("name", ["routine_options", "diet_menu_plan"])
def test_label_prompts_do_not_ask_for_the_sentence_voice(name):
    """라벨을 쓰는 프롬프트에는 문장 어투를 요구하지 않는다.

    루틴 후보의 `reason` 과 식단 계획의 `keyword` 는 명사로 끝나는 짧은 라벨이다.
    규칙 폴백도 그렇게 쓰므로, 해요체를 요구하면 AI 결과와 폴백의 말끝이 갈린다.
    """
    assert prompt_rules.MEMBER_VOICE not in ALL_PROMPTS[name]()


def test_coach_chat_still_refers_severe_symptoms_to_a_doctor():
    """챗은 공통 문구에 더해 전문의 상담 권유를 따로 갖는다 — 자유 질문을 받는다."""
    assert "전문의 상담을 권하세요" in ALL_PROMPTS["coach_chat"]()


def test_the_medical_guard_does_not_forbid_estimates():
    """공통 문구가 추정치까지 막지 않는다.

    루틴 후보는 시간·세트를, 식단 계획과 사진 인식은 열량·영양 추정치를 만들어야
    한다. "자료에 없는 수치를 만들지 말라" 고 쓰면 그 프롬프트들의 일과 부딪힌다.
    """
    assert "수치" not in prompt_rules.MEDICAL_GUARD
    assert "진단" in prompt_rules.MEDICAL_GUARD
    assert "해요체" in prompt_rules.MEMBER_VOICE

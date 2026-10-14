"""모든 프롬프트가 같은 대상을 두고 말한다 (#1642).

프롬프트가 기능마다 따로 자라면서 대상 회원을 소개하는 말이 갈라졌다. 루틴 후보
프롬프트는 폐기된 스타트 단계의 타깃(`만성질환 위험군`)으로 시작했고, 나머지도
"PT 를 받는 회원", "한국인 식단을 코칭하는", "운동하는 회원" 으로 제각각이었다.
모델은 첫 줄의 대상 소개를 틀로 삼아 답하므로 한 곳만 어긋나도 그 화면만 다른
서비스처럼 답한다.

대상 소개는 `prompt_rules` 한 곳에 있고, 새 프롬프트가 그 문구를 빼먹거나 옛
타깃을 다시 들이면 여기서 잡는다. `test_coach_grounding` 의 같은 검사는 회원 코치
세 개만 본다 — 여기는 LLM 을 부르는 프롬프트 전부를 본다.
"""
from __future__ import annotations

import pytest

from app.services import trainer_routine_options_service
from app.services.coach import chat as coach_chat
from app.services.coach import grounding, prompt_rules
from tests.prompt_registry import ALL_PROMPTS as _ALL_PROMPTS
from tests.prompt_registry import MEMBER_PROMPTS as _MEMBER_PROMPTS


@pytest.mark.parametrize("name", sorted(_ALL_PROMPTS))
def test_no_prompt_introduces_the_discarded_audience(name):
    """어떤 프롬프트도 폐기된 스타트 단계 타깃을 대상으로 소개하지 않는다.

    현재 타깃은 PT 를 이용하는 회원과 이들을 관리하는 트레이너다. 안 재는 지표를
    **물었을 때**의 안내(`UNTRACKED_METRIC_NOTICE`)는 `혈압`·`혈당` 을 정당하게
    쓰므로 금지어에 넣지 않았다 — 막는 것은 대상 집단을 그렇게 못 박는 말이다.
    """
    prompt = _ALL_PROMPTS[name]().replace(grounding.UNTRACKED_METRIC_NOTICE, "")
    for term in prompt_rules.DISCARDED_AUDIENCE_TERMS:
        assert term not in prompt, f"{name} 프롬프트가 폐기된 타깃을 쓴다: {term}"


@pytest.mark.parametrize("name", sorted(_MEMBER_PROMPTS))
def test_member_facing_prompts_share_one_audience(name):
    """회원에게 가는 답을 만드는 프롬프트는 같은 말로 대상을 소개한다."""
    assert prompt_rules.MEMBER_AUDIENCE in _MEMBER_PROMPTS[name]()


def test_routine_options_prompt_speaks_of_a_pt_member():
    """루틴 후보는 담당 트레이너가 자기 회원을 두고 부른다 — PT 회원이라고 말한다."""
    prompt = trainer_routine_options_service._SYSTEM_PROMPT
    assert prompt.startswith(f"당신은 {prompt_rules.PT_MEMBER_AUDIENCE}의 ")


def test_coach_chat_keeps_its_own_audience():
    """회원 AI 코치 챗은 공통 문구를 쓰지 않는다 — 담당 트레이너가 없는 회원만 쓴다.

    담당 트레이너가 있는 회원에게는 챗이 열리지 않으므로(`api/v1/ai_coach.py` 의
    403), "혼자 관리하는 회원" 이 실제 대상과 맞는 말이다. 대상 소개를 통일한다고
    이 구분을 지우면 모델이 없는 트레이너를 전제로 답한다.
    """
    assert "담당 트레이너 없이 혼자 관리하는 회원" in coach_chat._SYSTEM


def test_member_audience_does_not_assume_a_trainer():
    """공통 대상 소개는 담당 트레이너가 없는 회원에게도 맞아야 한다."""
    assert "PT" not in prompt_rules.MEMBER_AUDIENCE
    assert "트레이너" not in prompt_rules.MEMBER_AUDIENCE
    for term in prompt_rules.DISCARDED_AUDIENCE_TERMS:
        assert term not in prompt_rules.MEMBER_AUDIENCE
        assert term not in prompt_rules.PT_MEMBER_AUDIENCE

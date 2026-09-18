"""프롬프트는 실제로 적재하는 것만 근거로 요구해야 한다 (#602).

혈압·혈당이 정확히 그 상태였다 — 프롬프트는 "내 건강 기록에 근거해 혈압·혈당 조언"
을 지시했지만 그 수치는 수집도 저장도 하지 않는다. 모델은 근거 없이 답하거나 공공
가이드라인 일반론만 되풀이했다.

적재 도메인이 늘 때 프롬프트를 같이 고치는 걸 잊으면 아무도 모르므로, 그 어긋남을
여기서 잡는다.
"""
from __future__ import annotations

import pytest

from app.services.coach import chat as coach_chat
from app.services.coach import domain_coaches, grounding, personal_ingest

#: 개인 기록을 근거로 삼으라고 지시하는 프롬프트 전부.
_GROUNDED_PROMPTS = {
    "coach_chat": lambda: coach_chat._SYSTEM,
    "diet_coach": lambda: domain_coaches._DIET_SYSTEM,
    "exercise_coach": lambda: domain_coaches._EXERCISE_SYSTEM,
}


@pytest.mark.parametrize("name", sorted(_GROUNDED_PROMPTS))
def test_prompts_never_ask_to_ground_on_an_untracked_metric(name):
    """안 재는 지표는 '기록에 근거해' 대상이 될 수 없다.

    문구 자체를 금지하지는 않는다 — 사용자가 물으면 답해야 하고, 그 지침이
    UNTRACKED_METRIC_NOTICE 다. 그 안내문 바깥에서 등장하면 실패다.
    """
    prompt = _GROUNDED_PROMPTS[name]()
    outside_notice = prompt.replace(grounding.UNTRACKED_METRIC_NOTICE, "")

    assert not grounding.mentions_untracked_metric(outside_notice), (
        f"{name} 프롬프트가 적재하지 않는 지표를 근거로 요구한다"
    )


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("고혈압·당뇨 위험군 사용자를 돕습니다", False),  # 질환명 = 대상 집단
        ("저혈당 위험이 있는 분", False),
        ("혈압 관리에 도움이 되는 운동", True),          # 지표 주장
        ("최근 혈당 수치를 보면", True),
        ("나트륨·당류·운동 관리를 중심으로", False),
    ],
)
def test_condition_names_are_not_metric_claims(text, expected):
    """'고혈압' 에 '혈압' 이 들어 있다 — 단순 부분문자열 검사는 대상 집단 표현까지 잡는다."""
    assert grounding.mentions_untracked_metric(text) is expected


@pytest.mark.parametrize("name", sorted(_GROUNDED_PROMPTS))
def test_every_grounded_prompt_states_what_is_not_tracked(name):
    """안내가 빠지면 모델이 사용자의 수치를 아는 것처럼 답한다."""
    assert grounding.UNTRACKED_METRIC_NOTICE in _GROUNDED_PROMPTS[name]()


def test_the_chat_prompt_lists_exactly_the_grounded_topics():
    for topic in grounding.GROUNDED_TOPICS:
        assert topic in coach_chat._SYSTEM


def test_grounded_topics_match_what_is_actually_ingested():
    """적재 도메인이 늘었는데 주제 목록이 그대로면 잡는다.

    `personal_ingest` 의 적재 진입점과 대조한다 — 식단(나트륨·당류), 운동, 채팅.
    채팅은 특정 지표가 아니라 맥락이라 주제 목록에는 없다.
    """
    assert hasattr(personal_ingest, "record_diet")
    assert hasattr(personal_ingest, "record_exercise")
    assert "운동" in grounding.GROUNDED_TOPICS
    # 식단에서 나오는 두 수치는 record_diet 가 실제로 문서에 적는 값이다.
    assert {"나트륨", "당류"} <= set(grounding.GROUNDED_TOPICS)


def test_untracked_metrics_have_no_ingest_entry_point():
    """되살리려면 적재 함수부터 생긴다 — 그 전에 프롬프트만 되돌리면 안 된다."""
    ingest_entry_points = {
        name for name in dir(personal_ingest) if name.startswith("record_")
    }

    assert ingest_entry_points == {"record_diet", "record_exercise", "record_chat"}


def test_fallback_replies_only_offer_what_can_be_answered():
    """안내 문구가 혈압·혈당을 물으라고 권하면 그 자리에서 신뢰를 잃는다.

    폴백은 LLM 이 없을 때 나가는 문구라 이 경로가 오히려 더 자주 보인다.
    """
    empty = coach_chat._fallback_reply({"personal": [], "public": []})
    with_personal = coach_chat._fallback_reply({"personal": [object()], "public": []})

    for reply in (empty, with_personal):
        assert not grounding.mentions_untracked_metric(reply)


@pytest.mark.parametrize("name", sorted(_GROUNDED_PROMPTS))
def test_prompts_do_not_claim_a_discarded_audience(name):
    """코치가 폐기된 타깃을 대상 집단으로 소개하지 않는다. (#2026)

    `고혈압·당뇨 위험군` 은 캡스톤 스타트 단계의 타깃이고 지금은 폐기됐다 —
    현재 타깃은 PT를 이용하는 회원과 트레이너다. 프롬프트가 그렇게 시작하면
    모델이 그 틀로 답하는데, 혈압·혈당은 제품에서 뺀 항목이라 앱이 재지도 않는다.

    안 재는 지표를 **물었을 때** 답하는 지침(`UNTRACKED_METRIC_NOTICE`)은 그대로
    둔다 — 막을 것은 대상 집단을 그렇게 못 박는 쪽이다.
    """
    prompt = _GROUNDED_PROMPTS[name]().replace(
        grounding.UNTRACKED_METRIC_NOTICE, ""
    )
    for term in ("고혈압", "당뇨", "만성질환"):
        assert term not in prompt, f"{name} 프롬프트가 폐기된 타깃을 쓴다: {term}"


def test_fallback_reply_offers_what_the_app_actually_records():
    """LLM 없이 내려가는 안내도 답할 수 있는 것만 권한다. (#602 · #2026)"""
    reply = coach_chat._fallback_reply({"public": [], "personal": []})
    assert "고혈압" not in reply and "당뇨" not in reply
    assert "식단" in reply and "운동" in reply

"""AI 코칭 시트 문구는 한국어 하나다(#2707, #3404). DB 필요.

회원 앱이 `Accept-Language` 로 무엇을 보내든 서버는 읽지 않는다. 여기서 보는 것:

  * 인사말과 식단·운동 규칙 문구(AI 가 실패했을 때의 폴백)가 `en` 요청에도 한국어다.
  * 시트가 잇는 `이번 주` 긴 문장을 만드는 AI 의 시스템 프롬프트에 출력 언어 규칙이
    붙지 않고, 카드 제목도 한국어다.
"""
from __future__ import annotations

import json
import re
from uuid import uuid4

import pytest

from app.core import clock
from app.core.week import monday_of
from app.models.models import ExerciseSession
from app.services import diet_ai_sentence, exercise_week_ai

EN = {"Accept-Language": "en"}
_HANGUL = re.compile("[가-힣]")


@pytest.fixture
def member(client) -> dict[str, str]:
    """새 회원의 인증 헤더. 이 경로는 회원 전용이고(#3351) 카드를 회원별로 캐시하므로
    테스트마다 새 회원을 쓴다."""
    email = f"coach-ko-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "test-pw-1234", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _card(body: dict, tag: str) -> dict:
    return next(s for s in body["suggestions"] if s["tag"] == tag)


@pytest.fixture
def no_llm(monkeypatch):
    """`이번 주` 조언의 AI 가 실패해 규칙 문구로 떨어지게 한다 — 환경의 키에 기대지 않는다."""

    def _fail(*_args, **_kwargs):
        raise RuntimeError("테스트: LLM 없음")

    monkeypatch.setattr(diet_ai_sentence, "_call_pair_llm", _fail)
    monkeypatch.setattr(exercise_week_ai, "_call_llm", _fail)


_DETAIL = "이번 주는 걷기를 꾸준히 이어 갔어요. 남은 날에는 가벼운 근력 운동을 한 번 더해 보세요."


class _RecordingLLM:
    """받은 시스템 프롬프트를 적어 두고 정해진 두 문장을 돌려준다."""

    def __init__(self) -> None:
        self.system_prompts: list[str] = []

    def __call__(self, system_prompt: str, user_prompt: str, **_kwargs) -> str:
        self.system_prompts.append(system_prompt)
        return json.dumps(
            {"sentence": "주말에 스트레칭을 더해요.", "detail": _DETAIL},
            ensure_ascii=False,
        )


@pytest.fixture
def recording_llm(monkeypatch) -> _RecordingLLM:
    llm = _RecordingLLM()
    monkeypatch.setattr(diet_ai_sentence, "_call_pair_llm", llm)
    monkeypatch.setattr(exercise_week_ai, "_call_llm", llm)
    return llm


@pytest.mark.parametrize("extra", [{}, EN, {"Accept-Language": "en-US,en;q=0.9"}])
def test_rule_texts_are_korean_whatever_the_header(client, no_llm, member, extra):
    r = client.get("/v1/ai-coach/feedback", headers={**member, **extra})
    assert r.status_code == 200
    body = r.json()
    assert "님" in body["greeting"]
    assert [s["tag"] for s in body["suggestions"]] == ["diet", "exercise"]
    for card in body["suggestions"]:
        assert _HANGUL.search(card["title"]), card
        assert _HANGUL.search(card["body"]), card


@pytest.mark.parametrize("extra", [{}, EN])
def test_the_coach_is_always_asked_with_the_korean_prompt(
    client, db_session, recording_llm, member, extra
):
    """시트가 잇는 긴 문장은 운동 탭 `이번 주` AI 가 만든다(#3549) — 그 프롬프트에도
    출력 언어 규칙이 붙지 않는다."""
    user_id = client.get("/v1/users/me", headers=member).json()["id"]
    db_session.add(
        ExerciseSession(
            id=f"ko-ex-{uuid4().hex[:8]}", user_id=user_id,
            week_start=monday_of(clock.today()).isoformat(), day_label="월",
            type="cardio", name="걷기", minutes=40, calories=150,
        )
    )
    db_session.commit()

    r = client.get("/v1/ai-coach/feedback", headers={**member, **extra})
    assert r.status_code == 200
    card = _card(r.json(), "exercise")
    assert _HANGUL.search(card["title"]), card
    assert card["body"].endswith(" " + _DETAIL)
    assert recording_llm.system_prompts
    assert all("Output language" not in p for p in recording_llm.system_prompts)

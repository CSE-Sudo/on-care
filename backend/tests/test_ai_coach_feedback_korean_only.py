"""AI 코칭 시트 문구는 한국어 하나다(#2707, #3404). DB 필요.

회원 앱이 `Accept-Language` 로 무엇을 보내든 서버는 읽지 않는다. 여기서 보는 것:

  * 인사말과 식단·운동 규칙 문구(AI 가 실패했을 때의 폴백)가 `en` 요청에도 한국어다.
  * AI 코치에게 넘기는 시스템 프롬프트에 출력 언어 규칙이 붙지 않고, 카드 제목도
    한국어다.
"""
from __future__ import annotations

import re
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.services.coach import domain_coaches

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
    """AI 코치가 실패해 규칙 문구로 떨어지게 한다 — 환경의 키에 기대지 않는다."""

    def _fail(*_args, **_kwargs):
        raise RuntimeError("테스트: LLM 없음")

    monkeypatch.setattr(domain_coaches, "get_coach_llm", _fail)


class _RecordingLLM:
    """받은 시스템 프롬프트를 적어 두고 정해진 문장을 돌려준다."""

    def __init__(self) -> None:
        self.system_prompts: list[str] = []

    def generate(self, system_prompt: str, user_prompt: str):
        self.system_prompts.append(system_prompt)
        return SimpleNamespace(text="저녁 식사 뒤 20분 걸어 보세요.")


@pytest.fixture
def recording_llm(monkeypatch) -> _RecordingLLM:
    llm = _RecordingLLM()
    monkeypatch.setattr(domain_coaches, "get_coach_llm", lambda *_a, **_k: llm)
    # 검색 자료가 없으면 LLM 을 부르지 않고 폴백한다 — 자료가 있는 것처럼 둔다.
    monkeypatch.setattr(
        domain_coaches, "retrieve_context", lambda *_a, **_k: "[참고 자료]\n- 걷기"
    )
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
    client, recording_llm, member, extra
):
    r = client.get("/v1/ai-coach/feedback", headers={**member, **extra})
    assert r.status_code == 200
    assert _card(r.json(), "exercise")["title"] == "오늘의 운동 코칭"
    assert recording_llm.system_prompts
    assert all("Output language" not in p for p in recording_llm.system_prompts)

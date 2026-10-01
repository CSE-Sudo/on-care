"""AI 코칭 시트 문구가 요청 언어를 따른다(#2707). DB 필요.

회원 앱은 화면 언어를 모든 요청의 `Accept-Language` 로 보낸다. 데모 코칭 카드는
앱 문구라 영어 화면에서 영어인데, 실서버는 서버가 만든 한국어 문장 그대로였다.
여기서 보는 것:

  * 영어 요청이면 인사말과 식단·운동 규칙 문구(AI 가 실패했을 때의 폴백)가 영어다.
  * 헤더가 없으면 지금까지처럼 한국어다.
  * AI 코치는 영어 요청일 때만 시스템 프롬프트 끝에 출력 언어 규칙이 붙고, 제목도
    영어다. 한국어 프롬프트는 그대로다.
"""
from __future__ import annotations

import re
from types import SimpleNamespace

import pytest

from app.services.coach import domain_coaches

EN = {"Accept-Language": "en"}
_HANGUL = re.compile("[가-힣]")


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
        return SimpleNamespace(text="Take a 20-minute walk after dinner.")


@pytest.fixture
def recording_llm(monkeypatch) -> _RecordingLLM:
    llm = _RecordingLLM()
    monkeypatch.setattr(domain_coaches, "get_coach_llm", lambda *_a, **_k: llm)
    # 검색 자료가 없으면 LLM 을 부르지 않고 폴백한다 — 자료가 있는 것처럼 둔다.
    monkeypatch.setattr(
        domain_coaches, "retrieve_context", lambda *_a, **_k: "[참고 자료]\n- 걷기"
    )
    return llm


def test_english_request_gets_english_rule_texts(client, no_llm):
    r = client.get("/v1/ai-coach/feedback", headers=EN)
    assert r.status_code == 200
    body = r.json()
    assert "님" not in body["greeting"]
    assert [s["tag"] for s in body["suggestions"]] == ["diet", "exercise"]
    for card in body["suggestions"]:
        assert not _HANGUL.search(card["title"]), card
        assert not _HANGUL.search(card["body"]), card


def test_without_header_stays_korean(client, no_llm):
    r = client.get("/v1/ai-coach/feedback")
    assert r.status_code == 200
    body = r.json()
    assert "님" in body["greeting"]
    for card in body["suggestions"]:
        assert _HANGUL.search(card["title"]), card


def test_english_request_asks_the_coach_for_english(client, recording_llm):
    r = client.get("/v1/ai-coach/feedback", headers=EN)
    assert r.status_code == 200
    exercise = _card(r.json(), "exercise")
    assert exercise["title"] == "Today's workout coaching"
    assert exercise["body"] == "Take a 20-minute walk after dinner."
    assert recording_llm.system_prompts
    assert all("Output language" in p for p in recording_llm.system_prompts)


def test_korean_request_keeps_the_korean_prompt(client, recording_llm):
    r = client.get("/v1/ai-coach/feedback")
    assert r.status_code == 200
    assert _card(r.json(), "exercise")["title"] == "오늘의 운동 코칭"
    assert recording_llm.system_prompts
    assert all("Output language" not in p for p in recording_llm.system_prompts)

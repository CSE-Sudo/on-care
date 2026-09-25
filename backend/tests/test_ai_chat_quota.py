"""AI 챗봇 하루 한도 — 무료 대화와 포인트로 여는 추가 대화. (#2145) DB 필요(로컬 skip, CI 실행)."""
from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.models.models import HealthProfile
from app.services.coach.llm_base import LLMResult


@pytest.fixture
def llm(monkeypatch):
    """AI 가 답하는 환경. `fail` 을 참으로 두면 검색 기반 대체 답이 나온다."""
    from app.services.coach import chat as chat_service

    state = {"fail": False}

    class _StubLLM:
        def generate(self, system_prompt: str, user_prompt: str) -> LLMResult:
            if state["fail"]:
                raise RuntimeError("LLM 장애")
            return LLMResult(text="물을 한 컵 더 드세요.", model="stub")

    monkeypatch.setattr(chat_service, "get_coach_llm", lambda *a, **k: _StubLLM())
    return state


@pytest.fixture
def small_limits(monkeypatch):
    """무료 1회, 포인트 1회(50P) — 경계를 짧게 본다."""
    settings = get_settings()
    monkeypatch.setattr(settings, "coach_chat_free_per_day", 1)
    monkeypatch.setattr(settings, "coach_chat_paid_per_day", 1)
    monkeypatch.setattr(settings, "coach_chat_paid_cost", 50)


def _member(client, db_session, points: int) -> dict[str, str]:
    email = f"quota-{uuid4().hex[:8]}@oncare.com"
    client.post(
        "/v1/auth/register", json={"email": email, "password": "pw!", "name": "u"}
    )
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "pw!"}
    ).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    member_id = client.get("/v1/users/me", headers=headers).json()["id"]
    db_session.expire_all()
    profile = db_session.scalar(
        select(HealthProfile).where(HealthProfile.user_id == member_id)
    )
    if profile is None:
        db_session.add(HealthProfile(user_id=member_id, activity_points=points))
    else:
        profile.activity_points = points
    db_session.commit()
    return headers


def _send(client, headers, **extra):
    return client.post(
        "/v1/ai-coach/chat", headers=headers, json={"message": "물 얼마나?", **extra}
    )


def test_free_then_paid_then_daily_limit(client, db_session, llm, small_limits):
    h = _member(client, db_session, points=100)

    # AI 가 답하지 못한 대화는 무료 횟수를 쓰지 않는다.
    llm["fail"] = True
    assert _send(client, h).json()["quota"]["free_left"] == 1
    llm["fail"] = False

    assert _send(client, h).json()["points_spent"] == 0
    # 무료를 다 쓴 뒤에는 동의가 있어야 포인트로 보낸다.
    blocked = _send(client, h)
    assert blocked.status_code == 402
    assert blocked.json()["detail"]["code"] == "points_required"

    key = uuid4().hex
    paid = _send(client, h, pay_with_points=True, client_request_id=key).json()
    assert (paid["points_spent"], paid["balance_after"]) == (50, 50)
    # 재전송은 두 번 차감하지 않는다.
    again = _send(client, h, pay_with_points=True, client_request_id=key).json()
    assert again["balance_after"] == 50
    assert client.get("/v1/ai-coach/quota", headers=h).json()["next"] == "exhausted"

    limit = _send(client, h, pay_with_points=True)
    assert (limit.status_code, limit.json()["detail"]["code"]) == (429, "daily_limit")
    # 저장된 대화에서도 산 답변 아래에 차감을 다시 그린다.
    spent = [
        m["points_spent"]
        for m in client.get("/v1/ai-coach/messages", headers=h).json()["messages"]
        if m["role"] != "user"
    ]
    assert spent.count(50) == 1


def test_paid_chat_needs_enough_points(client, db_session, llm, small_limits):
    h = _member(client, db_session, points=10)
    _send(client, h)

    r = _send(client, h, pay_with_points=True)

    assert r.status_code == 409
    assert (r.json()["detail"]["code"], r.json()["detail"]["shortfall"]) == (
        "insufficient_points",
        40,
    )


def test_free_per_day_is_five(client, db_session, llm):
    """기본 무료는 하루 5회다(#2217). 여섯 번째부터 포인트 동의를 묻는다."""
    h = _member(client, db_session, points=0)

    for turn in range(5):
        r = _send(client, h)
        assert r.status_code == 200
        assert r.json()["quota"]["free_left"] == 4 - turn

    blocked = _send(client, h)
    assert blocked.status_code == 402
    assert blocked.json()["detail"]["code"] == "points_required"

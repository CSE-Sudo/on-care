"""트레이너 AI 코칭 API 삭제와 남은 트레이너 스레드의 격리. (#3085)

트레이너가 회원에 대해 AI 에게 묻던 `/trainer/clients/{id}/ai-coach`(#588)는 트레이너
웹 어디에서도 부르지 않아 지웠다. 그 API 가 남긴 스레드는 `AiConversation(user_id=회원,
trainer_id=트레이너)` 에 트레이너 질문을 `role="user"` 로 담고 있어, 회원 대화를 읽는
곳이 `user_id` 만 보면 트레이너가 한 말이 회원 발화로 읽혔다. 마이그레이션 0147 이
그 스레드를 지우지만, 지우기 전이나 다른 경로로 생겨도 새지 않게 조회에서도 막는다.

LLM 은 호출하지 않는다.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

import pytest
from sqlalchemy import select, text

from app.core.security import hash_password
from app.models import models
from app.models.models import AiConversation, AiMessage
from app.services import auto_routine_service
from app.services.coach import conversation
from app.services.coach.chat import _insight_context

TRAINER_QUESTION = "이 회원 무릎이 아프다던데 하체 루틴 괜찮을까?"

_MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "0147_drop_trainer_ai_threads.py"
)


@pytest.fixture(autouse=True)
def _no_llm(monkeypatch):
    def _boom(*args, **kwargs):
        raise RuntimeError("LLM disabled in tests")

    monkeypatch.setattr("app.services.coach.chat.get_coach_llm", _boom)
    yield


def _login(client, username: str, password: str = "oncare123") -> dict[str, str]:
    r = client.post("/v1/auth/login", data={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _member(client) -> tuple[str, dict[str, str]]:
    """담당 트레이너가 없는 새 회원 — AI 챗봇과 감지 기록을 쓸 수 있다."""
    email = f"noai-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register", json={"email": email, "password": "noai-pw-12", "name": "감지"}
    )
    assert r.status_code == 201, r.text
    return r.json()["id"], _login(client, email, "noai-pw-12")


def _trainer(db_session) -> str:
    trainer_id = f"user-noai-tr-{uuid4().hex[:8]}"
    db_session.add(
        models.User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="예전 트레이너",
            hashed_password=hash_password("test-pw-1234"),
            role="trainer",
        )
    )
    db_session.commit()
    return trainer_id


def _trainer_thread(db_session, member_id: str, trainer_id: str) -> tuple[str, str]:
    """예전 API 가 남긴 모양 그대로 트레이너 스레드를 만든다. (스레드 id, 질문 id)"""
    convo = AiConversation(
        id=f"aiconv-noai-{uuid4().hex[:8]}", user_id=member_id, trainer_id=trainer_id
    )
    db_session.add(convo)
    db_session.flush()
    question_id = f"aimsg-noai-{uuid4().hex[:8]}"
    db_session.add_all(
        [
            AiMessage(
                id=question_id,
                conversation_id=convo.id,
                seq=0,
                role="user",
                content=TRAINER_QUESTION,
                sources_json="[]",
            ),
            AiMessage(
                id=f"aimsg-noai-{uuid4().hex[:8]}",
                conversation_id=convo.id,
                seq=1,
                role="coach",
                content="하체 부하를 낮추세요",
                sources_json="[]",
            ),
        ]
    )
    db_session.commit()
    return convo.id, question_id


# ---- API 삭제 ----


@pytest.mark.parametrize("method", ["GET", "POST"])
def test_trainer_ai_coach_route_is_gone(client, method):
    headers = _login(client, "trainer@oncare.com")
    member_id = client.get("/v1/trainer/clients", headers=headers).json()[0]["id"]

    r = client.request(
        method,
        f"/v1/trainer/clients/{member_id}/ai-coach",
        headers=headers,
        json={"message": "이 회원 식단 어때요?"} if method == "POST" else None,
    )

    assert r.status_code == 404, r.text


def test_trainer_ai_coach_is_not_in_openapi(client):
    paths = client.get("/openapi.json").json()["paths"]
    assert not [p for p in paths if p.startswith("/v1/trainer/") and p.endswith("/ai-coach")]


# ---- 남은 트레이너 스레드 격리 ----


def test_trainer_thread_is_not_a_member_insight(client, db_session):
    member_id, headers = _member(client)
    _trainer_thread(db_session, member_id, _trainer(db_session))

    listed = client.get("/v1/ai-coach/insights", headers=headers)
    assert listed.status_code == 200, listed.text
    assert listed.json()["insights"] == []

    history = client.get("/v1/ai-coach/messages", headers=headers)
    assert history.status_code == 200, history.text
    assert history.json()["messages"] == []


def test_member_cannot_dismiss_a_trainer_thread_message(client, db_session):
    member_id, headers = _member(client)
    _, question_id = _trainer_thread(db_session, member_id, _trainer(db_session))

    r = client.delete(f"/v1/ai-coach/insights/{question_id}", headers=headers)

    assert r.status_code == 404, r.text
    db_session.expire_all()
    assert db_session.get(AiMessage, question_id).insight_dismissed is False


def test_trainer_thread_stays_out_of_coach_context_and_auto_routine(client, db_session):
    member_id, _ = _member(client)
    _trainer_thread(db_session, member_id, _trainer(db_session))

    assert _insight_context(db_session, member_id) == ""
    # 무릎 불편이 세어지면 체중을 싣는 종목이 빠진다 — 그대로여야 한다.
    assert auto_routine_service._adjust_for_insights(db_session, member_id) == list(
        auto_routine_service.SAFE_ROUTINES
    )


def test_member_own_thread_is_still_detected(client, db_session):
    """대조군 — 같은 회원의 본인 대화는 그대로 감지된다."""
    member_id, headers = _member(client)
    _trainer_thread(db_session, member_id, _trainer(db_session))
    conversation.append_exchange(
        db_session, member_id, question="무릎이 아파요", reply="쉬어 가세요", sources=[]
    )

    listed = client.get("/v1/ai-coach/insights", headers=headers).json()["insights"]

    assert [i["text"] for i in listed] == ["무릎이 아파요"]
    assert "무릎: 1회" in _insight_context(db_session, member_id)


# ---- 마이그레이션 0147 ----


def _load_migration():
    spec = importlib.util.spec_from_file_location("m0147", _MIGRATION)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_migration_drops_only_trainer_threads(client, db_session):
    member_id, _ = _member(client)
    trainer_convo, _ = _trainer_thread(db_session, member_id, _trainer(db_session))
    member_convo = conversation.append_exchange(
        db_session, member_id, question="무릎이 아파요", reply="쉬어 가세요", sources=[]
    )

    migration = _load_migration()
    with patch.object(
        migration.op, "execute", side_effect=lambda sql: db_session.execute(text(sql))
    ):
        migration.purge()
    db_session.commit()
    db_session.expire_all()

    assert db_session.get(AiConversation, trainer_convo) is None
    assert (
        db_session.scalars(
            select(AiMessage.id).where(AiMessage.conversation_id == trainer_convo)
        ).all()
        == []
    )
    assert db_session.get(AiConversation, member_convo.id) is not None
    assert [m.content for m in conversation.load_messages(db_session, member_id)] == [
        "무릎이 아파요",
        "쉬어 가세요",
    ]

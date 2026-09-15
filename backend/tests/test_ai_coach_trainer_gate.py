"""담당 트레이너가 있는 회원의 AI 챗봇 차단과 대화 30일 보관. (#1823)

트레이너가 연결된 회원은 AI 챗봇 대신 트레이너와 채팅한다. 앱이 입구를 숨기는 것과
별개로 서버가 대화 경로를 거절해야 한다. 회원 본인 AI 대화는 최근 30일만 복원하고,
새 대화를 저장할 때 그보다 오래된 메시지를 지운다. 트레이너가 회원에 대해 묻는
스레드는 이 보관 규칙의 대상이 아니다.

LLM 은 호출하지 않는다 — 검색 기반 폴백으로 고정한다.
"""
from __future__ import annotations

from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select, update

from app.core import clock
from app.core.security import hash_password
from app.models import models
from app.models.models import AiConversation, AiMessage
from app.services.coach import conversation


@pytest.fixture(autouse=True)
def _no_llm(monkeypatch):
    def _boom(*args, **kwargs):
        raise RuntimeError("LLM disabled in tests")

    monkeypatch.setattr("app.services.coach.chat.get_coach_llm", _boom)
    yield


def _member(client) -> tuple[str, dict]:
    email = f"gate-{uuid4().hex[:10]}@oncare.com"
    r = client.post(
        "/v1/auth/register", json={"email": email, "password": "gate-pw-12", "name": "게이트"}
    )
    assert r.status_code == 201, r.text
    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "gate-pw-12"}
    ).json()["access_token"]
    return r.json()["id"], {"Authorization": f"Bearer {token}"}


def _trainer(db_session) -> str:
    trainer_id = f"user-gate-tr-{uuid4().hex[:8]}"
    db_session.add(
        models.User(
            id=trainer_id,
            email=f"{trainer_id}@oncare.com",
            name="게이트 트레이너",
            hashed_password=hash_password("pw!"),
            role="trainer",
        )
    )
    db_session.commit()
    return trainer_id


def _link(db_session, trainer_id: str, member_id: str, *, active: bool) -> None:
    db_session.add(
        models.TrainerClient(
            id=f"tc-gate-{uuid4().hex[:10]}",
            trainer_id=trainer_id,
            member_id=member_id,
            active=active,
        )
    )
    db_session.commit()


def _age(db_session, convo_id: str, contents: list[str], days: int) -> None:
    db_session.execute(
        update(AiMessage)
        .where(AiMessage.conversation_id == convo_id, AiMessage.content.in_(contents))
        .values(created_at=clock.now() - timedelta(days=days))
    )
    db_session.commit()


def test_member_with_trainer_cannot_use_ai_chat(client, db_session):
    """활성 담당 링크가 있으면 대화 복원·보내기·감지 기록이 모두 403 이고, 스레드도 남지 않는다."""
    member_id, headers = _member(client)
    _link(db_session, _trainer(db_session), member_id, active=True)

    sent = client.post("/v1/ai-coach/chat", json={"message": "무릎이 아파요"}, headers=headers)
    assert sent.status_code == 403, sent.text
    assert "트레이너" in sent.json()["detail"]
    assert client.get("/v1/ai-coach/messages", headers=headers).status_code == 403
    assert client.get("/v1/ai-coach/insights", headers=headers).status_code == 403

    threads = db_session.scalar(
        select(func.count()).select_from(AiConversation).where(
            AiConversation.user_id == member_id
        )
    )
    assert threads == 0


def test_member_with_only_dormant_link_keeps_ai_chat(client, db_session):
    """휴면(비활성) 링크만 남은 회원은 담당이 없는 회원이다 — AI 챗봇을 그대로 쓴다."""
    member_id, headers = _member(client)
    _link(db_session, _trainer(db_session), member_id, active=False)

    sent = client.post("/v1/ai-coach/chat", json={"message": "나트륨 줄이는 법"}, headers=headers)
    assert sent.status_code == 200, sent.text

    history = client.get("/v1/ai-coach/messages", headers=headers)
    assert history.status_code == 200, history.text
    assert [m["role"] for m in history.json()["messages"]] == ["user", "coach"]


def test_member_without_trainer_keeps_ai_chat(client):
    _, headers = _member(client)

    sent = client.post("/v1/ai-coach/chat", json={"message": "단백질 얼마나 먹어요"}, headers=headers)
    assert sent.status_code == 200, sent.text
    assert client.get("/v1/ai-coach/insights", headers=headers).status_code == 200


def test_history_keeps_only_the_last_30_days(client, db_session):
    """30일이 지난 대화는 복원하지 않고, 새 대화를 저장할 때 지운다. 29일 전 대화는 남는다."""
    member_id, headers = _member(client)
    convo = conversation.append_exchange(
        db_session, member_id, question="예전 질문", reply="예전 답", sources=[]
    )
    conversation.append_exchange(
        db_session, member_id, question="얼마 전 질문", reply="얼마 전 답", sources=[]
    )
    _age(db_session, convo.id, ["예전 질문", "예전 답"], days=31)
    _age(db_session, convo.id, ["얼마 전 질문", "얼마 전 답"], days=29)

    history = client.get("/v1/ai-coach/messages", headers=headers)
    assert history.status_code == 200, history.text
    assert [m["content"] for m in history.json()["messages"]] == ["얼마 전 질문", "얼마 전 답"]

    sent = client.post("/v1/ai-coach/chat", json={"message": "오늘 질문"}, headers=headers)
    assert sent.status_code == 200, sent.text

    db_session.expire_all()
    remaining = db_session.scalars(
        select(AiMessage.content)
        .where(AiMessage.conversation_id == convo.id)
        .order_by(AiMessage.seq)
    ).all()
    assert "예전 질문" not in remaining
    assert "예전 답" not in remaining
    assert remaining[:3] == ["얼마 전 질문", "얼마 전 답", "오늘 질문"]


def test_trainer_thread_is_not_trimmed(client, db_session):
    """트레이너가 회원에 대해 AI 에게 묻는 스레드는 회원 챗봇 보관 규칙을 따르지 않는다."""
    member_id, _ = _member(client)
    trainer_id = _trainer(db_session)
    convo = conversation.append_exchange(
        db_session,
        member_id,
        question="회원 식단 요약",
        reply="요약",
        sources=[],
        trainer_id=trainer_id,
    )
    _age(db_session, convo.id, ["회원 식단 요약", "요약"], days=45)

    assert conversation.purge_expired_messages(db_session, member_id) == 0
    db_session.commit()

    kept = conversation.load_messages(db_session, member_id, trainer_id=trainer_id)
    assert [m.content for m in kept] == ["회원 식단 요약", "요약"]

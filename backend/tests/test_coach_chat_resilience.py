"""검색이 죽어도 AI 코치는 답한다 (#1543).

생성(LLM) 실패에는 처음부터 규칙 기반 폴백이 걸려 있었지만, **검색**은 그 경계
밖에서 돌았다. 질의 임베딩은 외부 provider 호출이라 timeout·429 로 흔히 실패하는데,
그 실패가 그대로 500 이 되면 임베딩 서비스 장애 하나가 회원·트레이너 AI 코치 전체
장애가 된다. 여기서 두 실패(검색/생성)를 각각 재현해 두 경우 모두 응답이 나가고
대화가 저장되는 것을 고정한다.
"""
from __future__ import annotations

import logging
import uuid

import pytest
from sqlalchemy import select
from sqlalchemy import text as sa_text

from app.models.models import AiConversation, AiMessage, User
from app.services.coach.rag import ingest_document


def _h(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(autouse=True)
def _no_llm(monkeypatch):
    """LLM 을 항상 실패시켜 폴백 경로만 본다(결정론 + 네트워크 차단)."""
    def _boom(*args, **kwargs):
        raise RuntimeError("LLM disabled in tests")

    monkeypatch.setattr("app.services.coach.chat.get_coach_llm", _boom)


@pytest.fixture
def member(client, db_session):
    """대화가 비어 있는 새 회원 — 이전 테스트의 히스토리에 걸리지 않게."""
    from app.core.security import hash_password

    email = f"chat-resilience-{uuid.uuid4().hex[:8]}@example.com"
    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=email, name="폴백 테스트",
        hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user)
    db_session.commit()

    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    return user, token


def _stored_messages(db_session, user_id: str) -> list[AiMessage]:
    convo = db_session.scalar(
        select(AiConversation).where(
            AiConversation.user_id == user_id,
            AiConversation.trainer_id.is_(None),
        )
    )
    if convo is None:
        return []
    return list(
        db_session.scalars(
            select(AiMessage)
            .where(AiMessage.conversation_id == convo.id)
            .order_by(AiMessage.created_at, AiMessage.id)
        ).all()
    )


def _fail_retrieve(monkeypatch, message: str = "embedding provider timeout") -> None:
    """질의 임베딩 실패를 재현한다 — 실제로 가장 흔한 검색 실패 원인이다."""
    def _boom(*args, **kwargs):
        raise TimeoutError(message)

    monkeypatch.setattr("app.services.coach.chat.retrieve", _boom)


def test_chat_answers_when_retrieve_fails(client, db_session, member, monkeypatch):
    """검색이 터져도 500 이 아니라 규칙 기반 답변이 나가고, 대화도 저장된다."""
    user, token = member
    _fail_retrieve(monkeypatch)

    r = client.post(
        "/v1/ai-coach/chat", json={"message": "요즘 나트륨을 줄이고 싶어요"},
        headers=_h(token),
    )

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["reply"].strip()
    # 근거를 하나도 못 찾았으므로 출처는 비어야 한다 — 있지도 않은 자료를
    # 인용한 것처럼 보이면 폴백이 더 나쁜 답이 된다.
    assert body["sources"] == []

    # 저장까지 이어져야 진짜 정상 응답이다. 검색이 DB 쪽에서 깨졌을 때 세션을
    # 정리하지 않으면 여기서 다시 터진다.
    stored = _stored_messages(db_session, user.id)
    assert sorted(m.role for m in stored) == ["coach", "user"]
    assert body["reply"] in [m.content for m in stored]


def test_retrieve_failure_reason_is_logged(client, member, monkeypatch, caplog):
    """장애 원인이 로그에 남아야 한다 — 조용한 폴백은 원인 추적을 막는다."""
    _, token = member
    _fail_retrieve(monkeypatch, "gemini embed 429 rate limited")

    with caplog.at_level(logging.ERROR, logger="app.services.coach.chat"):
        r = client.post(
            "/v1/ai-coach/chat", json={"message": "운동을 어떻게 시작할까요"},
            headers=_h(token),
        )

    assert r.status_code == 200, r.text
    assert "gemini embed 429 rate limited" in caplog.text
    assert "RAG 검색 실패" in caplog.text


def test_chat_answers_when_retrieve_breaks_the_session(client, db_session, member):
    """검색이 **DB 쪽에서** 깨진 경우도 응답과 저장이 이어진다.

    임베딩 실패와 달리 이때는 세션이 실패한 트랜잭션에 갇힌다. 폴백 답변만 만들고
    세션을 그대로 두면 뒤따르는 대화 저장이 다시 터져 결국 500 이 된다.
    """
    user, token = member

    def _broken_retrieve(db, *args, **kwargs):
        db.execute(sa_text("SELECT * FROM 없는테이블_1543"))  # 트랜잭션 오염
        raise AssertionError("여기에 닿지 않는다")

    with pytest.MonkeyPatch.context() as mp:
        mp.setattr("app.services.coach.chat.retrieve", _broken_retrieve)
        r = client.post(
            "/v1/ai-coach/chat", json={"message": "오늘 뭘 먹을까요"},
            headers=_h(token),
        )

    assert r.status_code == 200, r.text
    assert sorted(m.role for m in _stored_messages(db_session, user.id)) == [
        "coach", "user",
    ]


def test_chat_answers_when_generation_fails(client, db_session, member):
    """생성만 실패한 경우는 검색 근거를 인용하는 기존 폴백 그대로다."""
    _, token = member
    title = f"저염 식단 가이드 {uuid.uuid4().hex[:6]}"
    content = "나트륨은 하루 2000mg 이하로 줄이는 것이 좋습니다."
    ingest_document(
        db_session, content, user_id=None, domain="diet",
        source="test", title=title,
    )

    # `_no_llm` 이 생성만 막고 검색은 그대로 둔다.
    r = client.post(
        "/v1/ai-coach/chat", json={"message": content}, headers=_h(token),
    )

    assert r.status_code == 200, r.text
    body = r.json()
    assert title in body["sources"]
    assert content in body["reply"]

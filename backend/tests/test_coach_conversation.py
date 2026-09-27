"""AI 코치 대화 영속화(#274).

`/ai-coach/chat` 은 원래 무상태라 재접속·다기기에서 대화가 사라졌다. 여기서
저장·복원 계약을 고정한다.

LLM 은 호출하지 않는다. 실 Gemini 는 CI 에 키가 없어 재현이 안 되고, 여기서 보려는
건 답변 품질이 아니라 "무엇이 어떤 순서로 저장되고 복원되는가"이기 때문이다.
LLM 을 실패시키면 검색 기반 폴백 경로가 도는데, 그 경로에서도 저장이 되어야 한다는
것 자체가 검증 대상이다(graceful degrade).
"""
from __future__ import annotations

import uuid
from threading import Barrier, Lock, Thread

import pytest
from sqlalchemy import delete, select

from app.models.models import AiConversation, AiMessage, User
from app.services.coach import conversation


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(autouse=True)
def _no_llm(monkeypatch):
    """LLM 을 항상 실패시켜 검색 기반 폴백으로 고정한다(결정론 + 네트워크 차단)."""
    def _boom(*args, **kwargs):
        raise RuntimeError("LLM disabled in tests")

    monkeypatch.setattr("app.services.coach.chat.get_coach_llm", _boom)
    yield


@pytest.fixture
def member(client, db_session):
    """대화가 비어 있는 새 회원. 테스트 간 히스토리 오염을 피한다."""
    from app.core.security import hash_password

    email = f"coach-chat-{uuid.uuid4().hex[:8]}@example.com"
    user = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=email, name="대화 테스트",
        hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user)
    db_session.commit()

    token = client.post(
        "/v1/auth/login", data={"username": email, "password": "test-pw-1234"}
    ).json()["access_token"]
    yield user, token

    convo_ids = [
        c.id for c in db_session.scalars(
            __import__("sqlalchemy").select(AiConversation).where(
                AiConversation.user_id == user.id
            )
        )
    ]
    if convo_ids:
        db_session.execute(
            delete(AiMessage).where(AiMessage.conversation_id.in_(convo_ids))
        )
    db_session.execute(delete(AiConversation).where(AiConversation.user_id == user.id))
    db_session.execute(delete(User).where(User.id == user.id))
    db_session.commit()


def test_history_is_empty_before_any_chat(client, member):
    _, token = member
    body = client.get("/v1/ai-coach/messages", headers=_h(token)).json()
    assert body["messages"] == []


def test_reading_history_does_not_create_a_conversation(client, db_session, member):
    """채팅 화면만 열고 아무 말도 안 한 사용자에게 빈 대화 레코드를 남기지 않는다."""
    import sqlalchemy as sa

    user, token = member
    client.get("/v1/ai-coach/messages", headers=_h(token))

    count = db_session.scalar(
        sa.select(sa.func.count()).select_from(AiConversation).where(
            AiConversation.user_id == user.id
        )
    )
    assert count == 0


def test_chat_persists_question_and_reply_in_order(client, member):
    """#274 수용 기준: 재접속에서 히스토리가 유지된다.

    순서가 핵심이다 — created_at 으로 정렬하면 안 된다. PostgreSQL 의 now() 는
    트랜잭션 시각이라 같은 커밋의 질문·답변이 동일한 값을 갖고, 실제로 답변이
    질문보다 먼저 나왔다. seq 로 고정한다.
    """
    _, token = member
    res = client.post(
        "/v1/ai-coach/chat", json={"message": "나트륨 줄이는 법 알려주세요"},
        headers=_h(token),
    )
    assert res.status_code == 200
    reply = res.json()["reply"]
    assert reply  # LLM 이 죽어도 폴백 답변이 온다

    messages = client.get("/v1/ai-coach/messages", headers=_h(token)).json()["messages"]
    assert [m["role"] for m in messages] == ["user", "coach"]
    assert messages[0]["content"] == "나트륨 줄이는 법 알려주세요"
    assert messages[1]["content"] == reply


def test_multiple_turns_keep_their_order(client, member):
    _, token = member
    for i in range(3):
        client.post(
            "/v1/ai-coach/chat", json={"message": f"질문 {i}"}, headers=_h(token)
        )

    messages = client.get("/v1/ai-coach/messages", headers=_h(token)).json()["messages"]
    assert [m["role"] for m in messages] == ["user", "coach"] * 3
    assert [m["content"] for m in messages if m["role"] == "user"] == [
        "질문 0", "질문 1", "질문 2",
    ]


def test_concurrent_exchanges_share_one_thread_and_keep_unique_sequence(
    client, db_session, member, monkeypatch,
):
    """동시 첫 요청도 한 스레드와 연속된 질문·답변 순번으로 저장된다."""
    from app.db.session import SessionLocal

    user, _ = member
    user_id = user.id
    ready = Barrier(2)
    original_new_id = conversation._new_id

    def synchronized_new_id(prefix: str) -> str:
        value = original_new_id(prefix)
        if prefix == "aiconv":
            # 두 요청 모두 '활성 스레드 없음'을 확인한 뒤 INSERT 하게 해 생성 경쟁을
            # 결정적으로 재현한다. 유니크 인덱스가 없으면 스레드가 둘 생긴다.
            ready.wait(timeout=10)
        return value

    monkeypatch.setattr(conversation, "_new_id", synchronized_new_id)

    errors: list[Exception] = []
    error_lock = Lock()

    def append(question: str) -> None:
        try:
            with SessionLocal() as session:
                conversation.append_exchange(
                    session,
                    user_id,
                    question=question,
                    reply=f"{question} 답변",
                    sources=[],
                )
        except Exception as exc:  # noqa: BLE001 — 작업 스레드 오류를 본 테스트로 전달
            with error_lock:
                errors.append(exc)

    threads = [Thread(target=append, args=(f"동시 질문 {i}",)) for i in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=15)

    assert all(not thread.is_alive() for thread in threads), "동시 저장이 교착됐습니다."
    assert errors == []

    db_session.expire_all()
    conversations = db_session.scalars(
        select(AiConversation).where(
            AiConversation.user_id == user_id,
            AiConversation.archived_at.is_(None),
        )
    ).all()
    assert len(conversations) == 1

    messages = db_session.scalars(
        select(AiMessage)
        .where(AiMessage.conversation_id == conversations[0].id)
        .order_by(AiMessage.seq)
    ).all()
    assert [message.seq for message in messages] == [0, 1, 2, 3]
    assert [message.role for message in messages] == ["user", "coach"] * 2
    for question, reply in zip(messages[::2], messages[1::2], strict=True):
        assert reply.content == f"{question.content} 답변"


def test_sources_survive_a_reload(client, member):
    """복원했을 때 근거가 사라지면 왜 그렇게 답했는지 되짚을 수 없다."""
    _, token = member
    sent = client.post(
        "/v1/ai-coach/chat", json={"message": "나트륨"}, headers=_h(token)
    ).json()

    messages = client.get("/v1/ai-coach/messages", headers=_h(token)).json()["messages"]
    coach_turn = messages[1]
    assert coach_turn["sources"] == sent["sources"]
    assert messages[0]["sources"] == []  # 사용자 발화엔 근거가 없다


def test_history_is_isolated_per_user(client, db_session, member):
    """다른 사용자의 대화가 섞이면 개인정보 유출이다."""
    from app.core.security import hash_password

    user_a, token_a = member
    client.post("/v1/ai-coach/chat", json={"message": "A 의 비밀"}, headers=_h(token_a))

    email_b = f"coach-other-{uuid.uuid4().hex[:8]}@example.com"
    user_b = User(
        id=f"user-{uuid.uuid4().hex[:12]}", email=email_b, name="다른 사용자",
        hashed_password=hash_password("test-pw-1234"), role="member",
    )
    db_session.add(user_b)
    db_session.commit()
    try:
        token_b = client.post(
            "/v1/auth/login", data={"username": email_b, "password": "test-pw-1234"}
        ).json()["access_token"]
        body = client.get("/v1/ai-coach/messages", headers=_h(token_b)).json()
        assert body["messages"] == []
    finally:
        db_session.execute(delete(User).where(User.id == user_b.id))
        db_session.commit()


def test_server_history_is_used_without_client_history(client, db_session, member):
    """클라가 history 를 안 보내도 서버 저장분이 맥락으로 쓰인다.

    이게 성립해야 다른 기기에서 대화를 이어받을 수 있다.
    """
    user, token = member
    client.post("/v1/ai-coach/chat", json={"message": "첫 질문"}, headers=_h(token))

    stored = conversation.load_messages(db_session, user.id)
    assert [m.role for m in stored] == ["user", "coach"]
    assert stored[0].content == "첫 질문"
    assert stored[0].seq < stored[1].seq


def test_empty_message_is_rejected_and_stores_nothing(client, member):
    user, token = member
    assert client.post(
        "/v1/ai-coach/chat", json={"message": "   "}, headers=_h(token)
    ).status_code == 400
    assert client.get("/v1/ai-coach/messages", headers=_h(token)).json()["messages"] == []


def test_parse_sources_survives_corrupt_values():
    """저장값이 깨져도 화면이 죽으면 안 된다."""
    assert conversation.parse_sources('["a", "b"]') == ["a", "b"]
    assert conversation.parse_sources("") == []
    assert conversation.parse_sources("not json") == []
    assert conversation.parse_sources('{"not": "a list"}') == []
